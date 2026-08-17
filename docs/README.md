# Puntos Neggo

Sistema de fidelización/puntos de Grupo Neggo. Tercer proyecto, separado de Neggo y de Talleres — Supabase propio, repo propio, app propia. Fuente de verdad del saldo de puntos de cualquier cliente, sin importar en qué producto de Neggo lo ganó o lo quiere gastar.

## Documentos clave

- `sistema-puntos-unificado.md` — especificación de arquitectura, fuente de verdad del esquema y del flujo de canje.
- `docs/modelo-economico-v1.md` — modelo económico y regulatorio V1 (tasas, multiplicadores, condiciones de retiro en efectivo).
- `docs/cronograma-pendientes.md` — qué falta y en qué orden.
- `docs/roadmap-pendientes.md` — registro cronológico, sesión por sesión, de lo hecho y lo decidido.
- `docs/metodologia-trabajo.md` — cómo se trabaja este repo (protocolo de la skill `puntos-neggo-engineering`, documentación, Claude Code vs. Cowork).
- `PROMPT-MAESTRO-INICIO.md` — prompt de arranque para una sesión nueva de Claude/Claude Code sobre este repo.

## Estado

17 ago 2026 — Supabase (`puntos-neggo`, `ckxoypzsmvxhqlvlwnib`) activo, sin tablas todavía. Modelo económico V1 y documentación base ya definidos. Próximo paso: migración base del ledger (`docs/cronograma-pendientes.md`, Fase 1).
