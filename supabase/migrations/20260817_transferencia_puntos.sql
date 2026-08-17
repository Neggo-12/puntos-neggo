-- Fase 6, sub-tarea 4 (última): transferencia punto a punto
-- (modelo-economico-v1.md sección 5, requisito de V1 con controles).
--
-- Límites de antifraude -- PROPUESTOS por mí, no confirmados por Jhey todavía
-- (la spec sección 11 los deja explícitamente abiertos: "Límites diario/mensual de
-- transferencia persona a persona -- sin definir todavía"). Se implementan como
-- constantes fáciles de ubicar y cambiar en una sola migración futura, nunca se
-- presentan como decisión cerrada:
--   - Máximo por transferencia individual: 2.000 puntos ($20.000)
--   - Máximo diario por cliente emisor: 3.000 puntos ($30.000)
--   - Máximo mensual por cliente emisor: 10.000 puntos ($100.000)
--   - Máximo de transferencias por día: 3 (evita fraccionar una transferencia grande
--     en muchas chicas para esquivar el límite por transferencia)
--
-- Controles de la spec que este ledger SÍ puede aplicar: destinatario registrado,
-- límite diario/mensual, trazabilidad completa (ledger + audit_log), bloqueo de
-- transferencias sospechosas (reutiliza estado=congelado / bloqueo_redencion ya
-- construidos en la sub-tarea de reversos).
--
-- Controles de la spec que este ledger NO puede aplicar todavía, documentado, no
-- inventado: "usuario verificado" -- no existe verificación de identidad real en
-- neggo-12 (punto ciego ya documentado en la skill puntos-neggo-engineering, no se
-- resuelve acá) -- y "confirmación adicional" -- es una responsabilidad de UX del
-- producto que llama (Neggo/Talleres), no de este ledger.
--
-- Preservación de vencimiento del lote de origen (sección 5): un cliente puede tener
-- saldo compuesto por varios lotes con distintas fechas de vencimiento. La
-- transferencia recorre esos lotes en el mismo orden FIFO que ya usa el barrido de
-- vencimientos (_pendiente_por_lote) y crea, en el destinatario, una fila
-- 'transferido_entrada' POR CADA LOTE DE ORIGEN QUE TOCÓ, cada una con la
-- fecha_vencimiento original -- nunca una fecha nueva. Por eso _pendiente_por_lote
-- se actualiza para tratar 'transferido_entrada' como lote (además de 'ganado') --
-- así el saldo recibido por transferencia también vence y es transferible/canjeable
-- correctamente en el futuro.

comment on function public._pendiente_por_lote(text) is 'Actualizada para esta migración: los lotes de un cliente ahora son tipo ganado O transferido_entrada (ambos representan puntos que entraron con su propia fecha_vencimiento). El consumo sigue siendo canjeado/transferido_salida/vencido.';

create or replace function public._pendiente_por_lote(p_cliente_id text)
returns table(movimiento_id text, puntos_lote integer, fecha_vencimiento date, puntos_restantes integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_total_consumido numeric;
  v_restante_a_consumir numeric;
  r record;
  v_consumido_de_este_lote numeric;
begin
  select coalesce(sum(-pm.puntos), 0) into v_total_consumido
  from public.puntos_movimientos pm
  where pm.cliente_id = p_cliente_id
    and pm.tipo in ('canjeado', 'transferido_salida', 'vencido');

  v_restante_a_consumir := v_total_consumido;

  for r in
    select pm.id, pm.puntos, pm.fecha_vencimiento
    from public.puntos_movimientos pm
    where pm.cliente_id = p_cliente_id and pm.tipo in ('ganado', 'transferido_entrada')
    order by pm.fecha_vencimiento asc, pm.created_at asc
  loop
    v_consumido_de_este_lote := least(r.puntos::numeric, v_restante_a_consumir);
    v_restante_a_consumir := v_restante_a_consumir - v_consumido_de_este_lote;

    movimiento_id := r.id;
    puntos_lote := r.puntos;
    fecha_vencimiento := r.fecha_vencimiento;
    puntos_restantes := (r.puntos - v_consumido_de_este_lote)::integer;
    return next;
  end loop;
end;
$$;

-- idempotencia: mismo patrón que otorgar_puntos, un índice único parcial por tipo.
create unique index idx_puntos_movimientos_referencia_unica_transferencia
on public.puntos_movimientos(origen_producto, referencia_externa)
where tipo = 'transferido_salida' and referencia_externa is not null;

create or replace function public.transferir_puntos(
  p_tipo_documento_origen text,
  p_numero_documento_origen text,
  p_tipo_documento_destino text,
  p_numero_documento_destino text,
  p_puntos integer,
  p_origen_producto text,
  p_referencia_externa text default null,
  p_motivo text default null
)
returns table(
  cliente_origen_id text,
  cliente_destino_id text,
  puntos_transferidos integer,
  saldo_nuevo_origen integer,
  saldo_nuevo_destino integer,
  ya_procesado boolean
)
language plpgsql
security definer
set search_path = public
as $$
declare
  c_max_por_transferencia constant integer := 2000;
  c_max_diario constant integer := 3000;
  c_max_mensual constant integer := 10000;
  c_max_transferencias_dia constant integer := 3;

  v_origen_id text;
  v_origen_estado text;
  v_origen_bloqueo boolean;
  v_origen_saldo integer;
  v_destino_id text;
  v_destino_estado text;
  v_consumido_hoy numeric;
  v_consumido_mes numeric;
  v_transferencias_hoy integer;
  v_movimiento_existente record;
  v_saldo_origen_nuevo integer;
  v_saldo_destino_nuevo integer;
  v_lote record;
  v_restante integer;
  v_a_consumir integer;
begin
  if p_puntos is null or p_puntos <= 0 then
    raise exception 'puntos debe ser mayor a cero';
  end if;
  if p_origen_producto is null then
    raise exception 'origen_producto es obligatorio';
  end if;
  if p_puntos > c_max_por_transferencia then
    raise exception 'Máximo % puntos por transferencia', c_max_por_transferencia;
  end if;

  if p_referencia_externa is not null then
    select pm.puntos into v_movimiento_existente
    from public.puntos_movimientos pm
    where pm.origen_producto = p_origen_producto
      and pm.referencia_externa = p_referencia_externa
      and pm.tipo = 'transferido_salida';

    if found then
      select cp.id into v_origen_id from public.clientes_puntos cp
        where cp.tipo_documento = p_tipo_documento_origen and cp.numero_documento = p_numero_documento_origen;
      select cp.id into v_destino_id from public.clientes_puntos cp
        where cp.tipo_documento = p_tipo_documento_destino and cp.numero_documento = p_numero_documento_destino;
      select cp.saldo into v_saldo_origen_nuevo from public.clientes_puntos cp where cp.id = v_origen_id;
      select cp.saldo into v_saldo_destino_nuevo from public.clientes_puntos cp where cp.id = v_destino_id;
      return query select v_origen_id, v_destino_id, -v_movimiento_existente.puntos, v_saldo_origen_nuevo, v_saldo_destino_nuevo, true;
      return;
    end if;
  end if;

  select cp.id, cp.estado, cp.bloqueo_redencion, cp.saldo
  into v_origen_id, v_origen_estado, v_origen_bloqueo, v_origen_saldo
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento_origen and cp.numero_documento = p_numero_documento_origen
  for update;

  if v_origen_id is null then
    raise exception 'Cliente origen no encontrado';
  end if;
  if v_origen_estado = 'congelado' then
    raise exception 'Cliente origen congelado (posible fraude) -- no puede transferir puntos';
  end if;
  if v_origen_bloqueo then
    raise exception 'Cuenta origen marcada como sospechosa -- transferencias bloqueadas';
  end if;

  select cp.id, cp.estado
  into v_destino_id, v_destino_estado
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento_destino and cp.numero_documento = p_numero_documento_destino
  for update;

  if v_destino_id is null then
    raise exception 'Cliente destinatario no encontrado -- debe estar registrado';
  end if;
  if v_destino_id = v_origen_id then
    raise exception 'No se puede transferir puntos a la misma cuenta';
  end if;
  if v_destino_estado = 'congelado' then
    raise exception 'Cliente destinatario congelado -- no puede recibir puntos';
  end if;

  if v_origen_saldo < p_puntos then
    raise exception 'Saldo insuficiente: tiene % puntos, intenta transferir %', v_origen_saldo, p_puntos;
  end if;

  select coalesce(sum(-pm.puntos), 0) into v_consumido_hoy
  from public.puntos_movimientos pm
  where pm.cliente_id = v_origen_id and pm.tipo = 'transferido_salida' and pm.created_at >= current_date;

  if v_consumido_hoy + p_puntos > c_max_diario then
    raise exception 'Límite diario de transferencia superado (máximo % puntos/día)', c_max_diario;
  end if;

  select coalesce(sum(-pm.puntos), 0) into v_consumido_mes
  from public.puntos_movimientos pm
  where pm.cliente_id = v_origen_id and pm.tipo = 'transferido_salida' and pm.created_at >= date_trunc('month', now());

  if v_consumido_mes + p_puntos > c_max_mensual then
    raise exception 'Límite mensual de transferencia superado (máximo % puntos/mes)', c_max_mensual;
  end if;

  select count(*) into v_transferencias_hoy
  from public.puntos_movimientos pm
  where pm.cliente_id = v_origen_id and pm.tipo = 'transferido_salida' and pm.created_at >= current_date;

  if v_transferencias_hoy >= c_max_transferencias_dia then
    raise exception 'Límite de % transferencias por día alcanzado', c_max_transferencias_dia;
  end if;

  -- FIFO calculado ANTES de insertar nada -- necesito el saldo por lote previo a
  -- esta transferencia. Una fila en destino por cada lote de origen que se toca,
  -- cada una con la fecha_vencimiento original de ese lote.
  v_restante := p_puntos;
  for v_lote in
    select * from public._pendiente_por_lote(v_origen_id) pl
    where pl.puntos_restantes > 0
    order by pl.fecha_vencimiento asc
  loop
    exit when v_restante <= 0;
    v_a_consumir := least(v_lote.puntos_restantes, v_restante);

    insert into public.puntos_movimientos (cliente_id, tipo, puntos, lote_origen_id, origen_producto, motivo, fecha_vencimiento)
    values (v_destino_id, 'transferido_entrada', v_a_consumir, v_lote.movimiento_id, p_origen_producto, p_motivo, v_lote.fecha_vencimiento);

    v_restante := v_restante - v_a_consumir;
  end loop;

  if v_restante > 0 then
    raise exception 'Inconsistencia interna: no se pudo asignar % puntos a lotes de origen (saldo desincronizado)', v_restante;
  end if;

  insert into public.puntos_movimientos (cliente_id, tipo, puntos, origen_producto, referencia_externa, motivo)
  values (v_origen_id, 'transferido_salida', -p_puntos, p_origen_producto, p_referencia_externa, p_motivo);

  update public.clientes_puntos set saldo = saldo - p_puntos where id = v_origen_id
  returning saldo into v_saldo_origen_nuevo;

  update public.clientes_puntos set saldo = saldo + p_puntos where id = v_destino_id
  returning saldo into v_saldo_destino_nuevo;

  perform public._log_audit('puntos.transferido', p_origen_producto, v_origen_id,
    jsonb_build_object('puntos', p_puntos, 'clienteDestinoId', v_destino_id, 'referenciaExterna', p_referencia_externa));

  return query select v_origen_id, v_destino_id, p_puntos, v_saldo_origen_nuevo, v_saldo_destino_nuevo, false;
end;
$$;

-- Lección aplicada de la sesión anterior: revocar SIEMPRE de public, anon Y
-- authenticated explícitamente, nunca asumir que revocar de public alcanza.
revoke execute on function public.transferir_puntos(text, text, text, text, integer, text, text, text) from public, anon, authenticated;
grant execute on function public.transferir_puntos(text, text, text, text, integer, text, text, text) to service_role;
