# Especificaciones de Memora

Este directorio contiene las especificaciones técnicas del proyecto. Cada spec describe **qué** debe construirse y **cómo validarlo**. Claude implementa a partir de estos documentos; Kiro (Tech Lead) valida el resultado contra los criterios de cada spec.

## PRIORIDAD ACTUAL (decisión del Product Owner)

**Foco: `memora-app` (Flutter) + solo lo mínimo de `memora-backend` que la app necesite.**

- No se avanza en todo a la vez.
- `memora-web` queda **EN PAUSA** hasta nuevo aviso (su fundación ya está PASS, pero no se le añaden funcionalidades por ahora).
- Cada nueva funcionalidad del MVP se construye primero para app + backend; la web se retomará más adelante.

## Arranque en frío (leer primero)

`CONTEXTO-KIRO.md` es el **mapa de arranque**: el único documento que el Tech Lead necesita leer para retomar el trabajo. No reemplaza las fuentes de verdad (producto/estado/convenciones); las indexa y apunta a ellas. Los agentes custom de Kiro (`.kiro/agents/spec-writer.md` y `.kiro/agents/spec-validator.md`) arrancan leyéndolo.

## Organización (monorepo)

```
specs/
├── CONTEXTO-KIRO.md Mapa de arranque en frío (índice + punteros a las fuentes de verdad)
├── global/          Specs transversales que afectan a todo el repositorio
├── memora-backend/  Specs propias del backend (NestJS + TypeScript)
├── memora-web/      Specs propias de la plataforma web (Next.js)
└── memora-app/      Specs propias de la app móvil (Flutter)
```

- La numeración `specNN` es **independiente dentro de cada carpeta** (p. ej. `memora-backend/spec01`, `memora-web/spec01`).
- Las specs de `global/` se implementan/consideran antes que las de cada subproyecto cuando exista dependencia.

## Estructura de cada spec

Cada archivo `specNN-<nombre>.md` contiene:

1. **Objetivo** — para qué existe la spec.
2. **Alcance / Fuera de alcance** — límites explícitos.
3. **Comportamiento esperado** — requisitos verificables (usa SHALL/MUST para lo normativo).
4. **Checklist de implementación** — tareas `- [ ]` que Claude marca al completarlas.
5. **Criterios de validación** — lo que Kiro revisa para dar por buena la spec.
6. **Dependencias** — otras specs que deben estar listas antes.

## Estados de validación (los asigna Kiro al revisar)

- **PASS** — cumple la especificación.
- **PASS WITH NOTES** — cumple, con observaciones no bloqueantes.
- **CHANGES REQUIRED** — no cumple o hay problemas importantes.

## Reglas para Claude (implementador)

- Implementa según la spec aprobada. No redefinas requisitos de producto.
- Si encuentras una contradicción o ambigüedad: identifícala, explica la causa, propón una solución y solicita revisión. No cambies la spec en silencio.
- Marca las casillas del checklist solo cuando la tarea esté realmente completa y verificable.

## Índice de specs

### global/
- `spec01-estructura-monorepo.md` — estructura del monorepo y límites entre subproyectos.
- `spec02-contrato-api.md` — contrato base de la API HTTP/JSON (versionado, errores, correlación, salud).

### memora-backend/
- `spec01-fundacion-backend.md` — esqueleto NestJS, contrato base y aislamiento de proveedores.
- `spec02-autenticacion-google.md` — login con Google (flujo híbrido), sesión JWT propia y broker de tokens de Drive (scope `drive.file`).
- `spec03-biblioteca-albumes.md` — modelo y API de álbumes y biblioteca personal (M2); relación N:M foto↔álbum.
- `spec04-fotografias.md` — registro de fotos (referencias/metadatos) y coordinación de subida a Drive (M3 backend); biblioteca.
- `spec05-colaboradores.md` — invitaciones por enlace y roles Owner/Collaborator (M4 backend). Estado: PASS.
- `spec06-adoptar.md` — "Guardar en mi biblioteca" / copia de foto de colaborador (M5 backend). Estado: ⏸️ DIFERIDA A POST-MVP (no viable de forma transparente con `drive.file`; decisión del PO). Conserva el análisis técnico.
- `spec07-disponibilidad.md` — disponibilidad perezosa de fotos en Drive (M6 backend); cliente verifica → backend persiste. Estado: PASS.
- `spec08-abstraccion-almacenamiento.md` — abstracción `PhotoStorage` + referencia neutral `storageRef` (Drive detrás de interfaz; habilitador de storage futuro/M5). Estado: PASS.

### memora-web/
- `spec01-fundacion-web.md` — esqueleto Next.js y capa de acceso a la API.

### memora-app/
- `spec01-fundacion-app.md` — esqueleto Flutter y capa de acceso a la API.
- `spec02-login-google.md` — inicio de sesión con Google (nativo), obtención de `serverAuthCode`, sesión con el backend y estado de autenticación.

## Decisiones técnicas fijadas (aprobadas por el Product Owner)

Decisiones mixtas ya resueltas con tradeoff y aprobación:

- **Identidad / sesión en el backend: JWT propio.** El backend valida la identidad de Google y emite/gestiona sus propios tokens de sesión. Sin proveedor de identidad gestionado (evita lock-in y mantiene "clientes solo hablan con la API").
- **Base de datos — motor: PostgreSQL.** El modelo es relacional.
- **Base de datos — hosting: Neon** (Postgres serverless con escala a cero), a contratar solo cuando se necesite persistencia real.
- **Persistencia en el MVP: mocks en memoria** detrás de interfaces. La migración a Postgres/Neon será añadir un adaptador que implemente la misma interfaz, sin tocar lógica ni contrato de API.
- **Subida de fotos: directa del dispositivo a Google Drive del usuario** (el backend orquesta y autoriza, no recibe los bytes).
- **Autenticación: flujo híbrido de Google (offline access).** El cliente obtiene un `serverAuthCode` de un solo uso y lo envía al backend; el backend lo canjea por access + refresh token, guarda el **refresh token cifrado (nunca sale del backend)** y emite su propio JWT de sesión.
- **Scope de Google Drive: `drive.file`** (acceso solo a los archivos que Memora crea). Se descarta el scope `drive` completo por privacidad, UX del consentimiento y para evitar la auditoría de scopes restringidos de Google.
- **Token de Drive para el cliente: access token efímero** emitido por el backend bajo demanda (el cliente nunca ve el refresh token).

## Decisiones abiertas (pendientes)

- **Infraestructura/hosting del backend y despliegue** (dónde corre `memora-backend`, CI/CD): se decidirá antes de desplegar; no bloquea el desarrollo local.
- **Cifrado en reposo del refresh token**: mecanismo concreto (KMS gestionado vs. clave de aplicación) se decidirá junto con la infraestructura, antes del despliegue. En desarrollo con mocks se documenta la frontera.

## Pendientes conocidos (a retomar en specs futuras)

Trabajo diferido deliberadamente para no meter todo de golpe; NO olvidar:

- **App: refresco automático del JWT de sesión** y manejo de expiración (renovar con `/auth/refresh` cuando el access caduque). Diferido de `memora-app/spec02-login-google`.
- **App: obtención y uso del `drive-token`** para subir fotos directo a Drive. Irá en la spec de fotos.
- **Backend: `SessionRegistry` → interfaz con mock** (hoy es provider en memoria; el logout necesita persistencia real antes de desplegar). Ajuste no bloqueante de `memora-backend/spec02`.
- **Backend: cifrado real del refresh token** en `TokenStore` (hoy frontera documentada con mock).
- **Android release**: agregar el SHA-1 de la clave de firma de release (Play Console) al cliente OAuth, además del de debug, antes de publicar.
- **Google: publicar la app OAuth** (salir de modo "Prueba") cuando se abra a usuarios fuera de la lista de test users.
- **memora-web**: EN PAUSA — retomar funcionalidades cuando el Product Owner lo indique.
