-- create or replace con una lista de parámetros distinta creó un OVERLOAD nuevo,
-- no reemplazó la función original de 7 parámetros -- quedaron las dos
-- coexistiendo (mismo bug de fondo que el de codigo_publico: no revisar qué ya
-- existía antes de aplicar). El overload viejo nunca tuvo grant a anon/authenticated
-- (verificado), así que no hay hueco de seguridad, pero mantener dos cuerpos de
-- la misma función es un riesgo de mantenimiento -- un fix futuro podría
-- aplicarse solo a una de las dos. Se elimina la versión vieja; p_nombre tiene
-- default null, así que una llamada con los 7 argumentos de siempre (con nombre)
-- sigue resolviendo correctamente contra la versión de 8 parámetros.
drop function if exists public.otorgar_puntos(text, text, numeric, text, text, text, text);
