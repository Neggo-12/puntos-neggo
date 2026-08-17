-- Fix: otorgar_puntos fallaba en runtime ("column reference cliente_id is ambiguous") porque
-- RETURNS TABLE(cliente_id text, ...) declara cliente_id como variable PL/pgSQL implícita,
-- que colisiona con la columna cliente_id de puntos_movimientos en el chequeo de "cliente
-- nuevo". El CREATE FUNCTION original no lo detectó porque plpgsql compila el cuerpo recién
-- en la primera ejecución real -- encontrado recién al probar la función con datos reales
-- (skill puntos-neggo-verification). Se corrige calificando la columna con el alias de tabla.

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

  select cp.id into v_cliente_id
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento;

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

revoke execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text) from public;
grant execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text) to service_role;
