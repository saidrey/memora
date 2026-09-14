# Memora — Estado del proyecto (punto de retomada)

Documento de arranque para retomar el trabajo en una sesión nueva. La fuente de verdad son las specs y documentos de esta carpeta; el historial de chat NO es necesario.

## Roles
- **Founder/PO:** el usuario. Decide producto y reglas de negocio.
- **Kiro (Tech Lead):** especifica, valida contra criterios, no inventa reglas de producto.
- **Claude:** implementa según specs y reporta.
- Ciclo: Kiro escribe spec → PO aprueba → Claude implementa → Kiro valida (PASS / PASS WITH NOTES / CHANGES REQUIRED).

## Documentos clave (leer primero)
- **`specs/CONTEXTO-KIRO.md` — MAPA DE ARRANQUE EN FRÍO. Léelo primero: es el único documento necesario para arrancar; los demás se consultan bajo demanda vía sus punteros.**
- `specs/producto-mvp.md` — fuente de verdad funcional (decisiones D1–D16, principios, modelo N:M).
- `specs/backlog-mvp.md` — backlog maestro por módulos (M0–M9) con estado.
- `specs/README.md` — convenciones, decisiones técnicas fijadas, pendientes.

## Metodología con agentes (persistencia entre sesiones)
Para no repetir el arranque en frío cada sesión, el conocimiento se destila en `specs/CONTEXTO-KIRO.md` (mapa+punteros, no resumen sustituto: la fuente de verdad de producto sigue siendo `producto-mvp.md`). Dos agentes custom de Kiro (en `.kiro/agents/`) arrancan leyendo ese mapa:
- **`spec-writer`** — Tech Lead que escribe/refina specs en `specs/`. No inventa producto; trae al PO resumen ejecutivo + decisiones abiertas (opciones+recomendación+impacto). Solo escribe en `specs/`, nunca código.
- **`spec-validator`** — valida lo que implementa Claude con protocolo quirúrgico (build+tests+grep dirigido) y emite PASS / PASS WITH NOTES / CHANGES REQUIRED. Solo lectura de código.
Se seleccionan desde el agent picker del panel de chat. Claude sigue usando Engram (memoria propia de Claude Code); Kiro se apoya en los archivos del repo.

## Stack y reglas técnicas
- Monorepo: `memora-app` (Flutter), `memora-web` (Next.js), `memora-backend` (NestJS 10 + TS).
- Clientes solo hablan con la API del backend. Excepción: subida directa de bytes a Google Drive del usuario (Opción A: el backend nunca maneja bytes).
- Identidad: JWT propio. DB: Postgres (Neon) cuando toque; **por ahora mocks en memoria detrás de interfaces**.
- Aislamiento de entorno: cada subproyecto Node tiene su `.npmrc` (registro público). NO usar `npm -g`, NO cambiar config global, NO tocar `.npmrc`, NO cambiar versión de NestJS/Node.
- Ejecutar OpenSpec/otras herramientas: no aplica (OpenSpec fue removido; usamos specs numeradas en `specs/`).

## Estado de implementación (backend primero, luego app, luego web)

Completado y validado PASS:
- Fundación monorepo + contrato API (`/api/v1`, errores uniformes, correlación, `/health`).
- Auth Google backend (login híbrido, JWT sesión, broker `drive-token` scope `drive.file`). Login real probado en Android físico.
- App: fundación + login Google (probado en dispositivo real).
- Web: fundación (en pausa de desarrollo, sigue siendo parte del MVP).
- **M2** Álbumes backend (`spec03`) — crear/listar/abrir/renombrar/eliminar, N:M foto↔álbum.
- **M3 backend** Fotos (`spec04`) — registro por referencia, biblioteca, asociar/quitar N:M, borrar sin tocar Drive.

Pendiente (orden de backend acordado):
1. **M4 — Colaboradores** (siguiente): invitación por enlace (D12), aceptar, permisos Owner/Collaborator (D1), colaborador aporta fotos a su propio Drive, administrar/quitar colaboradores, abandonar álbum (D5, sus fotos permanecen).
2. **M5 — Adoptar** ("Guardar en mi biblioteca", D6): validar viabilidad de copia cross-Drive con `drive.file` en su spec (riesgo técnico; puede requerir que el backend intermedie una copia solicitada explícitamente).
3. **M6 — Disponibilidad** (verificación perezosa, D9; el campo `availability` ya existe en `Photo`).
4. **M7 — Compartir/visor** (enlace estable, acceso sin login D2) + resolución.
5. **M8 — NFC/QR** (asociar a álbum ya creado D14, URL estable, resolución).
6. **A1.5 — Refresh de sesión** (deuda: backend+app).
Después: app (M3 app: seleccionar/optimizar/subir; UI de álbumes; etc.) y web.

## Convenciones de validación (para optimizar tokens)
- Validación quirúrgica: correr `npm run build` + tests + grep dirigido a los criterios críticos; lectura profunda de código solo si un test falla o la spec es sensible (auth, borrados, adopción).
- Backend corre en puerto 3000; matar procesos colgados al terminar (`lsof -ti:3000`).
- Tests del backend necesitan env: `JWT_SESSION_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET` (valores dummy sirven para tests).

## Deuda técnica conocida (no bloqueante)
- Flake residual de e2e (supertest + apps Nest efímeras); `auth.e2e` sin migrar a beforeAll a propósito (muta sesión).
- `SessionRegistry` es provider en memoria; elevar a interfaz antes de desplegar.
- Cifrado real del refresh token en `TokenStore` (hoy frontera documentada).
