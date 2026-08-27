-- ==========================================================================
-- PORTAL DEL CLIENTE (página de Puntos Neggo) -- primer endpoint público
-- ==========================================================================
-- Decisión explícita de Jhey (27 ago): construir el frontend completo ya,
-- SIN esperar el PIN temporal por email/SMS. Identidad del cliente mientras
-- tanto = SOLO número de documento. Esto es intencionalmente débil: quien
-- sepa el tipo+número de documento de alguien puede ver su saldo y mover sus
-- puntos (transferir, canjear). Es la primera vez que este proyecto expone
-- funciones a `anon` (nunca antes se llamó desde el navegador de un cliente,
-- ver docs/sistema-puntos-unificado.md sección 7) -- decisión consciente y
-- temporal, no un descuido. Antes de anunciar esta página públicamente hay
-- que reemplazar la verificación por el PIN temporal ya decidido.
--
-- Diseño: estas son funciones NUEVAS ("cliente_portal_*"), no se tocan ni se
-- debilitan transferir_puntos/solicitar_canje existentes (siguen siendo
-- service_role-only, usadas por Neggo/Talleres server-to-server). Los
-- wrappers de portal llaman a esas mismas funciones por dentro -- SECURITY
-- DEFINER anidado funciona sin necesitar grants adicionales -- para no
-- duplicar la lógica de negocio ni sus controles antifraude.

-- 1) Estado del cliente: saldo, datos básicos, historial, puntos por vencer.
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

  select coalesce(sum(pv.puntos_por_vencer), 0) into v_por_vencer
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

-- 2) Buscar destinatario de una transferencia por su llave pública (nunca por
-- documento -- la llave es justo lo que existe para no tener que compartir
-- el documento entre clientes). Solo expone nombre + llave, nada sensible.
create or replace function public.cliente_portal_buscar_destinatario(p_llave_cliente text)
returns table(nombre text, llave_cliente text)
language sql
stable
security definer
set search_path = public
as $$
  select cp.nombre, cp.llave_cliente
  from public.clientes_puntos cp
  where cp.llave_cliente = lower(btrim(p_llave_cliente))
    and cp.estado <> 'congelado';
$$;

revoke execute on function public.cliente_portal_buscar_destinatario(text) from public, authenticated;
grant execute on function public.cliente_portal_buscar_destinatario(text) to anon;

-- 3) Transferir puntos por llave del destinatario -- wrapper sobre transferir_puntos.
create or replace function public.cliente_portal_transferir(
  p_tipo_documento_origen text,
  p_numero_documento_origen text,
  p_llave_destino text,
  p_puntos integer,
  p_referencia_externa text default null,
  p_motivo text default null
)
returns table(
  puntos_transferidos integer,
  saldo_nuevo_origen integer,
  destinatario_nombre text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_destino_tipo_documento text;
  v_destino_numero_documento text;
  v_destino_nombre text;
  v_resultado record;
begin
  select cp.tipo_documento, cp.numero_documento, cp.nombre
  into v_destino_tipo_documento, v_destino_numero_documento, v_destino_nombre
  from public.clientes_puntos cp
  where cp.llave_cliente = lower(btrim(p_llave_destino));

  if v_destino_tipo_documento is null then
    raise exception 'No encontramos ningún cliente con esa llave';
  end if;

  select * into v_resultado
  from public.transferir_puntos(
    p_tipo_documento_origen,
    p_numero_documento_origen,
    v_destino_tipo_documento,
    v_destino_numero_documento,
    p_puntos,
    'portal_cliente',
    p_referencia_externa,
    p_motivo
  );

  puntos_transferidos := v_resultado.puntos_transferidos;
  saldo_nuevo_origen := v_resultado.saldo_nuevo_origen;
  destinatario_nombre := v_destino_nombre;
  return next;
end;
$$;

revoke execute on function public.cliente_portal_transferir(text, text, text, integer, text, text) from public, authenticated;
grant execute on function public.cliente_portal_transferir(text, text, text, integer, text, text) to anon;

-- 4) Comercios disponibles para canje -- solo lo público (nunca contacto/datos_pago/user_id).
create or replace function public.cliente_portal_comercios_disponibles()
returns table(comercio_id text, nombre text, ciudad text)
language sql
stable
security definer
set search_path = public
as $$
  select cs.id, cs.nombre, cs.ciudad
  from public.comercios_solo_canje cs
  where cs.activo
  order by cs.nombre asc;
$$;

revoke execute on function public.cliente_portal_comercios_disponibles() from public, authenticated;
grant execute on function public.cliente_portal_comercios_disponibles() to anon;

-- 5) Solicitar canje -- wrapper sobre solicitar_canje, resuelve el nombre del
-- comercio internamente para que el cliente no tenga que escribirlo.
create or replace function public.cliente_portal_solicitar_canje(
  p_tipo_documento text,
  p_numero_documento text,
  p_comercio_id text,
  p_puntos integer
)
returns table(canje_id text, codigo_verificacion text, saldo_nuevo integer)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_comercio_nombre text;
begin
  select cs.nombre into v_comercio_nombre
  from public.comercios_solo_canje cs
  where cs.id = p_comercio_id and cs.activo;

  if v_comercio_nombre is null then
    raise exception 'Comercio no disponible';
  end if;

  return query
  select * from public.solicitar_canje(p_tipo_documento, p_numero_documento, p_comercio_id, v_comercio_nombre, p_puntos);
end;
$$;

revoke execute on function public.cliente_portal_solicitar_canje(text, text, text, integer) from public, authenticated;
grant execute on function public.cliente_portal_solicitar_canje(text, text, text, integer) to anon;
