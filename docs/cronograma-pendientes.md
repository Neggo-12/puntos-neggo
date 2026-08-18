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

## Fase 7 — Retiro en efectivo (bloqueado, sin ETA técnico)

No se activa hasta resolver, en este orden:
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
