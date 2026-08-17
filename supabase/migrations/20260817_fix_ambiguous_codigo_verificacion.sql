-- Fix: mismo patrón de bug que 20260817_fix_ambiguous_cliente_id.sql, esta vez en
-- solicitar_canje -- RETURNS TABLE(..., codigo_verificacion text, ...) colisiona con la
-- columna canjes.codigo_verificacion en el "RETURNING id, codigo_verificacion". Confirmado
-- fallando en runtime con datos reales antes de corregir.

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

  select cp.id, cp.saldo into v_cliente_id, v_saldo
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento
  for update;

  if v_cliente_id is null then
    raise exception 'Cliente no encontrado';
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

revoke execute on function public.solicitar_canje(text, text, text, text, integer) from public;
grant execute on function public.solicitar_canje(text, text, text, text, integer) to service_role;
