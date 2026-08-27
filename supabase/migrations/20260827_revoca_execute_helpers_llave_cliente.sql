-- Fuga de seguridad real encontrada al auditar con get_advisors + consulta directa
-- a information_schema.routine_privileges: este proyecto otorga EXECUTE a
-- anon/authenticated por privilegios por defecto a nivel de proyecto en cuanto
-- se crea una función, no solo por herencia de PUBLIC -- regla ya conocida en
-- este proyecto (ver otras migraciones), pero se me olvidó aplicarla a estas
-- 3 funciones internas (con prefijo _, nunca deberían ser invocables directo):
-- _normalizar_para_codigo (de la migración codigo_publico_cliente, ya en
-- producción con la fuga desde que se aplicó) y las dos nuevas de esta
-- migración (_generar_llave_cliente, _trigger_generar_llave_cliente).
-- Ninguna de las tres necesita ser llamada directamente por nadie -- solo las
-- usa el trigger internamente.

revoke execute on function public._normalizar_para_codigo(text) from public, anon, authenticated;
revoke execute on function public._generar_llave_cliente(text, text, text) from public, anon, authenticated;
revoke execute on function public._trigger_generar_llave_cliente() from public, anon, authenticated;
