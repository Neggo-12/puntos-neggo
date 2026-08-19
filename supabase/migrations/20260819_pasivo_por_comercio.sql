-- Fase 7 (técnica), sub-tarea: cuenta por pagar por comercio.
-- Extiende el mismo patrón de obtener_pasivo_puntos (Fase 5) pero agrupado por
-- comercio en vez de por cliente. No es SECURITY DEFINER a propósito -- la RLS
-- existente de canjes (admins_select_canjes, gated por is_admin()) ya protege
-- el acceso: un no-admin autenticado ejecuta la función y ve cero filas, no error.
--
-- "pendiente_pago" en canjes es exactamente la cuenta por pagar: puntos que el
-- cliente ya canjeó y el comercio ya entregó, pero Neggo todavía no le reembolsó.

create or replace function public.obtener_pasivo_por_comercio()
returns table(
  comercio_id text,
  comercio_nombre text,
  puntos_pendientes bigint,
  valor_cop bigint,
  canjes_pendientes bigint
)
language sql
stable
set search_path = public
as $$
  select
    c.comercio_id,
    max(c.comercio_nombre) as comercio_nombre,
    coalesce(sum(c.puntos), 0)::bigint as puntos_pendientes,
    coalesce(sum(c.valor_cop), 0)::bigint as valor_cop,
    count(*)::bigint as canjes_pendientes
  from public.canjes c
  where c.estado = 'pendiente_pago'
  group by c.comercio_id
  order by valor_cop desc;
$$;

-- Mismo criterio ya aplicado en toda la sesión: revocar explícito de public y
-- anon, nunca asumir que el default del proyecto los deja afuera.
revoke execute on function public.obtener_pasivo_por_comercio() from public, anon;
grant execute on function public.obtener_pasivo_por_comercio() to authenticated;
