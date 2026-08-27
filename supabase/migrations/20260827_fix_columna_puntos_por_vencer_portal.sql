-- Bug real encontrado al verificar cliente_portal_estado con datos reales:
-- puntos_por_vencer_cliente devuelve la columna puntos_restantes, no
-- puntos_por_vencer (nombre que asumí sin revisar la función real).

create or replace function public.cliente_portal_estado(p_tipo_documento text, p_numero_documento text)
returns table(
  cliente_id text,
  nombre text,
  llave_cliente text,
  saldo integer,
  puntos_por_vencer_30d integer,
  movimientos jsonb
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cliente_id text;
  v_nombre text;
  v_llave text;
  v_saldo integer;
  v_estado text;
  v_por_vencer integer;
begin
  if p_tipo_documento is null or p_numero_documento is null then
    raise exception 'tipo_documento y numero_documento son obligatorios';
  end if;

  select cp.id, cp.nombre, cp.llave_cliente, cp.saldo, cp.estado
  into v_cliente_id, v_nombre, v_llave, v_saldo, v_estado
  from public.clientes_puntos cp
  where cp.tipo_documento = p_tipo_documento and cp.numero_documento = p_numero_documento;

  if v_cliente_id is null then
    raise exception 'No encontramos un cliente con ese documento';
  end if;

  select coalesce(sum(pv.puntos_restantes), 0) into v_por_vencer
  from public.puntos_por_vencer_cliente(p_tipo_documento, p_numero_documento, 30) pv;

  select coalesce(jsonb_agg(m order by m.created_at desc), '[]'::jsonb) into movimientos
  from (
    select pm.tipo, pm.puntos, pm.motivo, pm.origen_producto, pm.created_at, pm.fecha_vencimiento
    from public.puntos_movimientos pm
    where pm.cliente_id = v_cliente_id
    order by pm.created_at desc
    limit 50
  ) m;

  cliente_id := v_cliente_id;
  nombre := v_nombre;
  llave_cliente := v_llave;
  saldo := v_saldo;
  puntos_por_vencer_30d := v_por_vencer;
  return next;
end;
$$;

revoke execute on function public.cliente_portal_estado(text, text) from public, authenticated;
grant execute on function public.cliente_portal_estado(text, text) to anon;
