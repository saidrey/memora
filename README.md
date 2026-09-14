# Memora

Plataforma para crear y compartir bibliotecas/álbumes digitales de fotografías y recuerdos.

## Estructura del monorepo

```
memora/
├── memora-app/       App móvil (Flutter) — principal punto de captura de contenido
├── memora-web/       Plataforma web (Next.js) — visor + plataforma autenticada
├── memora-backend/   Backend (NestJS + TypeScript) — única puerta de entrada a la lógica
└── specs/            Especificaciones técnicas (Kiro especifica, Claude implementa, Kiro valida)
```

## Regla de acceso (arquitectura)

- `memora-app` y `memora-web` se comunican con el sistema **únicamente a través de la API HTTP de `memora-backend`**.
- Los clientes **no** tienen dependencias directas a proveedores de backend (Firebase, Supabase u otros).
- **Única excepción:** para transferir los bytes de las fotografías del propio usuario, los clientes pueden contactar directamente a Google Drive del usuario, tras obtener del backend la autorización y los parámetros necesarios. Memora no almacena los bytes de las fotos.

## Contrato base de la API

- Recursos de negocio bajo el prefijo versionado `/api/v1`.
- `GET /api/v1/health` y `GET /health` (sin versionar, para probes de infraestructura): estado del servicio, sin autenticación.
- Errores en formato uniforme `{ code, message, requestId }`.
- Correlación de peticiones vía cabecera `x-request-id` (generada o propagada).

## Aislamiento del entorno de desarrollo

Este es un proyecto **personal**. Para no mezclarlo con configuraciones de trabajo:

- Cada subproyecto Node (`memora-backend`, `memora-web`) tiene su propio `.npmrc` apuntando al **registro público de npm**. No modificar ni eliminar.
- No usar `npm install -g` ni cambiar la configuración global de npm/Node.
- Backend en **NestJS 10** (compatible con Node 20).

## Puertos en desarrollo (convención)

Para poder correr los servicios simultáneamente en local:

| Subproyecto | Puerto |
|---|---|
| `memora-backend` (NestJS) | 3000 |
| `memora-web` (Next.js) | 3001 — arrancar con `PORT=3001 npm run dev` |
| `memora-app` (Flutter) | no expone servidor; consume `http://localhost:3000/api/v1` |

## Metodología (Spec-Driven)

1. **Kiro** (Tech Lead) crea/actualiza la spec en `specs/`.
2. **Claude** implementa siguiendo la spec y marca su avance.
3. **Kiro** valida el resultado contra los criterios de la spec y asigna: PASS / PASS WITH NOTES / CHANGES REQUIRED.

Para persistir el conocimiento entre sesiones y optimizar tokens, el arranque en frío del Tech Lead se resuelve con `specs/CONTEXTO-KIRO.md` (mapa+punteros a las fuentes de verdad) y dos agentes custom de Kiro en `.kiro/agents/`: `spec-writer` (escribe specs) y `spec-validator` (valida lo implementado).

Ver `specs/README.md` para convenciones, estados y decisiones abiertas, y `specs/CONTEXTO-KIRO.md` para el mapa de arranque.
