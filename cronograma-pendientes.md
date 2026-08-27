# Cronograma — Puntos Neggo (backend)

Última actualización: 17 de agosto de 2026. Compilado desde `docs/roadmap-pendientes.md` — este documento es la vista "qué falta y cuándo", el otro es el registro detallado de lo ya hecho. Mismo patrón que `neggo-12/docs/cronograma-pendientes.md`.

Las fases están pensadas en **sesiones de trabajo**, no en fechas de calendario fijas — el ritmo real depende de disponibilidad de Jhey y de cuántas decisiones de negocio queden abiertas en el camino, no de un plazo artificial.

## Fase 0 — Fundación (esta sesión, 17 ago)

- Lectura completa de `sistema-puntos-unificado.md`.
- Verificación real de Supabase: proyecto `puntos-neggo` (`ckxoypzsmvxhqlvlwnib`) **ACTIVE_HEALTHY**, sin tablas ni migraciones todavía.
- Documentación base creada: este cronograma, `metodologia-trabajo.md`, `modelo-economico-v1.md`, `roadmap-pendientes.md`.
- **Estado:** hecho.

## Fase 1 — Ledger base — **hecho y verificado, 17 ago**

- `clientes_puntos` (constraint único `(tipo_documento, numero_documento)`), `puntos_movimientos` (ledger append-only; el vencimiento a 12 meses vive en `fecha_vencimiento` de cada fila `ganado`, mismo patrón que `puntos_movimientos` de `neggo-12` — se descartó una tabla `lotes_puntos` separada por ser una segunda implementación de algo que ya existe), `canjes`, `audit_log`.
- RLS habilitada en las 4 tablas, sin policies (deny-all) — probada en ambos sentidos con `SET LOCAL ROLE anon/authenticated` (0 filas, `permission denied` en las funciones). Solo `service_role` tiene acceso.
- `otorgar_puntos` (1X/2X calculado internamente, no confía en el caller; 3X/5X quedan afuera hasta que exista infraestructura de campañas) y `solicitar_canje` como `SECURITY DEFINER`, con idempotencia por `referencia_externa`.
- Verificado con datos reales end-to-end (detalle en `roadmap-pendientes.md`) — 2 bugs reales encontrados y corregidos en el camino (grants a `PUBLIC` en vez de `anon`/`authenticated`; ambigüedad de nombre de columna en dos funciones).
- **Hallazgo pendiente de decisión de Jhey (no bloquea, pero hay que resolverlo antes de Fase 3):** `neggo-12` ya tiene su propio sistema de puntos (`puntos_movimientos`, tasa negociada por comercio) — ¿se migra/desactiva a favor de este, o coexisten un tiempo?

## Fase 2 — Código de verificación de canje — **hecho, incluido en Fase 1**

- Se revisó la definición real de `comercio_contactos.codigo_verificacion` en `neggo-12` antes de copiar el patrón — mismo hash+salt, salt propio del proyecto.
- Trigger + función `generar_codigo_verificacion_canje` sobre `canjes`, ya aplicado y probado (genera formato `"XXX XXX"`).

## Fase 3 — Integración servidor-a-servidor — **desplegado, 17 ago; falta 1 paso manual de Jhey**

- Edge Functions `otorgar-puntos` y `solicitar-canje` desplegadas en `puntos-neggo` (`verify_jwt=false`, autenticación propia por header `x-internal-secret`). No se investigó la integración `neggo-12` ↔ `ads-ai-platform` — Jhey aclaró que un proyecto aparte va a conectar las APIs de todos los productos, así que ese patrón puntual ya no es la referencia a copiar. El contrato de estas dos funciones (URL + header + JSON) sirve igual para quien termine llamándolas.
- **Nota sobre el sistema de puntos viejo de `neggo-12`:** Jhey confirmó que era la versión inicial y que va a desaparecer — solo queda el visual. No se tocó ni se va a tocar ese código desde `puntos-neggo`.
- **Pendiente de Jhey (no técnico, un paso de Dashboard):** cargar el secreto `INTERNAL_SECRET` en Supabase — sin eso las funciones responden `server_misconfigured` a propósito (fail-closed). Instrucción exacta en el mensaje de cierre de esta sesión.
- **Verificado en producción, 17 ago:** Jhey corrió el curl real y `otorgar_puntos` devolvió `puntos_otorgados: 2000, multiplicador: 2` — correcto para primera compra de $800.000. Dato de prueba borrado después. Fase 3 cerrada.

## Fase 4 — Panel admin mínimo, comercios solo-canje — **hecho y verificado en vivo, 17 ago**

- `comercios_solo_canje` (nombre, ciudad, contacto, datos de pago) con RLS restringida a `admins` (allowlist por `auth.uid()`, no a cualquier `authenticated`).
- `marcar_canje_pagado` como `SECURITY DEFINER`, transición explícita `pendiente_pago → pagado` (rechaza cualquier otro estado de origen), con `_log_audit`.
- Panel: página HTML sola (`admin/index.html`, sin framework — herramienta de un botón para un usuario, no ameritaba Vite/Cloudflare), login con Supabase Auth, lista de canjes pendientes con el código de verificación visible, botón "Marcar entregado", alta de comercios.
- 2 bugs de grants/RLS encontrados y corregidos en el camino (`anon` podía ejecutar `marcar_canje_pagado`; las policies de `admins` bloqueaban a un admin real por RLS-sobre-RLS — ver roadmap para el detalle).
- **Verificado por Jhey en el navegador real:** alta de comercio, y flujo completo de canje (otorgar puntos → solicitar canje → ver pendiente en el panel con código de verificación → marcar entregado) — confirmado también a nivel de base (`estado='pagado'`, `pagado_por` = su usuario real, `audit_log` con el evento). Datos de prueba eliminados después.
- **Pendiente, no bloqueante:** hosting persistente del panel (hoy corre con `python3 -m http.server` local) — decisión aparte cuando haga falta.
- **Pendiente de Jhey:** crear su usuario de Supabase Auth (instrucción exacta en el mensaje de cierre) — sin eso no hay forma de probar el flujo completo de admin autorizado, solo se verificaron los caminos de rechazo (no-admin, anon).

## Fase 5 — Pasivo financiero visible — **hecho y verificado, 17 ago**

- Función `obtener_pasivo_puntos()` (no `SECURITY DEFINER` a propósito — la RLS existente de `admins` la protege sola). Devuelve puntos en circulación, valor de referencia en COP, clientes con saldo.
- Panel (`admin/index.html`) con sección visible arriba de "Canjes pendientes".
- Verificado con datos de prueba: admin ve el total real, no-admin ve ceros. Confirmado también visualmente por Jhey en el navegador real.

## Fase 6 — Mecánicas avanzadas del modelo V1 (estimado: 2–3 sesiones, varias sub-tareas independientes)

- **Sub-tarea 1, vencimiento por lote (barrido) — hecho y verificado, 17 ago.** `ejecutar_barrido_vencimientos()` recalcula consumo FIFO sobre el ledger y vence lo que corresponda de cada lote pasado su `fecha_vencimiento`; programado por `pg_cron` diario (01:00 Bogotá). Idempotente, probado con datos reales (2 lotes, consumo parcial, vencimiento parcial correcto, segunda corrida sin duplicar). Detalle en `roadmap-pendientes.md`. El pasivo financiero (Fase 5) ahora es exacto con hasta 24h de rezago, ya no es una estimación.
- Presupuesto máximo por campaña con corte automático — **pendiente, sin decisión de Jhey sobre el mecanismo exacto de corte.**
- Transferencia punto a punto con límites antifraude y preservación de vencimiento del lote de origen — **pendiente, sin decisión de Jhey sobre límites diario/mensual.** (El ledger y el cálculo FIFO ya están listos para sumar `transferido_entrada`/`transferido_salida` cuando se construya.)
- **Sub-tarea 2, reversos y fraude — hecho y verificado, 17 ago.** `revertir_puntos_otorgados` (reversión de compra cancelada/devuelta, idempotente, recupera como máximo el saldo disponible y deja constancia de lo no recuperado), `congelar_cliente`/`descongelar_cliente` (bloquea todo), `bloquear_redencion_cliente`/`desbloquear_redencion_cliente` (bloquea solo canje). **En el camino se encontró y corrigió un hallazgo de seguridad real:** las 5 funciones quedaron ejecutables por `anon` (sin login) hasta que se detectó con `get_advisors` y se corrigió — detalle completo en `roadmap-pendientes.md`.
- **Sub-tarea 3, notificación de vencimiento próximo — hecho y verificado, 17 ago.** `puntos_por_vencer_cliente` + Edge Function `puntos-por-vencer`, confirmado con curl real. Ventana configurable (default 15 días, el mismo número de ejemplo de la spec -- la ventana final exacta sigue siendo decisión de Jhey). De paso se corrigió un gap real: `revertir_puntos_otorgados` (sub-tarea 2) nunca tuvo Edge Function propia -- ya desplegada (`revertir-puntos`) y confirmada con curl real (200 puntos otorgados y revertidos de punta a punta).
- **Sub-tarea 4, transferencia punto a punto — hecho y verificado, 17 ago.** `transferir_puntos` + Edge Function `transferir-puntos`. Preserva el vencimiento del lote de origen (puede generar varias filas en el destinatario si la transferencia toca más de un lote). **Límites confirmados por Jhey, 18 ago:** 2.000 puntos por transferencia, 3.000/día, 10.000/mes, 3 transferencias/día -- fáciles de cambiar en una migración futura si hace falta. Probado con transferencia multi-lote real, idempotencia, los 8 casos de rechazo, y regresión completa del barrido de vencimientos/notificación con puntos recibidos por transferencia. Detalle en `roadmap-pendientes.md`.

## Fase 6 completa

Las 4 sub-tareas (vencimiento por lote, reversos y fraude, notificación de vencimiento, transferencia punto a punto) están hechas y verificadas con datos reales. Los límites de transferencia quedaron confirmados por Jhey el 18 de agosto. Sin pendientes técnicos en esta fase.

## Fase 7 — Retiro en efectivo y pagos a comercios (arrancó parcialmente, 19 ago)

Jhey empezó conversación con una pasarela de pagos. Sigue bloqueado el envío real de plata (proveedor definitivo + consulta jurídica/SARLAFT), pero ya se puede avanzar la parte técnica que no depende de eso.

**Decisión de alcance importante (19 ago):** el comprobante de venta (monto pagado, producto/servicio) NO lo genera puntos-neggo — es responsabilidad del admin de Talleres/CarroTalleres, que tiene el contexto de la cita/servicio. Puntos-neggo ya soporta el enlace vía `referenciaExterna` en `otorgar_puntos` (existe desde Fase 1) más las columnas `valor_compra`/`multiplicador` ya persistidas en el ledger — no hizo falta ninguna migración para esto. Se le entregó al arquitecto de CarroTalleres el contrato exacto del endpoint `otorgar-puntos` para que genere el comprobante de su lado y lo enlace.

**Sub-tarea, cuenta por pagar por comercio — hecho y verificado, 19 ago.** `obtener_pasivo_por_comercio()` agrupa `canjes` en estado `pendiente_pago` por comercio (mismo patrón que el pasivo de clientes de Fase 5). Verificado con datos de prueba reales: admin ve los montos correctos por comercio, no-admin ve cero filas, `anon` no puede ni ejecutar la función (`permission denied`). Agregado al panel admin como nueva sección "Cuenta por pagar por comercio", y `marcar_canje_pagado` ahora refresca esa tabla también. Datos de prueba eliminados después.

**Sub-tarea, portal de comercios (login propio) — hecho y verificado, 20 ago.** Nueva app `comercio/index.html`, login con Supabase Auth independiente del admin. Diseño: `comercios_solo_canje.user_id` vincula el comercio a su cuenta (el admin lo crea manualmente en Supabase Dashboard y lo vincula desde el panel admin, no hay autoregistro). Nuevas RLS: el comercio ve solo su propia fila de `comercios_solo_canje` y solo sus propios `canjes` — esto además hace que `obtener_pasivo_por_comercio()` funcione automáticamente para el comercio sin duplicar lógica, la RLS ya filtra antes de agrupar.

Nueva función `confirmar_canje_comercio(canje_id, codigo)`: el comercio confirma el código que le da el cliente en persona. Decisión de diseño importante: el código de verificación **nunca se expone al comercio por consulta directa** (el portal no lo selecciona) — solo se puede confirmar escribiéndolo, y el servidor lo compara. Esto NO cambia `canjes.estado` (que sigue significando "Neggo ya pagó") — se guarda en una columna nueva `confirmado_comercio_at`, evitando romper el pasivo por comercio o cualquier filtro existente por estado. El pago real lo sigue marcando el admin (o, más adelante, la automatización con la pasarela).

**Bug real encontrado y corregido en el camino:** ambigüedad de nombre de columna en `confirmar_canje_comercio` (el parámetro de salida y la columna de la tabla se llamaban igual) — mismo patrón de bug que ya había mordido el proyecto en Fase 1. Corregido con una migración nueva (`fix_ambiguedad_confirmar_canje_comercio`), nunca se tocó la migración original.

**Verificado con datos y usuarios de prueba reales (limpiados después):** un comercio ve únicamente su propia fila y sus propios canjes, nunca los de otro comercio (probado con 2 comercios simultáneos). Código incorrecto rechazado. Un comercio ajeno con el código correcto en la mano igual no puede confirmar un canje que no es suyo (`No autorizado`). Confirmación exitosa deja `confirmado_comercio_at` pero `estado` sigue en `pendiente_pago`. Doble confirmación rechazada. `anon` no puede ejecutar ninguna función nueva (`permission denied`). `get_advisors(security)` limpio -- solo los WARN ya esperados de funciones `SECURITY DEFINER` intencionalmente callable por `authenticated`.

**Sub-tarea, llave pública del cliente (`llave_cliente`) — hecho y verificado, 27 ago.** Jhey definió que cada cliente necesita una "llave" memorable para identificarse en la futura página de Puntos Neggo: primer nombre + últimos 2 dígitos de la cédula (ej. `jheison68`). Se agregó `clientes_puntos.llave_cliente` (columna nueva, `unique`), generada automáticamente por trigger cuando el cliente tiene `nombre` guardado, con manejo de colisión (si `jheison68` ya existe, crece el sufijo a 3+ dígitos hasta encontrar uno libre). `otorgar_puntos` se extendió con un `p_nombre` opcional (parámetro 8, con default `null` — no rompe ningún caller existente) para poder llenar `nombre` la primera vez que se conoce (gana el primer nombre conocido, una compra posterior con otro nombre no lo pisa). El Edge Function `otorgar-puntos` ya se actualizó para mandarlo.

**Error real encontrado y corregido en el camino, más serio que el de nombres de columna:** el primer intento guardó la llave en la columna `codigo_publico`, que YA EXISTÍA desde Fase 1 con un propósito completamente distinto (un código opaco derivado del id interno, `'PT-' + primeros 6 del id`, para que un comercio verifique la identidad de un cliente sin exponer el documento — ver `sistema-puntos-unificado.md` sección 3, "Los dos códigos"). No se revisó qué ya existía antes de escribir la migración. Se detectó de inmediato al verificar con datos reales (el trigger nuevo escribía un valor que un trigger viejo, alfabéticamente posterior, pisaba en cada INSERT). Nunca llegó a producción real (0 clientes reales todavía). Corregido con una migración nueva (`llave_cliente_corrige_colision_codigo_publico`) que deshace el trigger equivocado y crea la columna `llave_cliente` separada — `codigo_publico` sigue funcionando exactamente igual que desde Fase 1, sin tocar.

**Segundo hallazgo en el camino:** `create or replace function` con una lista de parámetros distinta crea un *overload* nuevo en vez de reemplazar la función — quedaron dos versiones de `otorgar_puntos` (7 y 8 parámetros) coexistiendo. La vieja nunca tuvo permiso para `anon`/`authenticated` (sin hueco de seguridad), pero se eliminó para no mantener dos copias de la misma lógica (migración `elimina_overload_viejo_otorgar_puntos`) — una llamada con los 7 argumentos de siempre sigue funcionando igual, gracias al default de `p_nombre`.

**Tercer hallazgo, el más importante de seguridad:** `get_advisors` + consulta directa a permisos confirmó que este proyecto otorga `EXECUTE` a `anon`/`authenticated` por defecto al crear cualquier función nueva (el mismo comportamiento de proyecto ya conocido de fases anteriores) — se me olvidó revocarlo en 3 funciones internas nuevas (con prefijo `_`, nunca deberían llamarse directo): `_normalizar_para_codigo`, `_generar_llave_cliente`, `_trigger_generar_llave_cliente`. Corregido en una migración aparte (`revoca_execute_helpers_llave_cliente`). Re-verificado con `get_advisors`: limpio, sin hallazgos nuevos.

**Verificado con datos de prueba reales (limpiados después):** `jheison68` se genera exactamente como el ejemplo de Jhey; 2 clientes más con el mismo nombre y mismos últimos 2 dígitos generan `jheison868`/`jheison768` (colisión resuelta creciendo el sufijo); nombre con acentos y dos palabras (`María José`) genera `maria99` (solo primer nombre, normalizado); llamada estilo Edge Function actual (sin `p_nombre`) sigue funcionando igual que hoy; llamada con `p_nombre` llena `nombre` y genera la llave; una segunda compra con un nombre distinto no pisa el nombre ya guardado (`Carlos` se queda, no lo reemplaza `Carlos Alberto Otro`).

**Decisión de Jhey (27 ago) que cambia el plan anterior:** no esperar el PIN temporal — construir ya toda la página de Puntos Neggo, identificando al cliente **solo por número de documento** mientras tanto. El PIN sigue siendo el plan de verificación real, pero se pospone; esto se documenta como deuda de seguridad explícita, no un olvido.

**Sub-tarea, portal del cliente (`cliente/index.html`) — hecho y verificado, 27 ago.** Primera página de este proyecto pensada para que el cliente final la use directamente (hasta ahora todo era admin/comercio/servidor-a-servidor). Pantallas: identificarse por documento, ver saldo + historial + puntos por vencer en 30 días, transferir puntos a otro cliente por su llave (`jheison68`), solicitar canje en un comercio disponible y ver el código de verificación para dárselo en persona.

Backend nuevo: 5 funciones `cliente_portal_*` (`estado`, `buscar_destinatario`, `transferir`, `comercios_disponibles`, `solicitar_canje`), todas `SECURITY DEFINER`, otorgadas a `anon` — la **primera vez que este proyecto expone funciones a un navegador anónimo**, rompiendo a propósito la regla histórica "nunca se llama desde el navegador de un cliente" (Fase 3/7). Diseño elegido para no arriesgar la lógica ya probada: estas funciones son wrappers nuevos que llaman por dentro a `transferir_puntos`/`solicitar_canje` ya existentes (que siguen siendo `service_role`-only, sin tocar) — mismos límites antifraude, misma trazabilidad, ningún atajo.

**Riesgo de seguridad real y consciente, no oculto:** con solo el número de documento como identidad, cualquiera que lo conozca puede ver el saldo de otra persona y mover sus puntos (transferir, canjear). Es una decisión de negocio de Jhey para poder avanzar la interfaz ya, con el PIN temporal como reemplazo planeado antes de anunciar la página públicamente. La página ya trae un aviso visible al cliente sobre esto ("por ahora te identificamos solo con tu documento").

**Bug real encontrado y corregido en el camino:** `cliente_portal_estado` asumió que `puntos_por_vencer_cliente` devolvía una columna `puntos_por_vencer` sin revisar la función real — el nombre correcto es `puntos_restantes`. Se detectó de inmediato al probar como `anon` con datos reales (error `column does not exist`), corregido en una migración aparte (`fix_columna_puntos_por_vencer_portal`).

**Verificado con datos y llamadas reales (como rol `anon`, limpiados después):** `cliente_portal_estado` devuelve saldo/nombre/llave/historial correctos; documento no registrado da un error claro; `cliente_portal_buscar_destinatario` encuentra al destinatario por llave y devuelve `[]` (no error) si la llave no existe; una transferencia real entre 2 clientes de prueba movió el saldo correctamente en ambos lados; `anon` sigue sin poder llamar `transferir_puntos` directamente (`permission denied`) — el wrapper es la única puerta; `cliente_portal_solicitar_canje` genera el canje con su código de verificación y descuenta el saldo; comercio inexistente y comercio no encontrado dan error claro. `get_advisors(security)` solo marca los 5 `cliente_portal_*` como ejecutables por `anon` — exactamente lo esperado, ninguna fuga nueva.

**Verificado también el frontend (`cliente/index.html`)** con un navegador real (Playwright) contra respuestas idénticas en forma a las reales ya probadas por SQL (la red de este entorno no permite probar contra Supabase en vivo desde aquí, así que se interceptó solo la capa de red, no la lógica): documento inexistente muestra el error correcto sin entrar; login correcto muestra saldo/llave/historial/aviso de puntos por vencer; la sesión persiste al recargar la página y se borra correctamente al salir; buscar un destinatario por llave muestra su nombre antes de confirmar la transferencia, y una llave inexistente no muestra nada; la transferencia actualiza el saldo en pantalla; el canje valida el mínimo de 200 puntos del lado del cliente y muestra el código de verificación al final. Cero errores de consola en todo el recorrido.

Pendiente (no bloqueante, sub-fases siguientes): el PIN temporal de verificación (reemplazar la identificación por solo-documento), solicitud de pago anticipado, y el adaptador de pago (`PaymentProvider`) con disparo manual y programado.

El envío real de plata no se activa hasta resolver, en este orden:
1. Selección del proveedor financiero regulado (Wompi como primera validación de MVP, SEDPE/BaaS como objetivo, Bold como alternativa) — **gestión de Jhey, no técnica**.
2. Consulta jurídica/regulatoria formal (Ley 1735, régimen SEDPE, Superfinanciera) — **gestión de Jhey**.
3. Diseño del saldo prefondeado por comercio (no emitir puntos "a crédito").
4. Resolver o al menos decidir conscientemente el punto ciego de verificación de identidad de clientes en `neggo-12` (ya documentado en la skill `puntos-neggo-engineering`).

El ledger, la interfaz `PaymentProvider` (adapter, sin amarrar a proveedor) y todo lo de Fases 1–6 se construyen sin esperar esto — el retiro real es la única pieza que depende 100% de gestión externa.

## Resumen de bloqueos activos hoy

| Bloqueo | Tipo | Quién lo resuelve |
|---|---|---|
| Plan de Supabase (¿sigue en Free con 2 proyectos activos, o ya subió a Pro?) | Externo/facturación | Jhey — confirmar estado real |
| Proveedor financiero regulado | Externo/gestión | Jhey |
| Consulta jurídica fintech | Externo/gestión | Jhey |
| Verificación de identidad real en `neggo-12` | Producto hermano, fuera de este repo | Jhey decide prioridad |
| Cómo está integrado hoy `neggo-12` ↔ `ads-ai-platform` técnicamente | Investigación técnica | Se resuelve en Fase 3, revisando código real |

Nada de esto bloquea empezar la Fase 1 hoy mismo.
