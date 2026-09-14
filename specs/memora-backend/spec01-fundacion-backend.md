# spec01 — Fundación del backend (NestJS)

**Ámbito:** memora-backend
**Estado de validación:** PASS (validado por Kiro en runtime; ver notas al final)

## Objetivo

Implementar sobre el esqueleto ya andamiado de `memora-backend` (NestJS 10 + TypeScript, dependencias instaladas) el contrato base de la API definido en `global/spec02`: versionado, salud, correlación de peticiones y formato uniforme de errores.

## Estado del proyecto (contexto para el implementador)

- `memora-backend/` YA está creado con NestJS 10 + TypeScript y las dependencias instaladas (`npm install` hecho).
- Existe un `.npmrc` local en `memora-backend/` que apunta al registro público de npm. NO lo modifiques ni lo elimines.
- NO ejecutes `npm install -g` ni cambies configuración global de npm/Node.
- Usa NestJS 10 (compatible con Node 20). No actualices a NestJS 11+ ni cambies la versión de Node.

## Alcance

- Implementación del contrato base de API sobre el esqueleto existente (versionado, salud, correlación, errores).

## Fuera de alcance

- Lógica de negocio (auth, álbumes, fotos, colaboradores, NFC/QR).
- Interfaces de integración externa (identidad, persistencia, almacenamiento/Drive) y sus mocks: se definirán en la spec que realmente las consuma (principio de mínima complejidad: no se crean capas sin consumidor).
- Implementaciones concretas de proveedor real (base de datos, identidad, Drive).
- Infraestructura, cloud, CI/CD.

## Estrategia de persistencia (decidida por Tech Lead — para specs futuras)

- Cuando se introduzca persistencia, se usarán **adaptadores mock en memoria** detrás de interfaces, y la lógica dependerá siempre de las interfaces, nunca de una implementación concreta.
- Migrar más adelante a una base de datos real (previsiblemente Postgres) debe requerir solo añadir un nuevo adaptador que implemente la misma interfaz, sin tocar la lógica ni el contrato de API.
- Las interfaces se crearán en la spec que las consuma, no de forma anticipada.

## Comportamiento esperado

- El backend SHALL arrancar en modo desarrollo y servir sus recursos de negocio bajo el prefijo `/api/v1`.
- El backend SHALL cumplir el contrato base descrito en `global/spec02-contrato-api.md`.
- El backend SHALL exponer, además del `/api/v1/health` versionado, un endpoint `/health` **sin versionar** (fuera del prefijo `/api/v1`), sin autenticación, destinado a probes de infraestructura (liveness/readiness).
- El backend SHALL aplicar mínima complejidad: sin abstracciones ni capas sin consumidor.

## Checklist de implementación

- [x] Configurar el prefijo global `/api/v1` en el arranque de la aplicación (`main.ts`/`bootstrap.ts`).
- [x] Implementar `GET /api/v1/health` sin autenticación que devuelva HTTP 200 y un cuerpo indicando estado operativo (`{ status: "ok" }`).
- [x] Implementar un middleware de correlación que genere un `requestId` cuando el cliente no lo envíe, reutilice el enviado por el cliente si viene en cabecera, y lo exponga en la cabecera de respuesta (`x-request-id`).
- [x] Implementar un filtro global de excepciones que produzca el formato uniforme `{ code, message, requestId }` con el código HTTP correspondiente (incluye el caso 404 de recurso inexistente).
- [x] Limpiar el `AppController`/`AppService` de ejemplo (se reemplazaron por módulos con propósito).
- [x] Documentar en el backend (README propio) el contrato base.
- [x] Añadir pruebas e2e que cubran: `/health` (200 sin auth), prefijo `/api/v1`, correlación (`x-request-id` presente; y reutilizado si el cliente lo envía) y formato de error uniforme en un 404.
- [x] Verificar que `npm run build`, `npm run test` y `npm run test:e2e` pasan.
- [x] **(Ajuste tras validación)** Exponer `/health` **sin versionar** (fuera de `/api/v1`), sin autenticación, para probes de infraestructura, y cubrirlo con una prueba e2e.

## Criterios de validación (los revisa Kiro)

- El servidor arranca y sirve los recursos de negocio bajo `/api/v1`. — **OK**
- `GET /api/v1/health` responde 200 sin credenciales. — **OK**
- Existe `/health` sin versionar (200, sin auth) para probes. — **OK**
- Toda respuesta incluye la cabecera `x-request-id`; un `x-request-id` enviado por el cliente se reutiliza en la respuesta. — **OK**
- Un 404 (recurso inexistente) devuelve el formato uniforme `{ code, message, requestId }` con HTTP 404. — **OK**
- No hay dependencias a SDKs de proveedores (Firebase, Supabase, motores de DB) ni abstracciones especulativas. — **OK**
- `npm run build`, `npm run test` y `npm run test:e2e` pasan. — **OK**
- Existe documentación del contrato base en el README del backend. — **OK**

## Dependencias

- `global/spec01-estructura-monorepo.md`
- `global/spec02-contrato-api.md`

## Notas de validación (Kiro)

- **Resultado final: PASS** — todos los criterios verificados en runtime (build, 3 unit + 5 e2e, y pruebas en vivo con curl de `/health`, `/api/v1/health`, correlación y 404).
- **Interfaces de integración retiradas** del alcance (decisión Tech Lead + PO): contradecían "sin abstracciones especulativas". `src/integrations/*` eliminado; se recrearán en la spec que las consuma.
- **`/health` sin versionar**: implementado sobre el adaptador HTTP crudo (no `exclude`) para evitar colisión de sub-path con el controlador versionado; sigue pasando por el middleware de correlación. Decisión técnica correcta, aprobada.
- **Test del filtro de excepciones**: cubre el path 500 y verifica que un error interno no filtra detalles al cliente (cobertura de seguridad).
