-- Fix: el REVOKE de 20260817_ledger_base.sql apuntaba a anon/authenticated, pero Postgres
-- otorga EXECUTE a PUBLIC por defecto en CREATE FUNCTION, y anon/authenticated heredan de
-- PUBLIC -- el revoke anterior no tenía efecto real. Confirmado con get_advisors (security):
-- _log_audit, otorgar_puntos y solicitar_canje quedaron ejecutables por anon/authenticated
-- vía RPC. Mismo error que ya documenta neggo-12/docs/roadmap-pendientes.md (#107) para
-- _log_audit -- ahí también hubo que revocar de PUBLIC, no solo de los roles individuales.

revoke execute on function public._log_audit(text, text, text, jsonb) from public;
revoke execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text) from public;
revoke execute on function public.solicitar_canje(text, text, text, text, integer) from public;

grant execute on function public._log_audit(text, text, text, jsonb) to service_role;
grant execute on function public.otorgar_puntos(text, text, numeric, text, text, text, text) to service_role;
grant execute on function public.solicitar_canje(text, text, text, text, integer) to service_role;
