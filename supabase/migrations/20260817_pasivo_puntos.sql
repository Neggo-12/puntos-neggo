-- Fase 5: pasivo financiero visible (sistema-puntos-unificado.md sección 6 -- "un número
-- visible de puntos en circulación sin canjear, tiene que estar a la vista, no escondido").
--
-- No es SECURITY DEFINER a propósito: corre con los privilegios del que llama, así que la
-- RLS de clientes_puntos (solo admins) sigue aplicando -- un no-admin autenticado que la
-- llame ve 0, no un error, pero tampoco ve el dato real.
--
-- Caveat real (documentado, no oculto): esta suma no descuenta lotes ya vencidos
-- (fecha_vencimiento pasada) porque todavía no existe el barrido de vencimiento (Fase 6) --
-- puede sobreestimar el pasivo hasta que esa fase exista. Se muestra igual en el panel con
-- esa nota, mejor que no mostrar nada.
create or replace function public.obtener_pasivo_puntos()
returns table(puntos_en_circulacion bigint, valor_cop numeric, clientes_con_saldo bigint)
language sql
stable
set search_path = public
as $$
  select
    coalesce(sum(saldo), 0)::bigint as puntos_en_circulacion,
    coalesce(sum(saldo), 0) * 10 as valor_cop,
    count(*) filter (where saldo > 0)::bigint as clientes_con_saldo
  from public.clientes_puntos;
$$;

revoke execute on function public.obtener_pasivo_puntos() from public, anon;
grant execute on function public.obtener_pasivo_puntos() to authenticated;
