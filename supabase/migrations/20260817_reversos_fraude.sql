-- Fase 6, sub-tarea: reversos y fraude (modelo-economico-v1.md sección 9, requisito
-- de V1 no opcional).
--
-- Cubre:
-- 1) Cancelación de compra / devolución -> reversión de puntos (revertir_puntos_otorgados).
-- 2) Fraude detectado -> congelamiento de cuenta, bloquea otorgar_puntos Y solicitar_canje
--    (congelar_cliente/descongelar_cliente).
-- 3) Cuenta sospechosa -> bloqueo de redención, NO de acumulación, tal cual lo pide la
--    spec explícitamente (bloquear_redencion_cliente/desbloquear_redencion_cliente).
-- 4) Transacción duplicada -> ya cubierto desde la Fase 1 (idempotencia por
--    referencia_externa en otorgar_puntos) -- no se toca acá.
--
-- Decisión técnica documentada, no inventada: qué pasa si se cancela una compra pero
-- el cliente ya gastó esos puntos (canje, transferencia o vencimiento). La spec no
-- cubre este caso límite. El diseño conservador que se eligió: nunca se permite saldo
-- negativo (el constraint clientes_puntos_saldo_no_negativo ya lo garantiza a nivel de
-- base de datos), así que la reversión recupera como máximo lo que el cliente todavía
-- tiene disponible, y lo que no se pudo recuperar queda registrado explícitamente en
-- audit_log (puntos_no_recuperados) para que Jhey lo revise manualmente -- no se
-- inventa un modelo de "deuda"/saldo negativo sin que él lo decida.

alter table public.clientes_puntos
  add column estado text not null default 'activo' check (estado in ('activo', 'congelado')),
  add column bloqueo_redencion boolean not null default false;

comment on column public.clientes_puntos.estado is 'congelado = fraude confirmado, bloquea otorgar_puntos y solicitar_canje por completo.';
comment on column public.clientes_puntos.bloqueo_redencion is 'true = cuenta sospechosa, bloquea solo solicitar_canje -- sigue pudiendo acumular puntos (modelo-economico-v1.md sección 9).';

comment on column public.puntos_movimientos.lote_origen_id is 'Referencia al movimiento tipo ganado (lote) del que salen estos puntos -- usado por movimientos tipo vencido (barrido automático) y tipo revertido (reversión manual/automática de una compra cancelada).';

-- otorgar_puntos: agrega el chequeo de cuenta congelada. Resto del cuerpo sin cambios
-- respecto a la versión vigente (verificado con pg_get_functiondef antes de escribir esto).
create or replace function public.otorgar_puntos(
  p_tipo_documento text,
  p_numero_documento text,
  p_valor_compra numeric,
  p_comercio_id text,
  p_origen_producto text,
  p_referencia_externa text default null,
  p_motivo text default null
)
returns table(cliente_id text, puntos_otorgados integer, multiplicador integer, saldo_nuevo integer, ya_procesado boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id text;
  v_estado text;
  v_puntos_base integer;
  v_multiplicador integer := 1;
  v_puntos integer;
  v_saldo_nuevo integer;
  v_es_cliente_nuevo boolean;
  v_movimiento_existente record;
begin
  if p_tipo_documento is null or p_numero_documento is null then
    raise exception 'tipo_documento y numero_documento son obligatorios';
  end if;
  if p_valor_compra is null or p_valor_compra <= 0 then
    raise exception 'valor_compra debe ser mayor a cero';
  end if;
  if p_comercio_id is null or p_origen_producto is null then
    raise exception 'comercio_id y origen_producto son obligatorios';
  end if;

  insert into public.clientes_puntos (tipo_documento, numero_documento)
  values (p_tipo_documento, p_numero_documento)
  on conflict (tipo_documento, numero_documento) do nothing;

  select cp.id, cp.estado into v_cliente_id, v_estado
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento;

  if v_estado = 'congelado' then
    raise exception 'Cliente congelado (posible fraude) -- no se pueden otorgar puntos hasta descongelar la cuenta';
  end if;

  if p_referencia_externa is not null then
    select pm.puntos, pm.multiplicador into v_movimiento_existente
    from public.puntos_movimientos pm
    where pm.origen_producto = p_origen_producto
      and pm.referencia_externa = p_referencia_externa
      and pm.tipo = 'ganado';

    if found then
      select cp.saldo into v_saldo_nuevo from public.clientes_puntos cp where cp.id = v_cliente_id;
      return query select v_cliente_id, v_movimiento_existente.puntos, v_movimiento_existente.multiplicador, v_saldo_nuevo, true;
      return;
    end if;
  end if;

  select not exists (
    select 1 from public.puntos_movimientos pm
    where pm.cliente_id = v_cliente_id and pm.tipo = 'ganado' and pm.comercio_origen_id = p_comercio_id
  ) into v_es_cliente_nuevo;

  if v_es_cliente_nuevo then
    v_multiplicador := 2;
  end if;

  v_puntos_base := floor(p_valor_compra / 800);
  v_puntos := v_puntos_base * v_multiplicador;

  if v_puntos <= 0 then
    select cp.saldo into v_saldo_nuevo from public.clientes_puntos cp where cp.id = v_cliente_id;
    return query select v_cliente_id, 0, v_multiplicador, v_saldo_nuevo, false;
    return;
  end if;

  insert into public.puntos_movimientos (cliente_id, tipo, puntos, valor_compra, multiplicador, comercio_origen_id, origen_producto, referencia_externa, motivo, fecha_vencimiento)
  values (v_cliente_id, 'ganado', v_puntos, p_valor_compra, v_multiplicador, p_comercio_id, p_origen_producto, p_referencia_externa, p_motivo, (now() + interval '12 months')::date);

  update public.clientes_puntos
  set saldo = saldo + v_puntos
  where id = v_cliente_id
  returning saldo into v_saldo_nuevo;

  if not found then
    raise exception 'No se pudo actualizar el saldo del cliente %', v_cliente_id;
  end if;

  perform public._log_audit('puntos.otorgado', p_origen_producto, v_cliente_id,
    jsonb_build_object('puntos', v_puntos, 'multiplicador', v_multiplicador, 'comercioId', p_comercio_id, 'referenciaExterna', p_referencia_externa));

  return query select v_cliente_id, v_puntos, v_multiplicador, v_saldo_nuevo, false;
end;
$$;

-- solicitar_canje: agrega el chequeo de congelado (bloquea todo) y bloqueo_redencion
-- (bloquea solo esto). Resto del cuerpo sin cambios respecto a la versión vigente.
create or replace function public.solicitar_canje(
  p_tipo_documento text,
  p_numero_documento text,
  p_comercio_id text,
  p_comercio_nombre text,
  p_puntos integer
)
returns table(canje_id text, codigo_verificacion text, saldo_nuevo integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id text;
  v_saldo integer;
  v_estado text;
  v_bloqueo_redencion boolean;
  v_movimiento_id text;
  v_canje_id text;
  v_codigo text;
  v_saldo_nuevo integer;
begin
  if p_puntos is null or p_puntos < 200 then
    raise exception 'La redención mínima es 200 puntos';
  end if;
  if p_comercio_id is null or p_comercio_nombre is null then
    raise exception 'comercio_id y comercio_nombre son obligatorios';
  end if;

  select cp.id, cp.saldo, cp.estado, cp.bloqueo_redencion
  into v_cliente_id, v_saldo, v_estado, v_bloqueo_redencion
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento
  for update;

  if v_cliente_id is null then
    raise exception 'Cliente no encontrado';
  end if;

  if v_estado = 'congelado' then
    raise exception 'Cliente congelado (posible fraude) -- no se pueden solicitar canjes hasta descongelar la cuenta';
  end if;

  if v_bloqueo_redencion then
    raise exception 'Cuenta marcada como sospechosa -- redención bloqueada, sigue acumulando puntos con normalidad';
  end if;

  if v_saldo < p_puntos then
    raise exception 'Saldo insuficiente: tiene % puntos, intenta canjear %', v_saldo, p_puntos;
  end if;

  insert into public.puntos_movimientos (cliente_id, tipo, puntos, comercio_origen_id, origen_producto, motivo)
  values (v_cliente_id, 'canjeado', -p_puntos, p_comercio_id, 'solicitud_canje', 'Canje solicitado')
  returning id into v_movimiento_id;

  update public.clientes_puntos
  set saldo = saldo - p_puntos
  where id = v_cliente_id
  returning saldo into v_saldo_nuevo;

  if not found then
    raise exception 'No se pudo actualizar el saldo del cliente %', v_cliente_id;
  end if;

  insert into public.canjes as c (cliente_id, comercio_id, comercio_nombre, puntos, valor_cop, movimiento_id)
  values (v_cliente_id, p_comercio_id, p_comercio_nombre, p_puntos, p_puntos * 10, v_movimiento_id)
  returning c.id, c.codigo_verificacion into v_canje_id, v_codigo;

  update public.puntos_movimientos set canje_id = v_canje_id where id = v_movimiento_id;

  perform public._log_audit('puntos.canje_solicitado', p_comercio_id, v_cliente_id,
    jsonb_build_object('puntos', p_puntos, 'canjeId', v_canje_id));

  return query select v_canje_id, v_codigo, v_saldo_nuevo;
end;
$$;

-- revertir_puntos_otorgados: mismo modelo de acceso que otorgar_puntos/solicitar_canje
-- (solo service_role, vía Edge Function server-a-servidor -- Neggo/Talleres son quienes
-- saben cuándo se cancela/devuelve una compra, no un admin humano). Idempotente: si la
-- referencia ya fue revertida, devuelve el resultado anterior en vez de reprocesar.
create or replace function public.revertir_puntos_otorgados(
  p_origen_producto text,
  p_referencia_externa text,
  p_motivo text default null
)
returns table(cliente_id text, puntos_revertidos integer, puntos_no_recuperados integer, saldo_nuevo integer, ya_procesado boolean)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_movimiento_original record;
  v_reversion_existente record;
  v_saldo integer;
  v_a_revertir integer;
  v_no_recuperado integer;
  v_saldo_nuevo integer;
begin
  if p_origen_producto is null or p_referencia_externa is null then
    raise exception 'origen_producto y referencia_externa son obligatorios';
  end if;

  select pm.id, pm.cliente_id, pm.puntos into v_movimiento_original
  from public.puntos_movimientos pm
  where pm.origen_producto = p_origen_producto
    and pm.referencia_externa = p_referencia_externa
    and pm.tipo = 'ganado';

  if not found then
    raise exception 'No existe un movimiento "ganado" con origen_producto=% y referencia_externa=%', p_origen_producto, p_referencia_externa;
  end if;

  select pm.puntos into v_reversion_existente
  from public.puntos_movimientos pm
  where pm.lote_origen_id = v_movimiento_original.id and pm.tipo = 'revertido';

  if found then
    select cp.saldo into v_saldo_nuevo from public.clientes_puntos cp where cp.id = v_movimiento_original.cliente_id;
    return query select v_movimiento_original.cliente_id, -v_reversion_existente.puntos,
      (v_movimiento_original.puntos + v_reversion_existente.puntos), v_saldo_nuevo, true;
    return;
  end if;

  select cp.saldo into v_saldo from public.clientes_puntos cp where cp.id = v_movimiento_original.cliente_id for update;

  v_a_revertir := least(v_movimiento_original.puntos, v_saldo);
  v_no_recuperado := v_movimiento_original.puntos - v_a_revertir;

  if v_a_revertir > 0 then
    insert into public.puntos_movimientos (cliente_id, tipo, puntos, lote_origen_id, origen_producto, motivo)
    values (v_movimiento_original.cliente_id, 'revertido', -v_a_revertir, v_movimiento_original.id, p_origen_producto, p_motivo);

    update public.clientes_puntos
    set saldo = saldo - v_a_revertir
    where id = v_movimiento_original.cliente_id
    returning saldo into v_saldo_nuevo;
  else
    v_saldo_nuevo := v_saldo;
  end if;

  perform public._log_audit('puntos.revertido', p_origen_producto, v_movimiento_original.cliente_id,
    jsonb_build_object('puntosRevertidos', v_a_revertir, 'puntosNoRecuperados', v_no_recuperado,
      'referenciaExterna', p_referencia_externa, 'motivo', p_motivo));

  return query select v_movimiento_original.cliente_id, v_a_revertir, v_no_recuperado, v_saldo_nuevo, false;
end;
$$;

revoke execute on function public.revertir_puntos_otorgados(text, text, text) from public;
grant execute on function public.revertir_puntos_otorgados(text, text, text) to service_role;

-- congelar_cliente / descongelar_cliente / bloquear_redencion_cliente /
-- desbloquear_redencion_cliente: acciones de admin humano (Jhey desde el panel),
-- mismo patrón de autorización que marcar_canje_pagado (is_admin()).
create or replace function public.congelar_cliente(p_cliente_id text, p_motivo text default null)
returns table(cliente_id text, estado text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.clientes_puntos as cp
  set estado = 'congelado'
  where cp.id = p_cliente_id
  returning cp.id, cp.estado into cliente_id, estado;

  if not found then
    raise exception 'Cliente % no existe', p_cliente_id;
  end if;

  perform public._log_audit('puntos.cliente_congelado', auth.uid()::text, p_cliente_id, jsonb_build_object('motivo', p_motivo));

  return next;
end;
$$;

create or replace function public.descongelar_cliente(p_cliente_id text, p_motivo text default null)
returns table(cliente_id text, estado text)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.clientes_puntos as cp
  set estado = 'activo'
  where cp.id = p_cliente_id
  returning cp.id, cp.estado into cliente_id, estado;

  if not found then
    raise exception 'Cliente % no existe', p_cliente_id;
  end if;

  perform public._log_audit('puntos.cliente_descongelado', auth.uid()::text, p_cliente_id, jsonb_build_object('motivo', p_motivo));

  return next;
end;
$$;

create or replace function public.bloquear_redencion_cliente(p_cliente_id text, p_motivo text default null)
returns table(cliente_id text, bloqueo_redencion boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.clientes_puntos as cp
  set bloqueo_redencion = true
  where cp.id = p_cliente_id
  returning cp.id, cp.bloqueo_redencion into cliente_id, bloqueo_redencion;

  if not found then
    raise exception 'Cliente % no existe', p_cliente_id;
  end if;

  perform public._log_audit('puntos.redencion_bloqueada', auth.uid()::text, p_cliente_id, jsonb_build_object('motivo', p_motivo));

  return next;
end;
$$;

create or replace function public.desbloquear_redencion_cliente(p_cliente_id text, p_motivo text default null)
returns table(cliente_id text, bloqueo_redencion boolean)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'No autorizado';
  end if;

  update public.clientes_puntos as cp
  set bloqueo_redencion = false
  where cp.id = p_cliente_id
  returning cp.id, cp.bloqueo_redencion into cliente_id, bloqueo_redencion;

  if not found then
    raise exception 'Cliente % no existe', p_cliente_id;
  end if;

  perform public._log_audit('puntos.redencion_desbloqueada', auth.uid()::text, p_cliente_id, jsonb_build_object('motivo', p_motivo));

  return next;
end;
$$;

revoke execute on function public.congelar_cliente(text, text) from public;
grant execute on function public.congelar_cliente(text, text) to authenticated;

revoke execute on function public.descongelar_cliente(text, text) from public;
grant execute on function public.descongelar_cliente(text, text) to authenticated;

revoke execute on function public.bloquear_redencion_cliente(text, text) from public;
grant execute on function public.bloquear_redencion_cliente(text, text) to authenticated;

revoke execute on function public.desbloquear_redencion_cliente(text, text) from public;
grant execute on function public.desbloquear_redencion_cliente(text, text) to authenticated;
