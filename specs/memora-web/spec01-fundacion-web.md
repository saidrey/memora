# spec01 — Fundación de la web (Next.js)

**Ámbito:** memora-web
**Estado de validación:** PASS (validado por Kiro en runtime: conectado→ok, caído→no disponible)

## Objetivo

Implementar sobre el esqueleto ya andamiado de `memora-web` (Next.js + TypeScript + Tailwind, dependencias instaladas) una capa de acceso a la API del backend, respetando el límite de que la web solo se comunica con el sistema a través de `memora-backend`.

## Estado del proyecto (contexto para el implementador)

- `memora-web/` YA está creado con Next.js (App Router) + TypeScript + Tailwind y dependencias instaladas.
- Existe un `.npmrc` local en `memora-web/` que apunta al registro público de npm. NO lo modifiques ni lo elimines.
- NO ejecutes `npm install -g` ni cambies configuración global de npm/Node.
- No inicialices un repositorio git dentro de `memora-web/` (es un monorepo con git en la raíz).
- **Convención de puertos (dev):** backend en 3000, web en **3001** (`PORT=3001 npm run dev`). El valor por defecto de la base URL apunta al backend en `http://localhost:3000/api/v1`.

## Alcance

- Capa de acceso a la API del backend con base URL configurable.
- Verificación de conectividad contra el endpoint de salud.

## Fuera de alcance

- Experiencias de negocio (visor de álbumes, plataforma autenticada, gestión).
- Autenticación con Google.
- Dependencias directas a proveedores de backend.

## Comportamiento esperado

- La web SHALL arrancar en modo desarrollo.
- La web SHALL consumir la API del backend a través de una capa dedicada con base URL configurable apuntando a `/api/v1`.
- La web NO SHALL incluir dependencias directas a SDKs de proveedores de backend.

## Checklist de implementación

- [x] Configurar una variable de entorno para la base URL de la API (`NEXT_PUBLIC_API_BASE_URL`, con `.env.example` documentado y valor por defecto para desarrollo apuntando al backend local).
- [x] Implementar una capa de acceso a la API (cliente HTTP reutilizable) que anteponga la base URL y encapsule las peticiones al backend (`src/lib/api/*`).
- [x] Implementar una función/servicio que consulte el endpoint de salud del backend (`GET /api/v1/health`) a través de esa capa.
- [x] Implementar una vista o componente mínimo que muestre el estado de conectividad con el backend (ok / no disponible).
- [x] Verificar que el proyecto arranca (`npm run dev`), compila (`npm run build`) y consume el endpoint de salud correctamente.

## Criterios de validación (los revisa Kiro)

- El proyecto arranca en desarrollo y `npm run build` pasa.
- La base URL de la API es configurable por entorno (documentada en `.env.example`).
- Toda petición al backend pasa por la capa de acceso a la API (no hay `fetch` sueltos con URLs embebidas dispersos por el código).
- La web consulta el endpoint de salud a través de su capa de API y refleja el estado.
- No hay dependencias a SDKs de proveedores de backend (Firebase, Supabase u otros).
- No se creó un repositorio git anidado dentro de `memora-web/`.

## Dependencias

- `global/spec01-estructura-monorepo.md`
- `global/spec02-contrato-api.md`
- `memora-backend/spec01-fundacion-backend.md` (para probar contra `/health`).
