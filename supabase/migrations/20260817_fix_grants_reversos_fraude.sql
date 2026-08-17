-- Fix urgente: en la migración anterior (20260817_reversos_fraude.sql) revoqué EXECUTE
-- solo de "public" para las 5 funciones nuevas, siguiendo el patrón de
-- marcar_canje_pagado. get_advisors(security) mostró que NO fue suficiente: anon y
-- authenticated tenían EXECUTE de todas formas -- confirmado directo en
-- information_schema.routine_privileges, no solo el advisor.
--
-- Causa real (más precisa que el diagnóstico original de Bug #1 en
-- fix_grants_security_definer.sql): este proyecto Supabase tiene privilegios por
-- defecto que otorgan EXECUTE en funciones nuevas del schema public directo a
-- anon/authenticated/service_role (ALTER DEFAULT PRIVILEGES a nivel de proyecto,
-- estándar de Supabase) -- eso es un grant directo, no via PUBLIC, así que
-- "revoke ... from public" no lo toca. La migración de barrido de vencimiento sí
-- revocó explícitamente de anon/authenticated y por eso salió limpia. Esta es la
-- confirmación real de la causa -- de ahora en adelante, toda función nueva revoca
-- explícitamente de public, anon Y authenticated, y solo después se otorga a quien
-- sí debe tenerlo.

revoke execute on function public.revertir_puntos_otorgados(text, text, text) from public, anon, authenticated;
grant execute on function public.revertir_puntos_otorgados(text, text, text) to service_role;

revoke execute on function public.congelar_cliente(text, text) from public, anon;
grant execute on function public.congelar_cliente(text, text) to authenticated;

revoke execute on function public.descongelar_cliente(text, text) from public, anon;
grant execute on function public.descongelar_cliente(text, text) to authenticated;

revoke execute on function public.bloquear_redencion_cliente(text, text) from public, anon;
grant execute on function public.bloquear_redencion_cliente(text, text) to authenticated;

revoke execute on function public.desbloquear_redencion_cliente(text, text) from public, anon;
grant execute on function public.desbloquear_redencion_cliente(text, text) to authenticated;
