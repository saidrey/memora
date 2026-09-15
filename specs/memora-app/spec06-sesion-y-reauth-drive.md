# spec06 — Refresh de sesión y re-autorización de Drive (app Flutter)

**Ámbito:** memora-app
**Estado de validación:** APROBADA — lista para implementar (decisiones tomadas por Kiro con recomendación, informadas al PO; 2026-09-14). Pendiente de implementación por Claude y validación por el PO en dispositivo.
**Backlog:** A1.5 (parte app) + A1.6. FASE 2 (app), ítem E del ROADMAP. Consume `memora-backend/spec02` (PASS).

## Objetivo
Que la app **renueve automáticamente el JWT de sesión** cuando el access token caduca (A1.5), y que **detecte y resuelva la re-autorización de Drive** cuando Google revocó el permiso, sin forzar logout (A1.6 / D10).

## Contexto y decisiones que aplican
- `memora-backend/spec02` (PASS) expone `POST /api/v1/auth/refresh` (renueva el access de sesión con el refresh de sesión) y `POST /api/v1/auth/drive-token` (devuelve access efímero de Drive; sin refresh de Google válido → **401 `DRIVE_REAUTHORIZATION_REQUIRED`**).
- `memora-app/spec02` (PASS) guarda los JWT de sesión en almacenamiento seguro y adjunta el Bearer en `ApiClient`. Dejó **pendiente el refresco automático** y el uso del `drive-token`.
- **D10 — Autorización de Drive revocada:** se pide re-autorizar; **no** hay logout forzado, no se pierde la cuenta.

## Alcance (app)
- **Refresh automático de sesión (A1.5):** cuando una llamada autenticada por `ApiClient` responde **401** por access de sesión expirado, la app SHALL intentar `POST /auth/refresh` una vez, y **reintentar** la petición original con el nuevo access; si el refresh falla, cerrar sesión limpiamente.
- **Re-autorización de Drive (A1.6):** cuando `POST /auth/drive-token` responde **401 `DRIVE_REAUTHORIZATION_REQUIRED`** (o cualquier operación de Drive lo detecta), la app SHALL ofrecer **reconectar Google Drive** (re-ejecutar la autorización de servidor de Google con scope `drive.file`, reenviando el `serverAuthCode` al backend), **sin** cerrar la sesión de la app (D10). Tras reconectar, reintentar la operación pendiente.

## Fuera de alcance
- Cambiar el contrato del backend (ya existe). Cifrado del refresh token (frontera backend). Diseño visual final.

## Comportamiento esperado (normativo)
### Refresh de sesión (A1.5)
- Ante un **401 por sesión expirada** en `ApiClient`, la app SHALL llamar `POST /auth/refresh` con el refresh de sesión almacenado, **una sola vez**, y reintentar la petición original con el nuevo access.
- Refreshes concurrentes SHALL coalescerse (un solo refresh en vuelo; las demás peticiones esperan su resultado).
- Si el refresh **falla** (refresh inválido/revocado, p. ej. tras logout), la app SHALL borrar los tokens y pasar a estado no autenticado con un mensaje claro.
- El nuevo access SHALL guardarse en almacenamiento seguro; ningún token SHALL escribirse en logs.
### Re-autorización de Drive (A1.6 / D10)
- Ante **401 `DRIVE_REAUTHORIZATION_REQUIRED`**, la app SHALL mostrar una acción clara de **"Reconectar Google Drive"**, sin cerrar la sesión de la app.
- Al reconectar, la app SHALL re-ejecutar la autorización de servidor de Google (scope `drive.file` + identidad) y enviar el nuevo `serverAuthCode` al backend por el mismo canal que el login (spec02), para que el backend regenere el refresh token de Google.
- Tras reconectar con éxito, la app SHALL reintentar la operación que disparó el error (p. ej. la subida o la carga de miniaturas).
- Si el usuario cancela, la app SHALL permanecer autenticada (sesión intacta) y la operación de Drive queda pendiente, con mensaje claro.

## Decisiones (tomadas por Kiro, informadas al PO)
- **Dónde vive la lógica de refresh:** **centralizada en `ApiClient`** (interceptor: al recibir 401 de sesión, refresca y reintenta una vez), en vez de repartirla por cada `*Api`. Menos duplicación y comportamiento consistente.
- **Distinguir 401 de sesión vs 401 de Drive:** el de Drive viene con `code == 'DRIVE_REAUTHORIZATION_REQUIRED'` (de `/auth/drive-token`); cualquier otro 401 en endpoints de sesión se trata como sesión expirada. Se usa el `code` de `ApiException`, no solo el status.
- **Reintento único:** un solo intento de refresh por petición (evita bucles); si el reintento también da 401, se cierra sesión.
- **Reconexión de Drive:** reutiliza el `GoogleAuthService` de spec02 (mismo `authorizeServer` + envío de `serverAuthCode`), no un flujo nuevo.

## Checklist de implementación
- [ ] Interceptor de refresh en `ApiClient`: detectar 401 de sesión, llamar `/auth/refresh` una vez, coalescer concurrentes, reintentar la original, y limpiar sesión si el refresh falla.
- [ ] Persistir el nuevo access en almacenamiento seguro; sin tokens en logs.
- [ ] Detección de `DRIVE_REAUTHORIZATION_REQUIRED` (por `code`) y acción "Reconectar Google Drive" reutilizando `GoogleAuthService`.
- [ ] Reintento de la operación de Drive pendiente tras reconectar; cancelación deja la sesión intacta.
- [ ] Estado/feedback en la UI (reconectando, éxito, cancelado, error) con mensajes claros.
- [ ] `flutter analyze` pasa y compila.

## Criterios de validación (los valida el PO en el dispositivo)
- Con la sesión expirada, una acción autenticada se recupera sola (refresh transparente) sin re-login.
- Si el refresh ya no es válido (tras logout en otro lado), la app pasa a no autenticada limpiamente.
- Al revocar el permiso de Drive en la cuenta Google, la app ofrece reconectar sin cerrar sesión; tras reconectar, la operación (p. ej. subir/miniaturas) vuelve a funcionar.
- Ningún token aparece en logs.
- `flutter analyze` pasa y compila.

## Dependencias
- `memora-app/spec01` (`ApiClient`) y `spec02` (sesión, `GoogleAuthService`, almacenamiento seguro) — PASS.
- `memora-backend/spec02` (`/auth/refresh`, `/auth/drive-token`, `DRIVE_REAUTHORIZATION_REQUIRED`) — PASS.
- Se relaciona con spec03 (subida) y spec04 (miniaturas), que disparan la re-auth de Drive.
