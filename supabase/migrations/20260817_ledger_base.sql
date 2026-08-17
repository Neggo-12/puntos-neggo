-- Ledger base de Puntos Neggo: clientes_puntos, puntos_movimientos, canjes, audit_log
-- + otorgar_puntos / solicitar_canje (SECURITY DEFINER, solo callables desde service_role)
--
-- Decisiones de diseño que se apartan de la lectura literal de sistema-puntos-unificado.md
-- sección 7 (documentadas también en docs/roadmap-pendientes.md):
-- 1) otorgar_puntos calcula el multiplicador (1X/2X) internamente, nunca confía en un valor
--    que mande el caller. Motivo: "cliente nuevo" es un concepto cruzado entre productos
--    (Neggo/Talleres) que solo Puntos puede verificar con su propio historial. 3X/5X quedan
--    fuera de esta migración: dependen de infraestructura de campañas/inactividad (Fase 6).
-- 2) Se agrega p_referencia_externa (idempotencia) porque modelo-economico-v1.md sección 9
--    exige rechazar transacciones duplicadas, y sin una referencia única del caller eso es
--    imposible de detectar. Mismo problema que neggo-12 ya resolvió en emitir_puntos_por_compra
--    (chequeo por factura_cliente_id antes de insertar).

create table public.clientes_puntos (
  id text primary key default gen_random_uuid()::text,
  tipo_documento text not null,
  numero_documento text not null,
  email text,
  telefono text,
  nombre text,
  codigo_publico text unique,
  saldo integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint clientes_puntos_documento_unico unique (tipo_documento, numero_documento),
  constraint clientes_puntos_saldo_no_negativo check (saldo >= 0)
);

comment on table public.clientes_puntos is 'Fuente de verdad del saldo de puntos. Llave de cruce entre proyectos: (tipo_documento, numero_documento). saldo es un cache mantenido atómicamente por otorgar_puntos/solicitar_canje, nunca se escribe directo.';

create or replace function public.generar_codigo_publico_cliente(p_id text)
returns text
language sql
immutable
set search_path = public
as $$
  select 'PT-' || upper(left(p_id, 6));
$$;

create or replace function public.set_codigo_publico_cliente()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.codigo_publico := public.generar_codigo_publico_cliente(new.id);
  return new;
end;
$$;

create trigger trg_set_codigo_publico_cliente
before insert on public.clientes_puntos
for each row execute function public.set_codigo_publico_cliente();

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger trg_clientes_puntos_updated_at
before update on public.clientes_puntos
for each row execute function public.set_updated_at();

create table public.puntos_movimientos (
  id text primary key default gen_random_uuid()::text,
  cliente_id text not null references public.clientes_puntos(id),
  tipo text not null check (tipo in ('ganado','canjeado','revertido','transferido_salida','transferido_entrada','vencido')),
  puntos integer not null check (puntos <> 0),
  valor_compra numeric,
  multiplicador integer,
  comercio_origen_id text,
  origen_producto text,
  referencia_externa text,
  canje_id text,
  motivo text,
  fecha_vencimiento date,
  created_at timestamptz not null default now()
);

create index idx_puntos_movimientos_cliente on public.puntos_movimientos(cliente_id);
create index idx_puntos_movimientos_comercio_origen on public.puntos_movimientos(cliente_id, comercio_origen_id) where tipo = 'ganado';
create unique index idx_puntos_movimientos_referencia_unica on public.puntos_movimientos(origen_producto, referencia_externa) where tipo = 'ganado' and referencia_externa is not null;

comment on table public.puntos_movimientos is 'Ledger append-only. fecha_vencimiento (12 meses) solo aplica a movimientos tipo ganado.';

create table public.canjes (
  id text primary key default gen_random_uuid()::text,
  cliente_id text not null references public.clientes_puntos(id),
  comercio_id text not null,
  comercio_nombre text not null,
  puntos integer not null check (puntos > 0),
  valor_cop numeric not null,
  estado text not null default 'pendiente_pago' check (estado in ('pendiente_pago','pagado','cancelado')),
  codigo_verificacion text,
  movimiento_id text references public.puntos_movimientos(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  pagado_at timestamptz,
  pagado_por text
);

create index idx_canjes_cliente on public.canjes(cliente_id);
create index idx_canjes_estado on public.canjes(estado);

create trigger trg_canjes_updated_at
before update on public.canjes
for each row execute function public.set_updated_at();

-- Mismo patrón que comercio_contactos.codigo_verificacion en neggo-12 (hash determinístico + salt),
-- con salt propio de este proyecto para no compartir espacio de códigos entre proyectos.
create or replace function public.generar_codigo_verificacion_canje(p_id text)
returns text
language plpgsql
immutable
set search_path = public
as $$
declare
  v_hash bigint;
  v_code text;
begin
  v_hash := abs(('x' || substring(md5(p_id || 'puntos-neggo-salt-2026'), 1, 15))::bit(60)::bigint);
  v_code := lpad((v_hash % 1000000)::text, 6, '0');
  return substring(v_code, 1, 3) || ' ' || substring(v_code, 4, 3);
end;
$$;

create or replace function public.set_codigo_verificacion_canje()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.codigo_verificacion := public.generar_codigo_verificacion_canje(new.id);
  return new;
end;
$$;

create trigger trg_set_codigo_verificacion_canje
before insert on public.canjes
for each row execute function public.set_codigo_verificacion_canje();

create table public.audit_log (
  id bigint generated always as identity primary key,
  evento text not null,
  actor text,
  target text,
  detalle jsonb,
  created_at timestamptz not null default now()
);

create or replace function public._log_audit(p_evento text, p_actor text, p_target text, p_detalle jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.audit_log (evento, actor, target, detalle)
  values (p_evento, p_actor, p_target, p_detalle);
end;
$$;

revoke execute on function public._log_audit(text, text, text, jsonb) from anon, authenticated;

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

  select id into v_cliente_id
  from public.clientes_puntos
  where tipo_documento = p_tipo_documento and numero_documento = p_numero_documento;

  -- idempotencia: si ya se procesó esta referencia externa, no duplicar
  if p_referencia_externa is not null then
    select pm.puntos, pm.multiplicador into v_movimiento_existente
    from public.puntos_movimientos pm
    where pm.origen_producto = p_origen_producto
      and pm.referencia_externa = p_referencia_externa
      and pm.tipo = 'ganado';

    if found then
      select saldo into v_saldo_nuevo from public.clientes_puntos where id = v_cliente_id;
      return query select v_cliente_id, v_movimiento_existente.puntos, v_movimiento_existente.multiplicador, v_saldo_nuevo, true;
      return;
    end if;
  end if;

  select not exists (
    select 1 from public.puntos_movimientos
    where cliente_id = v_cliente_id and tipo = 'ganado' and comercio_origen_id = p_comercio_id
  ) into v_es_cliente_nuevo;

  if v_es_cliente_nuevo then
    v_multiplicador := 2;
  end if;

  v_puntos_base := floor(p_valor_compra / 800);
  v_puntos := v_puntos_base * v_multiplicador;

  if v_puntos <= 0 then
    select saldo into v_saldo_nuevo from public.clientes_puntos where id = v_cliente_id;
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

revoke execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text) from anon, authenticated;

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

  select id, saldo into v_cliente_id, v_saldo
  from public.clientes_puntos
  where tipo_documento = p_tipo_documento and numero_documento = p_numero_documento
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

  insert into public.canjes (cliente_id, comercio_id, comercio_nombre, puntos, valor_cop, movimiento_id)
  values (v_cliente_id, p_comercio_id, p_comercio_nombre, p_puntos, p_puntos * 10, v_movimiento_id)
  returning id, codigo_verificacion into v_canje_id, v_codigo;

  update public.puntos_movimientos set canje_id = v_canje_id where id = v_movimiento_id;

  perform public._log_audit('puntos.canje_solicitado', p_comercio_id, v_cliente_id,
    jsonb_build_object('puntos', p_puntos, 'canjeId', v_canje_id));

  return query select v_canje_id, v_codigo, v_saldo_nuevo;
end;
$$;

revoke execute on function public.solicitar_canje(text, text, text, text, integer) from anon, authenticated;

-- RLS: este proyecto no tiene usuarios finales autenticados (los clientes nunca inician sesión
-- en Puntos). Todo acceso real pasa por otorgar_puntos/solicitar_canje vía service_role
-- (Edge Function con x-internal-secret). RLS deny-all para anon/authenticated como defensa en
-- profundidad -- sin policies, nada es legible ni escribible desde esos roles; service_role
-- bypassa RLS de forma nativa en Supabase.
alter table public.clientes_puntos enable row level security;
alter table public.puntos_movimientos enable row level security;
alter table public.canjes enable row level security;
alter table public.audit_log enable row level security;
