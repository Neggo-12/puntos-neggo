-- Landing page pública (home) -- sección para comercios que quieren afiliarse
-- a la red de puntos. Necesita un lugar donde caiga el formulario. Tabla
-- simple, solo de captura de leads: anon puede INSERTAR (el formulario
-- público), nunca LEER -- ni siquiera sus propios datos después de enviarlos,
-- para no exponer nada de otros. Solo un admin puede ver y marcar atendida
-- una solicitud, mismo patrón de allowlist que el resto del panel admin.

create table public.solicitudes_comercio (
  id text primary key default gen_random_uuid()::text,
  nombre_negocio text not null,
  contacto_nombre text,
  telefono text,
  email text,
  ciudad text,
  mensaje text,
  atendido boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.solicitudes_comercio enable row level security;

create policy anon_insert_solicitudes on public.solicitudes_comercio
  for insert to anon
  with check (true);

create policy admin_select_solicitudes on public.solicitudes_comercio
  for select to authenticated
  using (public.is_admin());

create policy admin_update_solicitudes on public.solicitudes_comercio
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

-- Lección aplicada toda la sesión: revocar explícito de public y de lo que
-- no corresponde, nunca asumir que los grants por defecto están bien.
revoke all on public.solicitudes_comercio from public, anon, authenticated;
grant insert on public.solicitudes_comercio to anon;
grant select, update on public.solicitudes_comercio to authenticated;
