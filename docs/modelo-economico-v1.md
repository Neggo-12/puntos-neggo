# Modelo económico y regulatorio V1 — Puntos Neggo

Última actualización: 17 de agosto de 2026.

> Este documento registra el modelo V1 tal como lo definió Jhey (17 ago 2026), como referencia para desarrollo. Complementa — no reemplaza — `sistema-puntos-unificado.md`, que sigue siendo la fuente de verdad de arquitectura/esquema. Donde este documento define un número o regla de negocio que la spec dejaba abierta (sección 8), este documento gana porque es la decisión explícita.

## 1. Acumulación base

- `$800` de compra = **1 punto**.
- **1 punto = $10** de valor de referencia dentro del ecosistema Neggo.
- Recompensa base: **1,25%** ($10 ÷ $800).

## 2. Multiplicadores (no acumulables entre sí)

| Evento | Multiplicador | Equivalente |
|---|---|---|
| Compra normal | 1X | 1,25% |
| Cliente nuevo (primera compra en el comercio) | 2X | 2,5% |
| Campaña activa | 3X | 3,75% |
| Recuperación de cliente inactivo | 5X | 6,25% |

Regla explícita: si aplican varias condiciones a la vez (ej. cliente nuevo + campaña activa), **se aplica el multiplicador más alto de las condiciones que aplican, nunca la suma ni el producto**. Esto tiene que quedar como lógica determinística en `otorgar_puntos`, no como configuración libre que alguien pueda subir sin límite — el límite superior (5X) debe estar hardcodeado como techo, no como sugerencia.

**Presupuesto de campaña (pendiente de diseño técnico, no de decisión de negocio):** cada campaña con multiplicador debe poder definir un presupuesto máximo (ej. "$500.000") que corta la campaña automáticamente al agotarse. Falta definir el mecanismo exacto (¿se corta a mitad de una transacción si el presupuesto no alcanza para el multiplicador completo, o se corta antes de la transacción que lo agotaría?) — es una pregunta técnica para cuando se diseñe la tabla de campañas, no bloquea el ledger base.

## 3. Redención y valor

- Redención mínima: **200 puntos** (= $2.000 de valor).
- Puntos + dinero en la misma transacción: **sí**, soportado desde el diseño de `solicitar_canje`.
- **Regla anti-inflación de puntos:** los puntos generados por una compra se calculan solo sobre el monto pagado **en dinero real**, nunca sobre el monto cubierto con puntos. Ejemplo: servicio de $100.000, cliente paga $50.000 en puntos + $50.000 en efectivo → los puntos nuevos se calculan sobre $50.000, no sobre $100.000. Esto tiene que quedar como guarda explícita en la función que otorga puntos sobre una compra mixta, no como convención de frontend.

## 4. Retiro en efectivo (desbloqueable, NO activar sin resolver la sección 7)

Condiciones para desbloquear retiro, **las tres a la vez**:
1. **30%** de los puntos acumulados por el cliente deben haber sido usados dentro del ecosistema Neggo (redimidos en comercios, no transferidos — ver más abajo).
2. **Antigüedad mínima: 6 meses** desde el registro del cliente.
3. **Mínimo 5 transacciones** en comercios aliados.

Una vez desbloqueado: solo el **70%** de los puntos restantes es retirable (el 30% ya usado se descuenta de la base retirable, no es un 30% adicional). 1 punto retirado = $10, misma tasa que la redención interna.

## 5. Transferencia de puntos entre personas

- Permitida desde V1, pero con controles: usuario verificado, destinatario registrado, confirmación adicional, límite diario, límite mensual, trazabilidad completa, bloqueo de transferencias sospechosas.
- **Los puntos transferidos conservan la fecha de vencimiento original del lote** (no se renuevan al transferirse).
- **Los puntos recibidos por transferencia NO cuentan para el 30% de consumo interno que desbloquea el retiro en efectivo** — protección antifraude explícita contra "transferir para inflar el requisito".
- Límites exactos (monto diario/mensual) — **sin definir todavía**, queda para cuando se diseñe esta fase (no bloquea el ledger base).

## 6. Vencimiento de puntos

- **12 meses desde la fecha de emisión de cada lote**, no un vencimiento único por saldo total. El ledger tiene que manejar **lotes de puntos** (cada lote con su propia fecha de emisión/vencimiento), consumidos probablemente FIFO en redención.
- La app debe avisar antes de que un lote venza (ventana de aviso — ej. 15 días — sin definir el número exacto todavía).

## 7. Arquitectura financiera — separación en dos capas

**Esto es la decisión de arquitectura más importante del modelo y condiciona todo lo que se construye ahora:**

- **Capa Puntos (esto):** controla usuarios, saldo, reglas, campañas, transferencias, redenciones, vencimientos, ledger. No custodia dinero de terceros.
- **Capa financiera (proveedor regulado, todavía sin elegir):** custodia/recauda/liquida dinero real. Candidatos evaluados por Jhey: Wompi (primera opción para MVP, API de pagos a terceros + dispersión), SEDPE/BaaS regulado (objetivo para la arquitectura definitiva), Bold (alternativa, falta validar si soporta fondos de terceros).

**Consecuencia directa para el diseño técnico ahora:** el módulo financiero se construye desde ya como una interfaz `PaymentProvider` (adapter pattern) — nunca amarrado a un proveedor específico — para poder conectar Wompi/SEDPE/BaaS después sin rediseñar el ledger. El ledger de puntos (ganancia, transferencia, vencimiento, lotes, reversos, fraude, auditoría) es requisito obligatorio desde V1. El **retiro en efectivo real** (mover plata de una cuenta a la del cliente) se deja detrás de esa interfaz y **no se activa** hasta:
1. Elegir el proveedor financiero regulado.
2. Consulta jurídica/regulatoria formal con abogado fintech colombiano sobre captación de recursos de terceros (Ley 1735, régimen SEDPE, vigilancia de la Superfinanciera).
3. Resolver el saldo prefondeado por comercio (el comercio no puede emitir puntos "a crédito" — necesita saldo disponible que se descuenta al emitir, con aviso de recarga y bloqueo de emisión en $0).

**No confundir con el punto ciego de identidad ya documentado en la skill `puntos-neggo-engineering`** (registro de clientes en `neggo-12` sin verificación externa real) — son dos bloqueantes distintos para activar retiro real: uno es regulatorio/financiero (esta sección), el otro es de verificación de identidad del cliente. Los dos hay que resolverlos antes de mover plata real a un cliente, no alcanza con resolver uno solo.

## 8. Ingresos de Neggo en este modelo

- Membresía: $30.000/comercio/mes — financia crecimiento/plataforma, **no** financia la emisión de puntos.
- Comisión de liquidación propuesta: **5%** sobre el valor redimido cuando el punto se gana en un comercio y se usa en otro (hipótesis de diseño, no un dato de mercado confirmado).
- Quién financia la emisión: el comercio que genera la compra, vía saldo prefondeado (ver sección 7).

## 9. Fraude y reversos (requisito de V1, no opcional)

Los puntos solo se generan sobre una transacción validada, nunca porque alguien "diga que vendió". Reglas obligatorias desde el diseño de `otorgar_puntos`/`solicitar_canje`:
- Cancelación de compra → reversión de puntos.
- Devolución → reversión.
- Fraude detectado → congelamiento de cuenta.
- Cuenta sospechosa → bloqueo de redención (no necesariamente de acumulación).
- Transacción duplicada → rechazo (idempotencia en `otorgar_puntos`, mismo criterio que ya se usa en `emitir_puntos_por_compra` de `neggo-12`).

## 10. Ledger — nivel de detalle exigido

Cada movimiento queda registrado con, como mínimo: id de usuario, comercio, transacción de origen, valor de compra, puntos base, multiplicador aplicado, puntos otorgados, saldo anterior, saldo nuevo, fecha, estado, y — cuando aplica — comercio receptor de la redención, comisión de Neggo, monto liquidado al comercio, puntos usados. Esto es una razón directa por la que el esquema necesita lotes y un historial append-only, no solo una columna `saldo` en `clientes_puntos`.

## 11. Decisiones que siguen sin cerrar (no inventar, preguntar cuando se llegue a esa fase)

- Ventana exacta de aviso de vencimiento (¿15 días? ¿30?).
- Límites diario/mensual de transferencia persona a persona.
- Mecanismo exacto de corte de presupuesto de campaña a mitad de transacción.
- Proveedor financiero final (Wompi / SEDPE-BaaS / Bold) — depende de gestión externa de Jhey, no de diseño técnico.
- Si el `codigo_publico` del cliente se muestra en el perfil de Neggo/Talleres o solo lo ve el comercio al canjear (ya estaba abierta en `sistema-puntos-unificado.md` sección 8, sigue sin resolver).
