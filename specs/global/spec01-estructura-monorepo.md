# spec01 — Estructura del monorepo

**Ámbito:** global
**Estado de validación:** PASS

## Objetivo

Establecer la organización del monorepo de Memora y los límites entre sus subproyectos, garantizando que las aplicaciones cliente accedan al sistema únicamente a través de la API del backend, con la única excepción aprobada de Google Drive.

## Alcance

- Estructura de carpetas en la raíz del repositorio.
- Reglas de comunicación entre subproyectos.
- Convenciones básicas de versionado de código (`.gitignore`, `README` raíz).

## Fuera de alcance

- Implementación de lógica de negocio (auth, álbumes, fotos, colaboradores, NFC/QR).
- Selección de base de datos, proveedor de identidad, infraestructura o cloud.

## Comportamiento esperado

- El repositorio SHALL contener en la raíz los subproyectos `memora-app` (Flutter), `memora-web` (Next.js) y `memora-backend` (NestJS + TypeScript), más el directorio `specs/`.
- Las apps cliente (`memora-app`, `memora-web`) SHALL comunicarse con el sistema exclusivamente a través de la API HTTP de `memora-backend`.
- Las apps cliente NO SHALL incluir dependencias directas a SDKs de proveedores de backend (Firebase, Supabase u otros).
- Como única excepción, las apps cliente SHALL poder contactar directamente a Google Drive del usuario para transferir los bytes de sus propios archivos, obteniendo del backend la autorización y los parámetros necesarios.

## Checklist de implementación

- [x] Crear los directorios raíz `memora-app/`, `memora-web/`, `memora-backend/`.
- [x] Añadir `README.md` raíz que documente la estructura, el rol de cada subproyecto y la regla de acceso (clientes → solo API; excepción Drive).
- [x] Añadir `.gitignore` adecuado por subproyecto (Node/Next.js, Flutter) y en la raíz.
- [x] Verificar que no se versionan artefactos de build ni dependencias.

## Criterios de validación (los revisa Kiro)

- Existen los tres subproyectos y `specs/` en la raíz.
- El `README` raíz describe la estructura y la regla de acceso.
- Ningún cliente tiene dependencias a SDKs de proveedores de backend.
- Los `.gitignore` excluyen build y dependencias.

## Dependencias

- Ninguna.
