# Sistema de Puntos unificado (Neggo + Talleres + futuros proyectos)

## 1. Qué es

Un tercer proyecto, separado de Neggo y de Talleres — Supabase propio, repo propio, app propia pequeña. Es la única fuente de verdad del saldo de puntos. Ni Neggo ni Talleres guardan puntos en su propia base — cada uno le pregunta a Puntos por API y le avisa cuando un cliente hizo algo que gana puntos.

## 2. Identidad — llave: número de documento

Decisión de Jhey: la llave de cruce entre proyectos es el **número de documento**, no el email. Motivo: el documento no cambia, el email sí.

- Tabla `clientes_puntos`: `id` (interno), `tipo_documento`, `numero_documento` (llave única, not null), `email`, `telefono`, `nombre`, `codigo_publico`, `saldo`, `created_at`, `updated_at`.
- Constraint único sobre `(tipo_documento, numero_documento)`.
- `email` y `telefono` deben estar siempre actualizados — ahí llega el código de seguridad de cada canje. Si están vencidos/mal, el cliente no puede confirmar un canje. Esto hay que dejarlo visible en el perfil (algo tipo "actualizá tu correo/celular para poder canjear puntos").

Cuando Neggo o Talleres le reportan una acción que gana puntos, mandan `tipo_documento + numero_documento` (el que ya está verificado del lado de ellos, nunca uno que mande el cliente sin validar) — Puntos hace `insert on conflict` sobre esa llave: si no existe el cliente lo crea, si existe le suma el movimiento. El cliente nunca ve un login de "Puntos" — ve su saldo dentro de Neggo y dentro de Talleres, cada uno leyéndolo de la API de Puntos.

## 3. Los dos códigos — no son lo mismo

**Código público del cliente** (`codigo_publico`, tabla `clientes_puntos`): identifica al cliente frente a un comercio, igual que el `codigo_neggo` que ya existe para comercios (`'NG-' + primeros 6 del id`). Se genera una sola vez, al crear el registro. Ejemplo de patrón: `'PT-' || upper(left(id, 6))`. Sirve para que un comercio pueda verificar "sí, este es el cliente X" sin exponer el documento completo.

**Código de verificación por canje** (`codigo_verificacion`, tabla `canjes`): mismo patrón que `comercio_contactos.codigo_verificacion` — se genera automático (trigger + `generar_codigo_verificacion`) en cada canje nuevo, y se manda por email/SMS al cliente. El comercio (o vos, en el caso de comercios solo-canje) tiene que decir ese código antes de entregar el producto/servicio — si no lo dice, es señal de que algo no cuadra. Este es el mecanismo anti-fraude, no el identificador del cliente.

> **Nota importante:** hoy Neggo NO tiene un código público de cliente ya existente — solo el `id` interno (un código largo tipo uuid que no se le muestra a nadie) y el número de documento. El `codigo_publico` de Puntos es algo NUEVO que se crea desde cero, no algo que ya exista para "integrar". Ver explicación simple más abajo.

### ¿Por qué Neggo no tiene un "código de cliente" hoy? (explicado simple)

Pensá en Neggo como una lista enorme de personas guardada en una libreta. Cada persona tiene un número de fila (eso es el `id` — como el número de página de la libreta, nadie lo ve, solo la computadora lo usa para no perderse). También tiene su cédula anotada. Pero nunca nadie se sentó a inventarle a esa persona un "código bonito" tipo `NG-4X7B2P` para mostrárselo o dárselo a un tercero. Eso SÍ se hizo para los comercios (`codigo_neggo`, ej. `NG-A1B2C3`) porque un cliente necesita poder verificar "¿este negocio es de verdad?" antes de confiar. Para los clientes nunca hizo falta eso, porque nadie más necesitaba verificar al cliente — hasta ahora, con Puntos, que sí lo vas a necesitar (el comercio solo-canje necesita poder decir "sí, sos vos"). Por eso hay que crearlo nuevo, no reusar nada.

## 4. Tipos de comercio dentro de Puntos

1. **Comercio ya afiliado a Neggo o Talleres** — ve el canje como una feature más dentro de su dashboard existente. No necesita alta aparte.
2. **Comercio solo-canje** (tu ejemplo del hotel) — no es parte de Neggo ni de Talleres, solo participa de la red de puntos. Alta mínima: nombre, ciudad, contacto, datos para pagarle (cuenta bancaria/Nequi). Panel restringido: solo ve solicitudes de canje entrantes + botón "marcar entregado". Nada de CRM, nada de campañas, nada de estadísticas.

## 5. Flujo de canje (comercio solo-canje)

1. Cliente pide canjear X puntos en el comercio Y, desde donde esté (Neggo, Talleres, o el portal de Puntos si el comercio no está en ninguno de los dos ecosistemas).
2. Puntos descuenta el saldo al instante (evita doble canje) y crea el registro en `canjes` con estado `pendiente_pago`, y genera el `codigo_verificacion`.
3. Notificación a Jhey (admin de Puntos).
4. El comercio le entrega el producto/servicio al cliente solo si el cliente le dice el código de verificación correcto.
5. Jhey le paga al comercio por fuera del sistema (transferencia manual).
6. Jhey marca el canje como `pagado` en el panel admin — misma lógica SECURITY DEFINER + `_log_audit` que ya se usa en el resto de Neggo.

## 6. Pasivo financiero — no es solo arquitectura

Cada punto emitido es plata real que en algún momento hay que pagarle a un comercio. Falta definir:
- Tasa de conversión fija punto → COP.
- Un número visible de "puntos en circulación sin canjear" — es un pasivo, tiene que estar a la vista en algún panel, no escondido.

## 7. Integración técnica entre proyectos

Mismo patrón que ya existe entre `neggo-12` y `ads-ai-platform`: llamadas servidor-a-servidor con un secreto compartido (`x-internal-secret`), nunca desde el navegador del cliente. Cada producto (Neggo, Talleres, los que vengan) le pega a la API de Puntos con: `otorgar_puntos(documento, tipoDocumento, puntos, origen, motivo)` para ganar, y `solicitar_canje(documento, tipoDocumento, comercioId, puntos)` para canjear.

## 8. Decisiones pendientes de Jhey

- ~~Tasa de conversión punto → COP.~~ **Resuelto 17 ago 2026** — ver `docs/modelo-economico-v1.md` (sección 1: $800 = 1 punto, 1 punto = $10; sección 4: condiciones de retiro en efectivo).
- Pago a comercios solo-canje: ¿siempre manual, o en algún punto se automatiza (Nequi/transferencia por API)? — **sigue abierto.**
- ¿El `codigo_publico` del cliente se muestra en algún lugar del perfil de Neggo/Talleres, o solo lo ve el comercio al momento del canje? — **sigue abierto.**

> Nota (17 ago 2026): el modelo económico completo — multiplicadores, transferencias, vencimientos, y la decisión de arquitectura de separar la capa de Puntos (ledger) de una capa financiera regulada para el retiro en efectivo — quedó documentado en `docs/modelo-economico-v1.md`. Ese documento no reemplaza este esquema; lo complementa con las reglas de negocio que acá quedaban abiertas.

---

# Orden de cuentas (GitHub + Supabase) — nota aparte

Esto es administración de cuentas, no código — lo tenés que ejecutar vos mismo (no tengo acceso a tus otras cuentas de Google/GitHub/Supabase).

**GitHub:** creá UNA GitHub Organization (ej. algo tipo "neggo-group" o "grupo-neggo"), de la cuenta que ya usás en GitHub Desktop (`compramosfacil.com@gmail.com`). Los repos que están bajo otras cuentas (ej. los que tengas con `jf.neggo@gmail.com`) se transfieren a esa Organization: entrás una vez con esa otra cuenta → Settings del repo → Transfer ownership → a la Organization nueva. Una vez transferidos, GitHub Desktop con tu única cuenta ve todo — no hay que volver a loguear con la otra cuenta nunca más.

**Supabase:** mismo concepto — Supabase tiene "Organizations" que pueden contener varios Projects, cada uno con su base aislada (no se mezclan). Creá una Organization con tu cuenta principal, y transferí los proyectos de las otras cuentas hacia ahí (Project Settings → General → Transfer project). Ojo con los planes pagos si alguno de esos proyectos tiene billing activo — revisar que la transferencia no rompa nada de facturación antes de hacerla.

**Seguridad de la cuenta que queda como dueña de todo:** activar 2FA sí o sí en GitHub y en Supabase (se vuelve la llave de todo), password único y fuerte con gestor de contraseñas, y si en algún momento sumás gente al equipo, invitarlos como miembros con rol limitado — nunca compartir la contraseña de esa cuenta principal.

## Plan de Supabase para 10 proyectos (verificado en supabase.com/pricing)

**Free ($0/mes) no sirve para esto:** el plan gratis tiene un límite duro de **2 proyectos activos por organización**, y cada proyecto se pausa solo si pasa 1 semana sin uso. Con 10 proyectos reales, la mayoría quedaría pausada todo el tiempo.

**Pro ($25/mes) es el que necesitás.** Así se calcula para 10 proyectos:
- El primer proyecto está incluido en los $25/mes base.
- Cada proyecto adicional arranca en **$10/mes** (el tamaño de cómputo más chico — podés subirlo por proyecto si alguno necesita más potencia).
- Cálculo mínimo para 10 proyectos: $25 + (9 × $10) = **$115/mes** aproximadamente, antes de cualquier consumo extra (más ancho de banda, más almacenamiento, o más usuarios activos de los incluidos por proyecto, que se cobran aparte por encima de esos $115).

Con Pro además destrabás: backups diarios (7 días de retención), soporte por email, y que los proyectos ya no se pausen solos por inactividad — importante si algunos de los 10 proyectos son de uso esporádico (como Puntos al principio).

Si en el futuro sumás gente al equipo y necesitás SSO o permisos más finos por persona, ahí existe un plan Team arriba del Pro — no lo cotizo ahora porque para vos solo, hoy, es Pro lo que corresponde.
