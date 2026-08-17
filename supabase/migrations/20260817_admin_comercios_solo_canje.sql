-- Fase 4: comercios solo-canje + acceso de admin (Jhey) al panel mínimo.
-- Este proyecto no tiene usuarios finales autenticados (ver 20260817_ledger_base.sql),
-- pero SÍ necesita que un admin humano entre a marcar canjes como pagados. Se usa
-- Supabase Auth (un único usuario, creado por Jhey desde el dashboard) + tabla admins
-- como allowlist -- RLS solo se abre para quien esté en admins, nunca para
-- authenticated en general.

create table public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.admins enable row level security;
-- sin policies: nadie via API puede leer/escribir admins directo, ni siquiera un admin
-- logueado -- esa tabla se administra solo por SQL/dashboard, a propósito.

create table public.comercios_solo_canje (
  id text primary key default gen_random_uuid()::text,
  nombre text not null,
  ciudad text not null,
  contacto text not null,
  datos_pago text not null,
  activo boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger trg_comercios_solo_canje_updated_at
before update on public.comercios_solo_canje
for each row execute function public.set_updated_at();

alter table public.comercios_solo_canje enable row level security;

create policy admins_select_comercios on public.comercios_solo_canje
for select to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

create policy admins_insert_comercios on public.comercios_solo_canje
for insert to authenticated
with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));

create policy admins_update_comercios on public.comercios_solo_canje
for update to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()))
with check (exists (select 1 from public.admins a where a.user_id = auth.uid()));

-- El admin necesita LEER canjes/movimientos para el panel, pero nunca escribir esas
-- tablas directo -- todo cambio de estado pasa por marcar_canje_pagado (abajo).
create policy admins_select_canjes on public.canjes
for select to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

create policy admins_select_clientes_puntos on public.clientes_puntos
for select to authenticated
using (exists (select 1 from public.admins a where a.user_id = auth.uid()));

-- Nota: todas las referencias a columnas de canjes están calificadas con el alias `c`
-- a propósito -- RETURNS TABLE(canje_id, estado, pagado_at) declara esos nombres como
-- variables plpgsql implícitas, y ya nos pasó dos veces en esta sesión que una
-- referencia sin calificar a "estado"/"cliente_id"/"codigo_verificacion" sale ambigua
-- recién en runtime (ver 20260817_fix_ambiguous_cliente_id.sql y
-- 20260817_fix_ambiguous_codigo_verificacion.sql).
create or replace function public.marcar_canje_pagado(p_canje_id text)
returns table(canje_id text, estado text, pagado_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_estado_actual text;
  v_pagado_at timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null or not exists (select 1 from public.admins a where a.user_id = v_uid) then
    raise exception 'No autorizado';
  end if;

  select c.estado into v_estado_actual from public.canjes c where c.id = p_canje_id for update;

  if v_estado_actual is null then
    raise exception 'Canje % no existe', p_canje_id;
  end if;

  if v_estado_actual <> 'pendiente_pago' then
    raise exception 'Transición inválida: el canje está en estado %, se esperaba pendiente_pago', v_estado_actual;
  end if;

  update public.canjes as c
  set estado = 'pagado', pagado_at = now(), pagado_por = v_uid::text
  where c.id = p_canje_id and c.estado = 'pendiente_pago'
  returning c.pagado_at into v_pagado_at;

  if not found then
    raise exception 'No se pudo actualizar el canje % (posible carrera con otra actualización)', p_canje_id;
  end if;

  perform public._log_audit('canje.marcado_pagado', v_uid::text, p_canje_id, jsonb_build_object());

  return query select p_canje_id, 'pagado'::text, v_pagado_at;
end;
$$;

revoke execute on function public.marcar_canje_pagado(text) from public;
grant execute on function public.marcar_canje_pagado(text) to authenticated;
