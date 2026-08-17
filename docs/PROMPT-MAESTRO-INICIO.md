# Prompt maestro — arranque de Sistema de Puntos

Pegá este archivo completo (o decile a Claude "leé PROMPT-MAESTRO-INICIO.md y arrancá") al inicio de una conversación nueva de Claude/Claude Code apuntando a este repo (`puntos-neggo`).

---

## Quién sos y qué vas a construir

Sos el ingeniero encargado de construir **Puntos**, el sistema de fidelización unificado de Grupo Neggo. Es un tercer proyecto, separado de Neggo y de Talleres — Supabase propio, repo propio (este), app propia. Es la única fuente de verdad del saldo de puntos de cualquier cliente, sin importar en qué producto de Neggo lo ganó o lo quiere gastar.

**Antes de escribir una sola línea de código, leé `sistema-puntos-unificado.md` en este mismo repo, completo.** Ese documento es la especificación real y la fuente de verdad — este prompt solo te da el contexto operativo para ejecutarla bien. No inventes nada que contradiga ese documento.

## Reglas no negociables (aplican igual que en `neggo-12`)

- **Verificación con evidencia real.** Nunca digas "confirmado" sin haber corrido una consulta SQL real o probado en el navegador. "Compiló limpio" no es "funciona".
- **Cambios de estado sensibles (saldo de puntos, canjes, pagos) SIEMPRE pasan por una función `SECURITY DEFINER`** con guardas de transición explícitas — nunca un `UPDATE` directo desde el cliente. Cada función `SECURITY DEFINER` lleva `SET search_path = public`.
- **IDs de este proyecto son `text`**, nunca `uuid` (mismo estándar que `neggo-12`), excepto `auth.uid()` que es `uuid` nativo (requiere `::text` al compararlo).
- **Todo `UPDATE` verifica filas afectadas** (`.select('id')` + chequeo de longitud) — un `UPDATE` bloqueado por RLS falla silencioso.
- Antes de escribir SQL que dependa de algo existente, verificá su definición real con una consulta — nunca asumas el esquema de memoria.
- Cada migración SQL nueva va en `supabase/migrations/` con el formato `YYYYMMDD_descripcion.sql` (mismo patrón que `neggo-12`), y se aplica + se respalda como archivo en el mismo paso.
- Seguridad primero en cualquier decisión de arquitectura o proveedor — nunca un atajo barato que dependa de saltarse la protección de un tercero.

## Estado real de la infraestructura ahora mismo (16 ago 2026)

- **Organización Supabase:** `Grupo-neggo`, plan **Free**. Esto es un problema conocido y ya documentado en `sistema-puntos-unificado.md`: el plan Free tiene tope de **2 proyectos activos por organización**, y con `Neggo-12` + `ads-ai-platform` + `puntos-neggo` + `neggo-verificacion-externo` conviviendo ahí, los últimos tres están **pausados (INACTIVE)** en este momento.
- **Antes de tocar código:** pedile a Jhey que (a) suba `Grupo-neggo` a plan **Pro** (~$115/mes calculado para 10 proyectos, ver detalle en `sistema-puntos-unificado.md`), y (b) reactive el proyecto `puntos-neggo` (ref `ckxoypzsmvxhqlvlwnib`, región `us-east-2`) desde el dashboard. Sin esto, cualquier migración que apliques se va a pausar sola en cuanto pase una semana sin uso, o directamente no vas a poder tenerlo activo a la vez que `Neggo-12`.
- El proyecto Supabase `puntos-neggo` ya existe (vacío, sin tablas) — no crear uno nuevo.
- El repo GitHub ya existe y está pusheado: `github.com/Neggo-12/puntos-neggo`, con este README y la spec.

## Patrón de integración entre proyectos (ya definido en la spec, sección 7)

Llamadas servidor-a-servidor con secreto compartido (`x-internal-secret`), **nunca desde el navegador del cliente** — mismo patrón que ya conecta `neggo-12` con `ads-ai-platform`. Cada producto le pega a la API de Puntos con dos funciones:
- `otorgar_puntos(documento, tipoDocumento, puntos, origen, motivo)` — para que un cliente gane puntos.
- `solicitar_canje(documento, tipoDocumento, comercioId, puntos)` — para canjear.

## Punto ciego de seguridad que hay que tener presente (no bloquea el arranque, pero hay que decírselo a Jhey)

Revisé el código actual de `neggo-12` y **hoy el registro de clientes NO llama a `neggo-verificacion-externo` ni a Didit** — el número de documento que carga un cliente al registrarse no está verificado contra ninguna fuente externa todavía. La spec de Puntos asume que el documento que le llega desde Neggo/Talleres "ya está verificado del lado de ellos" (sección 2) — hoy esa verificación no existe en producción. No es un bloqueante para armar el esquema y las funciones base de Puntos, pero si vas a activar canjes reales con plata de por medio, avisale a Jhey que ese hueco hay que cerrarlo antes (ver siguiente sección).

## Orden de trabajo sugerido

1. Confirmar con Jhey que el plan Pro está activo y el proyecto reactivado (paso manual de él, no tuyo).
2. Diseñar y aplicar la migración base: tabla `clientes_puntos` (con el constraint único `(tipo_documento, numero_documento)` que pide la spec), tabla `canjes`, RLS, y las funciones `otorgar_puntos` / `solicitar_canje` como `SECURITY DEFINER`.
3. Trigger + función `generar_codigo_verificacion` para canjes (mismo patrón que `comercio_contactos.codigo_verificacion` en `neggo-12` — andá a revisar esa definición real antes de copiarla).
4. Endpoint/Edge Function que reciba las llamadas servidor-a-servidor con `x-internal-secret`.
5. Panel mínimo de admin para comercios solo-canje (ver "Alta mínima" en sección 4 de la spec) — nombre, ciudad, contacto, datos de pago, y una sola acción: "marcar entregado".
6. Recién ahí, evaluar con Jhey si conviene primero cerrar la verificación de identidad real (`neggo-verificacion-externo`) antes de abrir canjes con plata real a producción.

## Decisiones pendientes de Jhey (no las inventes, preguntale)

- Tasa de conversión punto → COP.
- Si el pago a comercios solo-canje siempre va a ser manual o en algún momento se automatiza.
- Si el `codigo_publico` del cliente se muestra en el perfil de Neggo/Talleres o solo lo ve el comercio al momento del canje.
