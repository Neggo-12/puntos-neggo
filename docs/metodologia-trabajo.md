# Metodología de trabajo — Puntos Neggo

Última actualización: 17 de agosto de 2026.

Propuesta de cómo trabajar este repo de forma eficaz sesión tras sesión, adaptando el mismo patrón que ya funciona en `neggo-12` a un proyecto que mueve puntos/dinero desde el día uno.

## 1. Protocolo de ejecución (ya configurado como skill)

Todo cambio en este repo sigue el protocolo de la skill `puntos-neggo-engineering`:

- **Fase A — Inspeccionar:** leer la spec, verificar estado real de Supabase, buscar si ya existe algo equivalente antes de crear.
- **Fase B — Planificar:** decir qué se va a crear/modificar, por qué, qué guardas de seguridad lleva, antes de escribir código.
- **Fase C — Implementar:** migración con formato `YYYYMMDD_descripcion.sql`, funciones sensibles como `SECURITY DEFINER` con `SET search_path = public`, `UPDATE` con verificación de filas afectadas.
- **Fase D — Verificar:** evidencia real (consulta SQL, prueba real) siempre. Para lo de alto riesgo (puntos, canjes, pagos, RLS, `SECURITY DEFINER`), se invoca la skill `puntos-neggo-verification` antes de dar algo por terminado — no autoevaluación.
- **Fase E — Reportar:** siempre separado en `HECHO / VERIFICADO / NO VERIFICADO / BLOQUEADO / DECISIONES PENDIENTES`. Nunca se presenta una inferencia como evidencia.

Esto no es negociable por eficiencia — es el mismo estándar de `neggo-12`, y en un proyecto que es "la única fuente de verdad del saldo de puntos de cualquier cliente" el costo de un error es dinero real, no un bug cosmético.

## 2. Documentación dual (mismo patrón que `neggo-12/docs`)

- **`docs/roadmap-pendientes.md`** — registro cronológico, sesión por sesión, de qué se hizo, qué se decidió, con qué evidencia se verificó, y qué quedó pendiente. Se agrega al final, nunca se reescribe retroactivamente lo ya loggeado (si algo cambia, se documenta el cambio como entrada nueva).
- **`docs/cronograma-pendientes.md`** — vista resumida "qué falta y cuándo", compilada desde el roadmap al cierre de cada sesión.
- **`docs/modelo-economico-v1.md`** — las reglas de negocio ya definidas (tasas, multiplicadores, condiciones de retiro), separado de la spec de arquitectura para que un cambio de tasa no obligue a tocar el documento de esquema.
- La razón de mantener esto así, igual que en `neggo-12`: que cualquier persona o IA nueva que entre al repo entienda en minutos qué existe, qué está decidido, qué sigue abierto y por qué — sin tener que reconstruir el historial de conversación.

## 3. Decisiones de negocio: preguntar una vez, documentar siempre

Cuando aparece una decisión que afecta plata, tasas, o qué información es pública (no una decisión técnica), se pregunta **una sola vez**, se documenta la respuesta en el archivo que corresponda, y no se vuelve a preguntar. Si la respuesta ya está en `sistema-puntos-unificado.md`, en `modelo-economico-v1.md`, o más arriba en la conversación, se usa directamente.

## 4. Estado externo se re-verifica cada sesión, las decisiones de Jhey no

Dos categorías distintas, y conviene no mezclarlas:

- **Hechos que cambian solos** (¿el proyecto de Supabase sigue activo?, ¿qué migraciones existen ya?, ¿qué dice el esquema real?): se verifican contra la fuente real al inicio de cada sesión nueva, nunca se asumen del historial.
- **Decisiones que Jhey ya tomó en conversación** (una tasa, una corrección, una confirmación): se toman como dadas, no se re-preguntan ni se re-confirman salvo que algo las ponga en duda genuinamente.

## 5. Empaquetar los skills del proyecto como plugin versionado

Hallazgo de revisar `github.com/anthropics` hoy: `anthropics/claude-plugins-official` documenta el formato estándar para empaquetar skills + subagentes + configuración MCP como un plugin instalable (carpeta `.claude-plugin/plugin.json`, `skills/`, `agents/`, `commands/`, `.mcp.json`).

Hoy los 5 skills de `neggo-12` (`neggo-architect`, `neggo-engineer`, `neggo-guardian`, `neggo-reviewer`, `neggo-security`) y los 2 de este proyecto (`puntos-neggo-engineering`, `puntos-neggo-verification`) viven en la sincronización de la cuenta de Claude, no versionados junto al código. Eso significa que si alguna vez se pierden, cambian, o se necesita ver *qué decía la skill en la fecha del commit X*, no hay forma de reconstruirlo desde el repo.

**Recomendación concreta:** mover (o al menos espejar) estas 7 skills a un plugin propio dentro de una organización de plugins privada, o directamente a una carpeta `plugin/` en uno de los repos (probablemente `neggo-12`, como repo "madre" de los estándares que ambos proyectos comparten). Esto es trabajo de configuración, no de código — no lo hago yo solo sin que Jhey lo confirme, porque toca cómo se administran las cuentas/skills, no el backend de Puntos. Lo dejo anotado como tarea de infraestructura, no lo ejecuto en esta sesión.

## 6. Otros hallazgos útiles de `github.com/anthropics` (revisado 17 ago 2026)

- **`anthropics/claude-code`** — la CLI que `neggo-12` ya usa localmente para deploys (`npx wrangler deploy` corrido desde terminal de Claude Code, según su propio `roadmap-pendientes.md`). Confirma que ya hay un flujo local funcionando, no hay que armar uno nuevo.
- **`anthropics/claude-code-action`** — GitHub Action oficial. Podría correr una revisión automática de Claude sobre cada PR de `puntos-neggo` antes de mergear — vale la pena considerarlo dado que cada PR acá puede tocar plata real, pero es una decisión de CI/CD, no urgente para la Fase 1.
- **`anthropics/defending-code-reference-harness`** — skills de threat modeling/scanning pensadas para código que maneja dinero. Útil como checklist de referencia cuando se haga la primera auditoría de seguridad real de este repo (equivalente a la que ya se hizo en `neggo-12` el 24 jul), en vez de reinventar el checklist desde cero.
- **`anthropics/financial-services`** — no aplica directo (está armado para banca de inversión/wealth management, no fidelización), pero confirma el mismo principio que ya seguimos acá: los agentes preparan/registran movimientos, nunca ejecutan transferencias de dinero real sin revisión humana explícita. Sirve como validación externa de que el diseño "ledger primero, retiro real bloqueado detrás de un adapter" es el patrón correcto, no una precaución exagerada.
- **`anthropics/skills`** — repo público de skills de Anthropic. Útil como referencia de formato/convención, no para instalar contenido de terceros directo en un proyecto financiero sin revisarlo.

## 7. Claude Code vs. Cowork — cuál usar para qué

No es una decisión de "uno u otro" — la evidencia de cómo ya trabaja `neggo-12` sugiere un uso combinado:

- **Claude Code (CLI local, en tu Mac) para el grueso del desarrollo día a día:** migraciones, funciones SQL, deploys. `neggo-12` ya usa este flujo (deploys vía terminal de Claude Code) y ya tiene los 5 skills tipo subagente pensados para ese entorno. Usar el mismo patrón acá evita mantener dos formas distintas de trabajar en paralelo, y el acceso a archivos es directo (sin el viaje de ida y vuelta del puente a este dispositivo).
- **Cowork (esta sesión) para lo que hoy mismo se usó:** research cruzado entre repos (`puntos-neggo` + `neggo-12/docs`), síntesis de contexto, documentación, y — más adelante — tareas programadas recurrentes (mismo patrón que `revision-seguridad-neggo`, semanal, ya corriendo en `neggo-12`). También sirve para consultar o destrabar algo desde el celular sin depender de tener la laptop abierta.
- **No son excluyentes:** hoy arrancó acá (catch-up + cronograma + esta metodología); el desarrollo pesado de las Fases 1 en adelante puede bajar a Claude Code local manteniendo la misma skill y el mismo protocolo de documentación — con la condición de seguir actualizando `docs/roadmap-pendientes.md` desde donde sea que se trabaje, para que el otro canal no pierda contexto.

## 8. Alcance y anti-scope creep

Se mantiene la regla de la skill: no se introducen abstracciones, frameworks, dependencias o refactors que no haga falta para la tarea actual. Cualquier mejora detectada fuera de alcance se reporta, no se implementa de paso.
