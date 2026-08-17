-- Fix: comercios_solo_canje/canjes/clientes_puntos tenían policies que hacían
-- "exists (select 1 from admins where user_id = auth.uid())" directo. Esa subconsulta
-- corre con el rol del que llama (authenticated), y admins también tiene RLS habilitada
-- sin policies (a propósito, para que nadie la lea/escriba directo) -- resultado: la
-- subconsulta siempre devolvía 0 filas, incluso para un admin real. Confirmado en vivo:
-- Jhey (ya en admins) recibió "new row violates row-level security policy" al intentar
-- insertar un comercio.
--
-- Fix estándar de Supabase: un helper SECURITY DEFINER que sí puede leer admins
-- (corre con privilegios del dueño de la función, bypassa RLS), y las policies llaman
-- a ese helper en vez de consultar la tabla directo.

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.admins a where a.user_id = auth.uid());
$$;

revoke execute on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

drop policy if exists admins_select_comercios on public.comercios_solo_canje;
drop policy if exists admins_insert_comercios on public.comercios_solo_canje;
drop policy if exists admins_update_comercios on public.comercios_solo_canje;
drop policy if exists admins_select_canjes on public.canjes;
drop policy if exists admins_select_clientes_puntos on public.clientes_puntos;

create policy admins_select_comercios on public.comercios_solo_canje
for select to authenticated using (public.is_admin());

create policy admins_insert_comercios on public.comercios_solo_canje
for insert to authenticated with check (public.is_admin());

create policy admins_update_comercios on public.comercios_solo_canje
for update to authenticated using (public.is_admin()) with check (public.is_admin());

create policy admins_select_canjes on public.canjes
for select to authenticated using (public.is_admin());

create policy admins_select_clientes_puntos on public.clientes_puntos
for select to authenticated using (public.is_admin());
