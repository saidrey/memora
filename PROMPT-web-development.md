# Prompt para agente de IA — Desarrollo de memora-web

Copiá el bloque de abajo (desde "## Tu misión" hasta el final) y pásalo al agente que va a construir la web. Está pensado para darle contexto suficiente sin atarle las manos: **él toma las decisiones técnicas de frontend y las implementa**. No arranca de cero — la fundación de la web ya existe.

---

## Tu misión

Sos un ingeniero frontend senior. Vas a construir **`memora-web`**, la plataforma web de Memora, en el monorepo ubicado en `memora/`. Ya existe una base andamiada (Next.js App Router + TypeScript + Tailwind, con capa de API y health check funcionando). Tu trabajo es **llevarla desde esa fundación hasta una web con las funcionalidades del producto**, tomando vos las decisiones técnicas de frontend (estructura de rutas, gestión de estado, componentes, estilos, data fetching, etc.) que no estén ya fijadas aquí.

Tenés dos referencias vivas y completas para saber QUÉ construir y CÓMO se comporta el sistema:
- **`memora-backend/`** — la API que vas a consumir (es la única puerta de entrada a la lógica).
- **`memora-app/`** — la app Flutter, que ya implementa el mismo producto contra el mismo backend. Es tu mejor referencia de flujos, features y reglas de negocio: **replicá su comportamiento en web**, adaptándolo a patrones web.

## Qué es Memora

Plataforma para crear y compartir **bibliotecas/álbumes digitales de fotos y recuerdos**. El usuario inicia sesión con Google, crea álbumes, sube fotos (que viven en **su propio Google Drive**, no en Memora), colabora con otros en álbumes compartidos, y comparte álbumes por enlace público, QR o etiquetas NFC.

Principios de producto clave:
- **Memora no almacena los bytes de las fotos.** Viven en el Google Drive del usuario. El backend guarda solo referencias (`storageRef`) y metadatos.
- Los clientes (app y web) **solo hablan con el backend** vía su API HTTP. La única excepción: para transferir bytes de fotos, el cliente contacta a Google Drive directo, con autorización efímera que emite el backend.
- Sin dependencias directas a proveedores de backend (Firebase/Supabase/etc.) en el cliente.

## Reglas de arquitectura (fijas, respetalas)

- La web consume **exclusivamente** la API del backend bajo el prefijo `/api/v1`. Nada de SDKs de proveedores de backend.
- En dev: backend en `http://localhost:3000/api/v1`, web en el puerto **3001** (`PORT=3001 npm run dev`). Base URL configurable por env (`NEXT_PUBLIC_API_BASE_URL`, ya documentada en `.env.example`).
- **Toda** llamada al backend pasa por la capa de API (`src/lib/api/*`) — nada de `fetch` sueltos dispersos. Extendé esa capa, no la evadas.
- Errores del backend vienen en formato uniforme `{ code, message, requestId }`. Manejá los `code` (ver abajo) para dar buena UX.
- No inicialices git dentro de `memora-web/` (el git está en la raíz del monorepo). No toques `.npmrc` ni uses `npm install -g`.

## De dónde partís (la web NO arranca de cero)

`memora-web/` ya tiene:
- Next.js (App Router) + TypeScript + Tailwind, dependencias instaladas.
- `src/lib/api/` con: `config.ts` (base URL), `client.ts` (cliente HTTP reutilizable), `errors.ts` (manejo del formato uniforme), `health.ts` (consulta `/api/v1/health`).
- `src/app/` con layout y una página mínima que muestra el estado de conectividad con el backend.
- `.env.example` con `NEXT_PUBLIC_API_BASE_URL`.

Leé estos archivos antes de empezar: reutilizá y extendé el cliente HTTP existente para todas las nuevas llamadas.

## Qué construir (funcionalidades del producto)

Tomá `memora-app` como especificación viva de comportamiento. Las features del MVP son:

1. **Autenticación con Google.** Login con Google en web (flujo que obtiene un `serverAuthCode` de Google con acceso offline y scope `drive.file`), enviarlo al backend, recibir la sesión (JWT propio de Memora: access + refresh) y persistirla. Manejar refresh automático del access token y logout. En la app esto vive en `lib/auth/` — mirá el flujo ahí.
2. **Álbumes / biblioteca.** Listar álbumes (propios + donde colaboro, con rol), crear, abrir y ver fotos (miniaturas desde Drive), renombrar, cambiar visibilidad y eliminar (solo owner). Agregar/quitar fotos de álbumes. Referencia en la app: `lib/albums/`.
3. **Fotos.** Ver fotos a full resolution desde Drive, con estado "no disponible" si el archivo ya no está. **La subida de fotos desde web es opcional/decisión tuya** (implica el flujo de subida directa a Drive con token efímero del backend — más complejo en web); prioridad es la **visualización**. Referencia: `lib/photos/` y `lib/albums/screens/photo_viewer_screen.dart`.
4. **Colaboradores.** El owner invita por enlace, administra y quita colaboradores; el invitado acepta la invitación; el colaborador puede abandonar. Referencia: `lib/albums/collaborators_api.dart` y `lib/albums/screens/accept_invitation_screen.dart`.
5. **Compartir / visor público.** Página de **visor público de solo lectura sin login** (accesible por un enlace estable / token opaco), y resolución de QR/NFC que redirige a ese visor. Esta es una de las piezas más valiosas en web (la web es el destino natural de un enlace compartido). Referencia de compartir en la app: `lib/albums/sharing_api.dart`.

> No tenés que replicar features propias de móvil (programar etiquetas NFC físicas es solo de la app). Sí conviene que la web sea el buen destino de esos enlaces/QR.

## El contrato de la API (fuente de verdad: `memora-backend/README.md`)

**Leé `memora-backend/README.md`** — documenta cada endpoint, sus reglas y sus errores. Resumen de lo que vas a consumir:

**Auth** (`/api/v1/auth`):
- `POST /auth/google { serverAuthCode }` → `{ sessionAccessToken, sessionRefreshToken, user }`
- `POST /auth/refresh { sessionRefreshToken }` → nuevo `sessionAccessToken`
- `POST /auth/logout` (Bearer) → revoca sesión
- `POST /auth/drive-token` (Bearer) → `{ driveAccessToken, expiresIn }` (efímero, para leer/subir bytes a Drive directo)

**Álbumes / fotos / biblioteca** (todos Bearer, prefijo `/api/v1`):
- `GET /albums` (lista con `role` por álbum), `POST /albums`, `GET /albums/:id`, `PATCH /albums/:id`, `DELETE /albums/:id`
- `POST /photos`, `DELETE /photos/:id`, `GET /library`
- `POST /albums/:albumId/photos`, `DELETE /albums/:albumId/photos/:photoId`
- `PATCH /photos/:photoId/availability`

**Colaboradores:**
- `POST/GET/DELETE /albums/:albumId/invitations[...]`, `POST /invitations/:token/accept`
- `GET /albums/:albumId/collaborators`, `DELETE /albums/:albumId/collaborators/:userId`, `DELETE /albums/:albumId/collaborators/me`

**Compartir / visor / NFC-QR** (parte pública SIN Bearer): enlace estable de compartición y resolución pública del token, y redirección 302 desde la URL de NFC/QR. Confirmá formas exactas en el README del backend y en `sharing_api.dart` de la app.

**Salud:** `GET /api/v1/health`.

Códigos de error a manejar en UX: `GOOGLE_AUTH_FAILED`, `SESSION_REFRESH_INVALID`, `DRIVE_REAUTHORIZATION_REQUIRED`, `INVALID_REQUEST`, `NOT_FOUND` (recurso ajeno/inexistente → 404 uniforme, no reveles existencia), `INVITATION_NOT_USABLE` (410), `CANNOT_REMOVE_OWNER`/`CANNOT_LEAVE_AS_OWNER` (400).

## Reglas de negocio que no debés romper (ya implementadas en app + backend)

- **404 uniforme:** un álbum/foto ajeno o inexistente responde 404 igual — no distingas "no existe" de "no es tuyo" en la UI.
- **Roles por álbum:** `owner` vs `collaborator`. Gestión (renombrar, visibilidad, eliminar, administrar colaboradores) es **owner-only**. El colaborador aporta fotos y solo puede quitar las suyas.
- **Visor público** es solo lectura y **no requiere login** (D2).
- **Sin GPS/EXIF** en el modelo de foto (privacidad, D8).
- Las miniaturas y full-res se piden a **Google Drive** usando el token que emite el backend; la web no pasa por el backend para los bytes.

## Cómo trabajar

1. Leé primero: `README.md` (raíz), `memora-backend/README.md` (contrato API completo), y recorré `memora-app/lib/` (auth, albums, photos, sharing) para entender flujos y reglas.
2. Leé `memora-web/src/lib/api/*` y `src/app/*` para partir de lo que ya existe.
3. Diseñá la estructura de la web (rutas App Router, estado de sesión, componentes, estilo) — **esas decisiones son tuyas**. Mantené coherencia visual con la identidad de Memora (mirá el design system de la app en `lib/design/` como inspiración de marca: colores, tipografía, tono).
4. Implementá incrementalmente, extendiendo la capa de API existente. Priorizá: **auth → álbumes/biblioteca → visor de fotos → visor público compartido → colaboradores**.
5. Verificá que `npm run build` pasa y que la web arranca en dev (`PORT=3001 npm run dev`) contra el backend local.

## Límites (no hacer)

- No agregues SDKs de proveedores de backend ni hables con nada que no sea la API del backend (salvo Google Drive para bytes, con el token del backend).
- No redefinas reglas de producto ni el contrato de la API; si algo del backend no te da lo que necesitás, anotalo y pedí aclaración en vez de inventar.
- No implementes programación de NFC físico (es exclusivo de la app móvil).
- No toques `.npmrc`, git anidado, ni configuración global de Node.

## Entregable

Una `memora-web` que: permite login con Google, muestra la biblioteca y los álbumes del usuario con sus fotos desde Drive, permite gestionar álbumes y colaboradores según rol, y sirve un visor público de álbumes compartidos accesible por enlace/QR sin login. Con `npm run build` verde y arranque en dev funcionando contra el backend.

---
