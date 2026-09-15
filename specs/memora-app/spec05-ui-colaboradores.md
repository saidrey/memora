# spec05 — UI de colaboradores (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** APROBADA — lista para implementar (decisiones tomadas por Kiro con recomendación, informadas al PO; 2026-09-14). Pendiente de implementación por Claude y validación por el PO en dispositivo.
**Backlog:** M4 en app — UI de colaboradores. FASE 2 (app), ítem C del ROADMAP. Consume el backend de M4 (`memora-backend/spec05`, PASS).

## Objetivo
Implementar en `memora-app` la interfaz de **colaboradores** de un álbum: que el owner invite por enlace (D12), vea y quite colaboradores, revoque invitaciones (D13); que el invitado abra el enlace, inicie sesión y acepte (pasando a Collaborator); y que un colaborador pueda **abandonar** el álbum (D5).

## Contexto y decisiones que aplican
Fuente de verdad de producto: `specs/producto-mvp.md`. Aplican:
- **D1 — Roles.** Owner administra álbum + colaboradores; Collaborator ve todo y aporta, **no** administra. La UI de administración de colaboradores es **owner-only**.
- **D12 — Invitación solo por enlace** (sin código) en el MVP.
- **D13 — Invitaciones expiran y son revocables por el owner.**
- **D5 — Abandonar.** Un colaborador puede dejar de aportar; sus fotos históricas permanecen mientras estén disponibles en su Drive.

## Contrato real del backend (M4 — `memora-backend/spec05`, PASS)
- `POST /api/v1/albums/:albumId/invitations` (owner-only) → crea una invitación de un solo uso; responde `{ token, url, expiresAt, ... }` (URL construida sobre env de invitaciones, tipo `APP_INVITE_BASE_URL`).
- `GET /api/v1/albums/:albumId/collaborators` (owner o miembro) → lista de colaboradores (y estado de invitaciones pendientes según lo expuesto por el backend).
- `POST /api/v1/invitations/:token/accept` (autenticado) → el invitado acepta y pasa a Collaborator (un solo uso; expirada/usada/inválida → error uniforme).
- `DELETE /api/v1/albums/:albumId/invitations/:invitationId` (owner-only) → revoca una invitación pendiente (D13).
- `DELETE /api/v1/albums/:albumId/collaborators/:userId` (owner-only) → quita a un colaborador.
- `DELETE /api/v1/albums/:albumId/collaborators/me` (colaborador) → abandonar el álbum (D5).

> Si algún nombre exacto de campo/endpoint difiere, prevalece lo implementado en `memora-backend/spec05` (PASS); Claude debe alinearse a ese contrato real al integrar.

## Alcance (UI app)
- **Owner — invitar:** desde el detalle del álbum, generar una invitación y **compartir el enlace** con el share sheet del sistema (D12); mostrar `expiresAt`.
- **Owner — administrar:** ver la lista de colaboradores del álbum; quitar un colaborador (con confirmación); ver invitaciones pendientes y revocarlas (D13).
- **Invitado — aceptar:** abrir el enlace de invitación → si no hay sesión, login (spec02) → aceptar → quedar como Collaborator del álbum y verlo en su lista (spec04).
- **Colaborador — abandonar:** acción "Abandonar álbum" (con confirmación que aclare que sus fotos históricas permanecen mientras estén disponibles, D5).
- Extiende `AlbumsApi`/estado (o crea `CollaboratorsApi` + controlador `ChangeNotifier`) sobre `ApiClient`.

## Fuera de alcance
- Roles configurables (no existen, D1). Compartir/visor y NFC/QR (ítem F). Diseño visual final.
- Notificaciones push de invitación (no hay en el MVP).

## Comportamiento esperado (normativo)
- La app SHALL permitir al **owner** crear una invitación (`POST .../invitations`) y compartir su `url` mediante el share sheet del sistema; SHALL mostrar la expiración.
- La app SHALL mostrar la **lista de colaboradores** del álbum (owner). SHALL permitir al owner **quitar** un colaborador (`DELETE .../collaborators/:userId`) con confirmación, y **revocar** invitaciones pendientes (`DELETE .../invitations/:id`).
- Las acciones de administración de colaboradores SHALL ser **owner-only**: para un collaborator, ocultas o deshabilitadas (D1).
- Al abrir un **enlace de invitación**, la app SHALL resolver el `token`: si no hay sesión, iniciar login (spec02) y, tras autenticarse, llamar `POST /invitations/:token/accept`; con éxito, el usuario SHALL quedar como Collaborator y ver el álbum en su lista.
- Una invitación expirada/usada/inválida SHALL mostrar un mensaje claro, sin filtrar detalles internos.
- La app SHALL permitir a un **colaborador abandonar** el álbum (`DELETE .../collaborators/me`) con confirmación que aclare que sus fotos históricas permanecen (D5).
- Toda llamada al backend por `ApiClient` (Bearer adjunto); ningún token en logs; errores con mensajes claros.

## Decisiones (tomadas por Kiro, informadas al PO)
- **Deep link de invitación:** en este corte, la app soporta abrir el enlace por **pegar/introducir el token o vía deep link básico** si la plataforma ya lo permite; la configuración completa de universal/app links se difiere (no bloquea el flujo: aceptar funciona con el token). *Recomendación: no montar aún el esquema completo de deep links nativos; validar el flujo de aceptar primero.*
- **Compartir el enlace:** usar el **share sheet del sistema** (`share_plus` o equivalente), en vez de solo copiar al portapapeles. Mejor UX.
- **Vista de colaboradores:** superficie mínima (nombre/email según lo exponga el backend); sin PII extra ni acciones que el backend no soporte.

## Checklist de implementación
- [ ] `CollaboratorsApi` (o extensión de `AlbumsApi`) sobre `ApiClient`: crear invitación, listar colaboradores, aceptar por token, revocar invitación, quitar colaborador, abandonar.
- [ ] Estado con `ChangeNotifier`; refresco de la lista tras invitar/quitar/revocar/abandonar.
- [ ] UI owner en el detalle del álbum: botón "Invitar" → genera y comparte enlace (share sheet) + muestra expiración; lista de colaboradores con "quitar"; invitaciones pendientes con "revocar". Todo owner-only.
- [ ] Flujo de aceptación: resolver token → login si hace falta → `accept` → feedback y navegación al álbum.
- [ ] Acción "Abandonar álbum" para colaborador, con confirmación (D5).
- [ ] Manejo de errores (invitación inválida/expirada/usada; 404 ajeno; sin sesión) con mensajes claros; sin tokens en logs.
- [ ] `flutter analyze` pasa y compila.

## Criterios de validación (los valida el PO en el dispositivo)
- El owner genera un enlace y lo comparte; el invitado lo abre, inicia sesión y queda como colaborador viendo el álbum.
- El owner ve, quita colaboradores y revoca invitaciones; un colaborador no ve esas acciones.
- Un colaborador puede abandonar el álbum; sus fotos históricas siguen visibles mientras estén disponibles.
- Invitación expirada/usada muestra mensaje claro. Ningún token en logs.
- `flutter analyze` pasa y compila.

## Dependencias
- `memora-app/spec02-login-google.md` (sesión, necesaria para aceptar) — PASS.
- `memora-app/spec04-ui-albumes.md` (detalle de álbum donde viven estas acciones) — en implementación.
- `memora-backend/spec05-colaboradores.md` (endpoints de invitaciones/colaboradores) — PASS.
