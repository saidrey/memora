# Cómo trabajar en Memora (guía paso a paso para el PO)

Recordatorio del flujo por cada spec. Tú (PO) orquestas; los agentes hacen el trabajo especializado.

> **Importante:** los agentes de Kiro (`spec-writer`, `spec-validator`) **los eliges tú** en el *agent picker* — el nombre del agente en la barra inferior del panel de chat. Kiro no cambia de agente solo; sí puede llamar sub-agentes internamente, pero el flujo de roles con contexto/permisos aislados lo activas tú cambiando de agente.

---

## Los 3 agentes

| Agente | Para qué | Dónde vive |
|--------|----------|-----------|
| **Default (Kiro)** | Conversación general, orquestación, tareas sueltas. | (integrado) |
| **spec-writer** | Escribe/refina specs en `specs/`. No toca código. | `.kiro/agents/spec-writer.md` |
| **spec-validator** | Valida lo que implementó Claude (build+tests+grep). Solo lee código. | `.kiro/agents/spec-validator.md` |

Claude (implementador) vive en **Claude Code**, aparte, con su memoria Engram.

---

## Flujo por cada nueva spec (ej. M5, M6, ...)

### Paso 1 — Especificar (agente `spec-writer`)
1. En el agent picker, cambia a **spec-writer**.
2. **No necesitas recordar en qué spec vas.** Solo dile: **"Continuemos con la siguiente spec."** Él lee `specs/ROADMAP.md`, ubica el siguiente módulo pendiente (respetando el orden backend → app → web) y te confirma cuál va a especificar antes de empezar. (Si quieres uno específico, también puedes nombrarlo.)
3. Él arranca leyendo `specs/CONTEXTO-KIRO.md` + `specs/ROADMAP.md`, escribe el borrador de la spec en `specs/<capa>/specNN-*.md` y te devuelve:
   - **Resumen ejecutivo** (qué construye, qué respeta, qué deja fuera).
   - **Decisiones de producto abiertas**, cada una con **opciones + recomendación + impacto**.

### Paso 2 — Aprobar decisiones (tú)
4. Respondes cada decisión abierta (puedes decir *"todas tus recomendaciones"* y ajustar las que quieras).
5. El spec-writer **congela** la spec (estado → APROBADA) y te entrega el **prompt para Claude**.

### Paso 3 — Implementar (Claude, en Claude Code)
6. Copias el prompt a Claude. Claude implementa dentro del subproyecto, marca el checklist de la spec y, al terminar, te da su **reporte de cierre** (ver formato abajo).

**Reporte de cierre que Claude debe darte** (ya incluido en el prompt de Claude):
- Qué spec implementó (número + nombre).
- Resultado de `npm run build`, `npm test`, `npm run test:e2e` (conteos).
- Checklist de la spec marcado.
- Desviaciones/dudas, si las hubo.

Con eso ya sabes que está listo para validar. No tienes que revisar el código tú.

### Paso 4 — Validar (agente `spec-validator`)
7. En el agent picker cambia a **spec-validator**.
8. Dile una de estas dos (ambas funcionan; el agente lee el ROADMAP y sabe cuál está 🟡 EN CURSO):
   - *"Valida la spec de M4 (spec05-colaboradores)."* — si quieres nombrarla.
   - *"Claude terminó, valida lo que está pendiente de validación."* — si no quieres recordar el número.
9. Corre build + tests + grep dirigido y emite veredicto:
   - **PASS** → marca ✅ en el ROADMAP y pasas al siguiente módulo (paso 1).
   - **PASS WITH NOTES** → aceptable, con observaciones anotadas.
   - **CHANGES REQUIRED** → te dice exactamente qué falta; se lo pasas de vuelta a Claude (paso 3) y repites.

### Paso 5 — Cerrar
10. Con PASS, se actualizan `ESTADO.md`, `backlog-mvp.md` y el índice de `CONTEXTO-KIRO.md`. Siguiente módulo → paso 1.

---

## ¿Dónde voy? ¿Y cómo paso de capa? (no lo tienes que recordar tú)

La secuencia vive en **`specs/ROADMAP.md`**. Ahí está el orden por fases y qué está hecho:

- **FASE 1 — Backend** (en curso): M4 → M5 → M6 → M7 → M8 → A1.5.
- **FASE 2 — App** (arranca cuando tú lo autorices).
- **FASE 3 — Web** (en pausa hasta tu aviso).

**Regla de capas:** se completa **todo el backend primero**. Los agentes NO arrancan la parte de app de un módulo hasta que la FASE 1 esté completa y tú digas "pasamos a app". No tienes que especificar "solo backend" cada vez: mientras la fase activa sea backend, "la siguiente spec" siempre será backend. Cuando quieras cambiar de fase, dilo explícitamente: **"terminamos backend, pasemos a la app"**.

- Para retomar sin recordar nada: cambia a `spec-writer` y di *"continuemos con la siguiente spec"*.
- Para saber el estado de un vistazo: abre `specs/ROADMAP.md`.

---

## Reparto de validación por capa (acuerdo con el PO)

- **Backend:** el `spec-validator` valida completo (build + unit + e2e + grep dirigido) en Kiro.
- **App (Flutter) y Web:** el `spec-validator` verifica lo que pueda de forma estática (que el código cumple la spec, análisis, tests automatizados si el toolchain está disponible) y reporta qué no pudo ejecutar. **Las pruebas de usuario en app y web las hace el PO** en su entorno (dispositivo real / navegador). El veredicto del agente en esas capas es sobre código y criterios, no sustituye la prueba manual del PO.

## Reglas que los agentes ya conocen (no hace falta repetirlas)

- No inventar reglas de producto: si falta una decisión, se pregunta con opciones + recomendación + impacto. Fuente de verdad de producto: `specs/producto-mvp.md` (D1–D16).
- Entorno: NestJS 10 / Node 20; no `npm -g`; no tocar `.npmrc`.
- Validación quirúrgica: build + tests + grep; leer código completo solo si algo falla o la spec es sensible.
- Arranque en frío: siempre por `specs/CONTEXTO-KIRO.md` (mapa+punteros; no reemplaza las fuentes).

---

## Plantilla de prompt para Claude (reutilizable en cada spec)

Copia esto a Claude Code cambiando el nombre de la spec:

> Proyecto Memora, monorepo. Actúa como implementador. Implementa **exactamente** la spec `specs/<capa>/<specNN-nombre>.md`, que ya está APROBADA.
>
> Trabaja **solo dentro del subproyecto de esa spec**. No toques `specs/` ni otros subproyectos. Respeta el entorno: NestJS 10 / Node 20, no `npm -g`, no tocar `.npmrc`. Sigue los patrones existentes del backend (repos en memoria + token `Symbol`; guard de sesión + `@CurrentUser`; patrón `requireOwned` → 404; errores uniformes `{ code, message, requestId }`; validación manual sin class-validator).
>
> Marca el checklist de la spec conforme avances. Guarda en Engram un resumen de lo implementado.
>
> **Al terminar, dame un reporte de cierre con:** (1) spec implementada; (2) resultado de `npm run build`, `npm test`, `npm run test:e2e` con conteos; (3) checklist marcado; (4) desviaciones o dudas. No des por terminado nada que no compile o cuyos tests no pasen.

---

## Atajos útiles

- **"¿Dónde estoy? / ¿qué sigue?"** → cambia a `spec-writer` y di *"continuemos con la siguiente spec"*; o abre `specs/ROADMAP.md`.
- **"¿Cuál es el estado?"** → `specs/ROADMAP.md` (secuencia) y `specs/ESTADO.md` (detalle).
- **"¿Qué falta del MVP?"** → `specs/backlog-mvp.md`.
- **Validar lo de Claude** → cambia a `spec-validator` y di *"valida lo que está pendiente de validación"*.
