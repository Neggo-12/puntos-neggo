# Roadmap y Pendientes — Puntos Neggo

Última actualización: 17 de agosto de 2026.

## Sesión 17 ago 2026 — Arranque, catch-up y planificación

**Paso 0 ejecutado:**
- Lectura completa de `sistema-puntos-unificado.md` y `PROMPT-MAESTRO-INICIO.md`.
- Verificación real de Supabase (`mcp__Supabase__list_projects` / `list_tables` / `list_migrations`): proyecto `puntos-neggo` (ref `ckxoypzsmvxhqlvlwnib`, región `us-east-2`) está **ACTIVE_HEALTHY** ahora mismo. **Sin tablas ni migraciones todavía** — arranque real desde cero.
- **Hallazgo a confirmar con Jhey:** `ads-ai-platform` y `neggo-verificacion-externo` siguen `INACTIVE` mientras `Neggo-12` y `puntos-neggo` están activos — exactamente 2 proyectos activos a la vez, el mismo tope que tiene el plan **Free** de Supabase (documentado en `sistema-puntos-unificado.md`). Esto es consistente con seguir en Free (reactivaste `puntos-neggo` pausando otro), no con el upgrade a Pro que recomendaba `PROMPT-MAESTRO-INICIO.md`. Si ya subiste a Pro, avisame — si no, `puntos-neggo` se puede volver a pausar solo tras una semana sin uso.
- Revisión de `neggo-12/docs` (carpeta conectada) para entender el patrón real de documentación y metodología ya en uso: `roadmap-pendientes.md` + `cronograma-pendientes.md` como par (detalle cronológico / vista resumida), decisiones de negocio marcadas explícitamente como bloqueantes no técnicos, verificación siempre con evidencia real (consultas SQL, navegador real, nunca "compiló limpio").

**Trabajo de esta sesión (no es código de producto — es planificación y documentación base):**
- `docs/cronograma-pendientes.md` — fases del backend de Puntos, de Fase 0 (esta sesión) a Fase 7 (retiro en efectivo, bloqueado).
- `docs/metodologia-trabajo.md` — protocolo de trabajo, patrón de documentación dual, cuándo usar Claude Code local vs. Cowork, hallazgos de `github.com/anthropics`.
- `docs/modelo-economico-v1.md` — modelo económico y regulatorio V1 que definió Jhey (tasas, multiplicadores, condiciones de retiro, arquitectura de dos capas Puntos/proveedor financiero). Resuelve varias de las "decisiones pendientes" que dejaba abierta `sistema-puntos-unificado.md` sección 8 — ver ese documento para el detalle completo.

**DECISIONES DOCUMENTADAS HOY (ya definidas por Jhey, no inventadas):**
- Tasa de conversión: $800 compra = 1 punto, 1 punto = $10 de valor. Ver `modelo-economico-v1.md` sección 1.
- Multiplicadores 1X/2X/3X/5X, no acumulables, techo en 5X. Ver sección 2.
- Condiciones de desbloqueo de retiro en efectivo (30% consumo interno + 6 meses + 5 transacciones, 70% retirable). Ver sección 4.
- Arquitectura de dos capas (Puntos = ledger, proveedor financiero regulado = dinero real) con interfaz `PaymentProvider` como adapter. Ver sección 7.

**SIGUE ABIERTO (no se inventó, queda para cuando corresponda):**
- Ventana exacta de aviso de vencimiento de puntos.
- Límites diario/mensual de transferencia persona a persona.
- Mecanismo exacto de corte de presupuesto de campaña a mitad de transacción.
- Proveedor financiero final (Wompi / SEDPE-BaaS / Bold) y consulta jurídica formal — gestión de Jhey, fuera del alcance técnico.
- Visibilidad del `codigo_publico` del cliente (ya estaba abierta en la spec original, sigue sin resolver).
- Empaquetar los 7 skills del proyecto (`neggo-*` + `puntos-neggo-*`) como plugin versionado — anotado como mejora de infraestructura, no ejecutado esta sesión (requiere decisión de Jhey sobre dónde vivir).

**NO se tocó código de producto ni se aplicó ninguna migración esta sesión** — el arranque de la Fase 1 (migración base `clientes_puntos`/lotes/`canjes` + funciones `SECURITY DEFINER`) queda para la próxima sesión.

## Sesión 17 ago 2026 (continuación) — Fase 1+2: ledger base aplicado y verificado

**Hallazgo importante antes de migrar:** `neggo-12` ya tiene su propio sistema de puntos interno (`puntos_movimientos`, `puntos_liquidaciones`, `puntos_tasas_comercio`, funciones `emitir_puntos_por_compra`/`canjear_puntos`), con tasa **negociada por comercio** (`puntos_por_1000`), distinta del modelo fijo (1,25% base) que define `modelo-economico-v1.md`. Esto contradice el principio de la spec ("ni Neggo ni Talleres guardan puntos en su propia base") — hoy sí lo hacen. **No bloquea esta migración** (corre en un proyecto Supabase separado y vacío), pero la migración/cutover de ese sistema hacia `puntos-neggo` es una decisión de Jhey pendiente, no técnica todavía.

**Migraciones aplicadas (Supabase, proyecto `puntos-neggo`, directo por MCP — no requirió Claude Code):**
1. `20260817_ledger_base.sql` — tablas `clientes_puntos`, `puntos_movimientos`, `canjes`, `audit_log`; triggers de `codigo_publico` y `codigo_verificacion_canje` (mismo patrón hash+salt que `comercio_contactos` en `neggo-12`, salt propio); funciones `otorgar_puntos`/`solicitar_canje` `SECURITY DEFINER`; RLS habilitada sin policies (deny-all, solo `service_role` accede).
2. `20260817_fix_grants_security_definer.sql` — corrige que el `REVOKE ... FROM anon, authenticated` original no bloqueaba nada real: Postgres otorga `EXECUTE` a `PUBLIC` por defecto y esos roles heredan de ahí. Encontrado con `get_advisors(security)`, no asumido.
3. `20260817_fix_ambiguous_cliente_id.sql` — `otorgar_puntos` fallaba en runtime (`column reference "cliente_id" is ambiguous`): el nombre de columna de salida colisionaba con la columna de la tabla. Encontrado ejecutando la función con datos reales, no por el `apply_migration` (plpgsql compila recién en la primera llamada).
4. `20260817_fix_ambiguous_codigo_verificacion.sql` — mismo bug, en `solicitar_canje` (`codigo_verificacion`). Mismo método de detección.

**Decisiones de diseño que se apartan de la lectura literal de `sistema-puntos-unificado.md` sección 7** (documentado también como comentario en la migración):
- `otorgar_puntos` calcula el multiplicador (1X/2X) internamente, nunca confía en un valor que mande el caller — "cliente nuevo" es un concepto cruzado entre productos que solo Puntos puede verificar. 3X/5X quedan fuera de esta migración (dependen de infraestructura de campañas/inactividad, Fase 6).
- Se agregó `p_referencia_externa` para idempotencia — sin eso, la regla de "transacción duplicada → rechazo" de `modelo-economico-v1.md` sección 9 era imposible de cumplir.

**VERIFICADO con evidencia real (no inferencia):**
- `get_advisors(security)` antes/después de cada fix — confirmado que `anon`/`authenticated` quedaron sin `EXECUTE` en `_log_audit`/`otorgar_puntos`/`solicitar_canje` (`information_schema.routine_privileges`).
- `SET LOCAL ROLE anon/authenticated` + `SELECT` sobre `clientes_puntos` → 0 filas visibles (RLS deny-all real, no solo "debería andar").
- `SET LOCAL ROLE anon` + llamada a `otorgar_puntos` → `permission denied` real.
- Flujo completo con datos de prueba (documento `TEST-VERIF-0001`, luego borrado): compra $800.000 → 2000 puntos (2X cliente nuevo) → segunda compra mismo comercio → 1000 puntos (1X) → **reintento con la misma `referencia_externa`** → devuelve el resultado original sin duplicar movimiento (idempotencia real) → canje de 1000 puntos → saldo baja a 2000, `codigo_verificacion` generado, `audit_log` con las 3 entradas esperadas y ninguna de más → canje por debajo del mínimo (200) rechazado → canje por más del saldo disponible rechazado, sin afectar el saldo real. Datos de prueba eliminados al final (las 4 tablas quedaron en 0 filas).

**Archivos de respaldo:** las 4 migraciones están en `supabase/migrations/` del repo, mismo contenido que se aplicó.

**Pendiente (Fase 3 del cronograma):** Edge Function/endpoint con validación de `x-internal-secret` para exponer `otorgar_puntos`/`solicitar_canje` servidor-a-servidor — antes de construirla, revisar en el código real de `neggo-12` cómo está armada hoy la integración con `ads-ai-platform` para no inventar un patrón nuevo si ya existe uno.

## Sesión 17 ago 2026 (continuación 2) — Aclaraciones de Jhey + Fase 3 desplegada

**Aclaraciones de Jhey (documentadas, no se vuelven a preguntar):**
- El sistema de puntos viejo de `neggo-12` (`puntos_movimientos`, `puntos_liquidaciones`, `puntos_tasas_comercio`) era la versión inicial y **va a desaparecer**; solo queda el visual de puntos en `neggo-12`. No se toca ni se va a tocar desde este repo.
- Va a existir un proyecto aparte que conecta las APIs de todos los productos de Neggo. Por eso no hacía falta investigar el patrón puntual `neggo-12` ↔ `ads-ai-platform` para construir la Fase 3 — el contrato de `puntos-neggo` (URL + `x-internal-secret` + JSON) queda igual sin importar quién termine llamándolo.

**Desplegado (Supabase Edge Functions, proyecto `puntos-neggo`, directo por MCP — no requirió Claude Code):**
- `otorgar-puntos` y `solicitar-canje`, `verify_jwt=false` (autenticación propia por header, justificada explícitamente por la guía de la herramienta de deploy). Validan `x-internal-secret` contra la variable de entorno `INTERNAL_SECRET`, parsean y validan el body, llaman a `otorgar_puntos`/`solicitar_canje` vía `service_role`, devuelven 401/400/500 según corresponda. Código respaldado en `supabase/functions/otorgar-puntos/index.ts` y `supabase/functions/solicitar-canje/index.ts`.
- Secreto generado (32 bytes, hex) — entregado a Jhey en el mensaje de cierre de esta sesión para que lo cargue en Supabase. No lo genera ni lo carga el proyecto conector todavía porque ese proyecto no existe aún.

**NO VERIFICADO (bloqueado, requiere acción externa):**
- Sin `INTERNAL_SECRET` cargado, ambas funciones responden `server_misconfigured` (500) a propósito — comportamiento fail-closed, no un bug.
- No se pudo probar la llamada HTTP real end-to-end desde este entorno (sin salida de red a dominios externos desde este sandbox). Falta que Jhey (o quien corresponda con Claude Code local, que sí tiene red real) corra una prueba real una vez cargado el secreto. Comando exacto entregado en el mensaje de cierre.

## Sesión 17 ago 2026 (continuación 3) — Fase 3 verificada en producción + Fase 4 (base)

**Verificado:** Jhey cargó `INTERNAL_SECRET` en el dashboard y corrió el curl real. Respuesta: `{"cliente_id":"...","puntos_otorgados":2000,"multiplicador":2,"saldo_nuevo":2000,"ya_procesado":false}` — correcto (primera compra de $800.000 en un comercio nuevo → 2X). Dato de prueba (`PRUEBA-001`) borrado de producción después de confirmar. **Fase 3 cerrada.**

**Migraciones aplicadas (Fase 4, base):**
1. `20260817_admin_comercios_solo_canje.sql` — tabla `comercios_solo_canje`, tabla `admins` (allowlist, `user_id uuid references auth.users(id)`, sin policies — se administra solo por SQL), políticas RLS que restringen `comercios_solo_canje`/`canjes`/`clientes_puntos` a usuarios en `admins`, función `marcar_canje_pagado` (`SECURITY DEFINER`, transición `pendiente_pago → pagado` explícita).
2. `20260817_fix_grants_marcar_canje_pagado.sql` — `get_advisors(security)` encontró que `anon` podía ejecutar `marcar_canje_pagado` (grant directo a `anon`, no vía `PUBLIC` como en la Fase 1 — mecanismo distinto, mismo tipo de hallazgo). Corregido revocando de `public`/`anon`/`authenticated` y otorgando solo a `authenticated`.

**VERIFICADO con evidencia real:**
- `get_advisors(security)` post-fix: sin hallazgos de `anon` ejecutando funciones sensibles.
- `SET LOCAL ROLE anon` + `marcar_canje_pagado` → `permission denied` real.
- `SET LOCAL ROLE authenticated` con un `auth.uid()` simulado que NO está en `admins` → `SELECT` sobre `canjes`/`comercios_solo_canje` devuelve 0 filas (RLS real); `marcar_canje_pagado` devuelve `'No autorizado'` (guarda dentro de la función, no solo RLS).

**NO VERIFICADO (falta cuenta real de Jhey):** el camino de admin autorizado (login real → ver canjes → marcar entregado) no se pudo probar de punta a punta porque requiere un usuario real de Supabase Auth, que solo Jhey puede crear. No se simuló insertando directo en `auth.users` — manipular esa tabla a mano es frágil y no es el flujo real. Instrucciones entregadas en el mensaje de cierre.

**Entregado:** `admin/index.html` — página sola (sin framework), login Supabase Auth, lista de canjes pendientes con código de verificación visible, botón "Marcar entregado", alta de comercios solo-canje. Pensada para abrirse con un servidor estático local por ahora (no vía `file://`, los imports de módulo ES no cargan bien desde ahí) — hosting persistente (GitHub Pages u otro) queda como decisión aparte, no se inventó una ahora.

## Sesión 17 ago 2026 (continuación 4) — Bug real de RLS en Fase 4, corregido y verificado

Jhey creó su cuenta (`jf.neggo@gmail.com`), se agregó a `admins`, abrió el panel local y probó agregar un comercio. **Falló:** `new row violates row-level security policy for table "comercios_solo_canje"`, con un admin real ya cargado.

**Causa real (encontrada, no asumida):** las policies de `comercios_solo_canje`/`canjes`/`clientes_puntos` consultaban `admins` directo (`exists (select 1 from admins where user_id = auth.uid())`). Esa subconsulta corre con el rol de quien llama (`authenticated`), y `admins` tiene RLS habilitada sin policies a propósito (nadie la lee directo) — entonces la subconsulta siempre veía 0 filas, incluso para un admin real. Bug de diseño propio, no de Supabase.

**Fix (`20260817_fix_rls_admins_check.sql`):** función `is_admin()` `SECURITY DEFINER` (bypassa RLS de `admins` a propósito, mismo patrón ya usado en `otorgar_puntos`/`solicitar_canje`/`marcar_canje_pagado`), las 5 policies reescritas para llamar a `is_admin()` en vez de consultar la tabla directo.

**VERIFICADO con evidencia real:** simulando el `auth.uid()` real de Jhey (`86a52e2c-1172-4c51-810a-627155c5fc67`) vía `SET LOCAL request.jwt.claims` — `is_admin()` devuelve `true`, `INSERT` en `comercios_solo_canje` funciona. Fila de prueba borrada después. Confirmado también por Jhey desde el navegador real: alta de comercio exitosa.

## Sesión 17 ago 2026 (continuación 5) — Flujo completo de canje verificado en vivo, Fase 4 cerrada

Se creó un canje de prueba real (`otorgar_puntos` → 2000 puntos, cliente `TEST-ADMIN-FLOW` → `solicitar_canje` de 500 puntos, comercio "Comercio de prueba admin", código `839 337`). Jhey lo vio en el panel real (`http://localhost:8787`), confirmó el código y marcó "Marcar entregado".

**VERIFICADO con evidencia real (consulta directa, no el mensaje de éxito de la UI):** `canjes.estado = 'pagado'`, `pagado_por = '86a52e2c-1172-4c51-810a-627155c5fc67'` (su usuario real), `pagado_at` con timestamp real, `audit_log` con `canje.marcado_pagado`. Todos los datos de prueba (cliente, movimientos, canje, audit log) eliminados después de confirmar.

**Fase 4 cerrada — funcionalidad completa verificada de punta a punta: alta de comercio, otorgar puntos, solicitar canje, ver pendiente con código, marcar entregado, ledger y auditoría correctos.**

## Sesión 17 ago 2026 (continuación 6) — Fase 5: pasivo financiero visible

**Migración aplicada:** `20260817_pasivo_puntos.sql` — función `obtener_pasivo_puntos()`, **a propósito no `SECURITY DEFINER`** (corre con los privilegios del que llama, así que la RLS ya existente de `clientes_puntos` — solo admins — sigue aplicando sola: un no-admin autenticado ve ceros, no un error ni el dato real, sin tener que duplicar la lógica de "es admin" dentro de la función).

**Caveat real, documentado en la migración y en el panel (no oculto):** la suma no descuenta lotes con `fecha_vencimiento` ya pasada, porque el barrido de vencimiento todavía no existe (Fase 6) — puede sobreestimar el pasivo hasta que esa fase se construya.

**VERIFICADO con evidencia real:**
- `get_advisors(security)` post-migración: sin hallazgos nuevos.
- `information_schema.routine_privileges`: `anon`/`public` sin `EXECUTE`, solo `authenticated`.
- Datos de prueba (`TEST-PASIVO-001`, 2000 puntos otorgados): simulando sesión de admin real → `obtener_pasivo_puntos()` devolvió `{puntos_en_circulacion:2000, valor_cop:"20000", clientes_con_saldo:1}` (2000 × $10 = $20.000, correcto). Simulando sesión `authenticated` sin fila en `admins` → `{0,"0",0}` (no error, no dato real filtrado). Datos de prueba eliminados después.

**Entregado:** `admin/index.html` actualizado — nueva sección "Pasivo financiero (puntos en circulación)" arriba de "Canjes pendientes de pago", con 3 cifras (puntos en circulación, valor de referencia en COP, clientes con saldo) y la nota de la limitación de vencimiento visible en el panel, no solo en el código. `cargarPasivo()` se ejecuta junto con `cargarCanjes()`/`cargarComercios()` al entrar.

**Pendiente de confirmación de Jhey:** recargar el panel local y confirmar visualmente que las 3 cifras aparecen (hoy en 0 porque no hay puntos reales en circulación en este momento — eso es correcto, no un bug).

**Fase 5 cerrada del lado técnico — a la espera de confirmación visual de Jhey.**

**Confirmado por Jhey:** vio el panel con la sección de pasivo financiero. **Fase 5 cerrada, verificada.**

## Sesión 17 ago 2026 (continuación 7) — Fase 6, sub-tarea 1: vencimiento por lote (barrido)

**Problema real a resolver:** el ledger no rastrea contra qué lote `ganado` específico se aplica cada canje (`solicitar_canje` solo resta del saldo total). Sin eso, no se puede saber cuánto de un lote sigue sin consumir cuando llega su `fecha_vencimiento` — necesario para que el pasivo financiero (Fase 5) sea exacto, no solo un caveat.

**Diseño (`20260817_barrido_vencimientos.sql`):**
- Columna nueva `puntos_movimientos.lote_origen_id` — en filas `vencido`, referencia al movimiento `ganado` del que salieron esos puntos.
- `_pendiente_por_lote(cliente_id)` (interna, `SECURITY DEFINER`, sin grant a `anon`/`authenticated`): recalcula en cada llamada, en orden FIFO (lote más antiguo primero), cuánto de cada lote `ganado` sigue sin consumir — sumando todo lo `canjeado`/`transferido_salida`/`vencido` como consumo total y restándolo lote por lote. No arrastra estado propio: es puro cálculo sobre el ledger existente, así que correrlo de nuevo es seguro.
- `ejecutar_barrido_vencimientos()` (`SECURITY DEFINER`, mismo grant restringido): recorre clientes con `saldo > 0`, y para cada lote con `fecha_vencimiento < hoy` y puntos restantes > 0, inserta un movimiento `vencido`, descuenta el saldo, y registra `audit_log`.
- **Decisión técnica documentada (no de negocio):** orden de consumo FIFO. Ni `sistema-puntos-unificado.md` ni `modelo-economico-v1.md` especifican el orden de consumo — no era una decisión de Jhey pendiente, es el estándar de la industria para puntos con vencimiento, así que se tomó y se documentó en el comentario de la migración.
- Programado con `pg_cron` (extensión ya disponible en el proyecto, instalada en esta migración): corre todos los días 06:00 UTC (01:00 Bogotá, Colombia no tiene horario de verano).
- **Fuera de alcance a propósito, para cuando existan (no se construyó de más):** transferencias punto a punto (`transferido_salida` ya cuenta como consumo en el cálculo; `transferido_entrada` va a necesitar sumarse como lote cuando se construya esa sub-tarea) y notificación de vencimiento próximo (sub-tarea aparte de Fase 6).

**VERIFICADO con evidencia real, no inferencia:**
- `get_advisors(security)`: sin hallazgos nuevos (los 2 `WARN` existentes de `is_admin`/`marcar_canje_pagado` son intencionales y ya documentados, no relacionados con esta migración).
- `information_schema.routine_privileges`: `_pendiente_por_lote` y `ejecutar_barrido_vencimientos` solo tienen `EXECUTE` para `postgres`/`service_role` — nada para `anon`/`authenticated`.
- Prueba funcional con datos reales (cliente `TEST-VENC-001`): 2 lotes de 300 puntos cada uno (comercios distintos, ambos 2X por ser "cliente nuevo" en cada comercio) → saldo 600 → canje de 250 puntos → FIFO confirmado por consulta directa a `_pendiente_por_lote` antes de vencer nada: lote 1 con 50 restantes, lote 2 con 300 intactos → se vence artificialmente el lote 1 (`fecha_vencimiento` a ayer) → `ejecutar_barrido_vencimientos()` vence exactamente los 50 puntos restantes del lote 1 (`vencido`, `lote_origen_id` apuntando al lote correcto), lote 2 queda intacto por no estar vencido → saldo baja a 300 (600 − 250 − 50), coincide exacto con lo esperado.
- **Idempotencia confirmada:** segunda corrida de `ejecutar_barrido_vencimientos()` sobre el mismo cliente devuelve `clientes_afectados: 0, puntos_vencidos: 0` — no duplica el vencimiento.
- `cron.job` confirmado activo (`jobname: puntos-neggo-barrido-vencimientos`, `schedule: 0 6 * * *`, `active: true`).
- Todos los datos de prueba (cliente, movimientos, canje, audit log) eliminados después de confirmar.

**Panel actualizado:** la nota de "Pasivo financiero" en `admin/index.html` ya no dice que no descuenta vencidos — ahora explica que el barrido corre diario y puede haber hasta 24h de rezago (no es tiempo real, es correcto por diseño).

**Fase 6, sub-tarea 1 (vencimiento por lote) cerrada y verificada.**

## Sesión 17 ago 2026 (continuación 8) — Fase 6, sub-tarea 2: reversos y fraude + hallazgo de seguridad real

**Diseño (`20260817_reversos_fraude.sql`, modelo-economico-v1.md sección 9):**
- `clientes_puntos.estado` (`activo`/`congelado`) y `clientes_puntos.bloqueo_redencion` (booleano).
- `otorgar_puntos`/`solicitar_canje` (mismo cuerpo vigente, verificado con `pg_get_functiondef` antes de tocar nada, solo se agregó el guardado): `congelado` bloquea ambas funciones por completo; `bloqueo_redencion` bloquea solo `solicitar_canje` (la spec pide explícitamente que la cuenta sospechosa siga acumulando, no solo redimiendo).
- `revertir_puntos_otorgados(origen_producto, referencia_externa, motivo)`: reversión de compra cancelada/devuelta. Mismo modelo de acceso que `otorgar_puntos`/`solicitar_canje` (solo `service_role`, server-a-servidor). Idempotente por la misma referencia externa.
- **Decisión técnica documentada (caso límite que la spec no cubre):** qué pasa si se cancela una compra pero el cliente ya gastó esos puntos. Se eligió el diseño conservador: nunca saldo negativo (constraint ya existente lo garantiza), la reversión recupera como máximo el saldo disponible, y lo no recuperado queda en `audit_log` (`puntos_no_recuperados`) para revisión manual de Jhey -- no se inventó un modelo de "deuda".
- `congelar_cliente`/`descongelar_cliente`/`bloquear_redencion_cliente`/`desbloquear_redencion_cliente`: acciones de admin humano, mismo patrón de `is_admin()` que `marcar_canje_pagado`.

**HALLAZGO DE SEGURIDAD REAL (encontrado por `get_advisors`, corregido antes de seguir):** las 5 funciones nuevas quedaron ejecutables por `anon` (sin login) vía API REST, incluyendo `revertir_puntos_otorgados` -- cualquiera con la key pública podía revertir puntos de cualquier cliente o congelar/bloquear cuentas ajenas. Causa real: siguiendo el patrón de `marcar_canje_pagado` se revocó `EXECUTE` solo de `public`, pero este proyecto tiene privilegios por defecto que otorgan `EXECUTE` en funciones nuevas directo a `anon`/`authenticated`/`service_role` (no vía `PUBLIC`) -- revocar de `public` no alcanza. La migración de barrido de vencimientos (sesión anterior) sí había revocado explícito de `anon`/`authenticated` y por eso salió limpia; esta vez no se replicó ese detalle. Corregido en `20260817_fix_grants_reversos_fraude.sql` -- confirmado con `information_schema.routine_privileges` que `anon` ya no aparece en ninguna, y con una llamada real simulando `SET LOCAL ROLE anon` que devuelve `permission denied` real (no solo el advisor). **Lección para toda migración futura: revocar siempre de `public, anon, authenticated` explícitamente, nunca asumir que revocar de `public` alcanza.**

**VERIFICADO con evidencia real, no inferencia (todo con datos de prueba, limpiados después):**
- `congelar_cliente` bloquea `otorgar_puntos` y `solicitar_canje` con el mensaje esperado; `descongelar_cliente` los restaura.
- `bloquear_redencion_cliente` bloquea `solicitar_canje` pero `otorgar_puntos` sigue funcionando con normalidad (saldo subió de 700 a 900 puntos con la cuenta bloqueada); `desbloquear_redencion_cliente` restaura el canje.
- `revertir_puntos_otorgados`, reversión completa (nada gastado): 400/400 revertidos, 0 no recuperados. Repetido: `ya_procesado: true`, no duplica.
- `revertir_puntos_otorgados`, reversión parcial (250 de 400 ya canjeados): recupera exactamente los 150 disponibles, registra 250 como no recuperados, saldo nunca negativo. Repetido: idempotente, mismo resultado.
- `SET LOCAL ROLE anon` contra `revertir_puntos_otorgados` y `congelar_cliente`: `permission denied` real en ambos, post-fix.
- Sesión `authenticated` simulada con un `auth.uid()` que NO está en `admins`: `congelar_cliente` devuelve `'No autorizado'` (guarda interna, no solo RLS).
- `get_advisors(security)` final: solo quedan los 4 `WARN` esperados de `authenticated` en las funciones admin-gateadas (mismo patrón ya aceptado de `marcar_canje_pagado`/`is_admin`), cero hallazgos de `anon`.

**Fase 6, sub-tarea 2 (reversos y fraude) cerrada y verificada.**

## Sesión 17 ago 2026 (continuación 9) — Fase 6, sub-tarea 3: notificación de vencimiento próximo + gap real corregido

**Gap encontrado antes de empezar:** `revertir_puntos_otorgados` (sesión anterior) quedó restringida a `service_role`, correcto para seguridad, pero nunca se le construyó el Edge Function -- sin eso, Neggo/Talleres no tenían forma real de llamarla por HTTP. Corregido en esta sesión junto con la nueva funcionalidad, no se dejó pendiente.

**Diseño (`20260817_puntos_por_vencer.sql`, modelo-economico-v1.md sección 6):**
- `puntos_por_vencer_cliente(tipo_documento, numero_documento, dias default 15)` -- reutiliza `_pendiente_por_lote` (misma función que ya usa el barrido de vencimientos), filtrando lotes que **todavía no vencieron** pero vencen dentro de la ventana pedida, en vez de lotes ya vencidos.
- **Decisión pendiente de Jhey, no inventada (ya estaba abierta en `modelo-economico-v1.md` sección 11):** la ventana exacta de aviso. Se implementó como parámetro con default 15 días -- es el número que el propio Jhey puso como ejemplo en la spec, no uno nuevo inventado, pero sigue siendo configurable por llamada, no una decisión final cerrada.
- Puntos Neggo no envía notificaciones (no tiene canal propio) -- solo expone la data vía Edge Function; el producto que consume esto (Neggo/Talleres) decide push/email/banner.

**Desplegado (Edge Functions, mismo patrón de `otorgar-puntos`/`solicitar-canje` -- `x-internal-secret`, `verify_jwt=false`):**
- `puntos-por-vencer` -- envuelve `puntos_por_vencer_cliente`.
- `revertir-puntos` -- envuelve `revertir_puntos_otorgados` (el gap de la sesión anterior).

**VERIFICADO con evidencia real:**
- `get_advisors(security)` + `information_schema.routine_privileges`: `puntos_por_vencer_cliente` solo `postgres`/`service_role`, sin `anon`/`authenticated` -- se revocó explícito de los 3 desde el inicio esta vez (lección de la sesión anterior aplicada).
- Prueba funcional con datos reales (cliente `TEST-VENCER-001`): 2 lotes de 300 puntos, uno reubicado a 10 días de vencer, el otro a 12 meses -- `puntos_por_vencer_cliente(..., 15)` devolvió exactamente el lote de 10 días, el de 12 meses quedó afuera. Cliente inexistente -> lista vacía, sin error. Datos de prueba eliminados después.
- Los 2 Edge Functions se desplegaron con `status: ACTIVE`. **No se pudo probar la llamada HTTP real desde este entorno** (sin salida de red, misma limitación que Fase 3) -- comandos curl exactos entregados a Jhey en el mensaje de cierre para que él (o Claude Code local) confirme end-to-end.

**Pendiente de confirmación de Jhey:** correr los 2 curls de prueba y confirmar respuesta.
