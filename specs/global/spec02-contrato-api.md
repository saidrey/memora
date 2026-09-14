# spec02 — Contrato base de la API

**Ámbito:** global
**Estado de validación:** PASS (validado en el backend; `/health` versionado y sin versionar operativos)

## Objetivo

Definir el contrato base de la API HTTP/JSON de Memora: versionado, formato uniforme de respuestas y errores, correlación de peticiones y endpoint de salud, para que todas las funcionalidades posteriores se construyan sobre convenciones consistentes y verificables.

## Alcance

- Convenciones transversales de la API que consumen `memora-web` y `memora-app`.
- Contrato observable: rutas, formato de error, cabeceras de correlación, salud.

## Fuera de alcance

- Endpoints de negocio (auth, álbumes, fotos, etc.).
- Elección de base de datos, ORM o proveedor de identidad.

## Comportamiento esperado

### Versionado
- La API SHALL exponer sus recursos bajo el prefijo `/api/v1`.
- Un cambio incompatible SHALL introducirse bajo una nueva versión de ruta (p. ej. `/api/v2`) manteniendo operativa la anterior según la política de compatibilidad.

### Formato de error uniforme
- La API SHALL devolver los errores en JSON con los campos `code` (legible por máquina), `message` (descriptivo) y `requestId`.
- El código de estado HTTP SHALL corresponder a la categoría del error.
- Un recurso inexistente SHALL responder con HTTP 404 y el cuerpo con el formato uniforme.

### Correlación de peticiones
- La API SHALL asociar a cada petición un `requestId`, devolverlo en una cabecera de respuesta e incluirlo en los errores.
- Si el cliente envía un `requestId` en la cabecera, la API SHALL reutilizarlo en la respuesta y en los registros asociados.

### Salud del servicio
- El backend SHALL exponer un endpoint de salud versionado `GET /api/v1/health` que responda HTTP 200 indicando estado operativo, sin autenticación.
- El backend SHALL exponer además un endpoint `GET /health` **sin versionar** (fuera del prefijo `/api/v1`), sin autenticación, destinado a probes de infraestructura (liveness/readiness).

## Checklist de implementación

- [x] Configurar el prefijo global de versión `/api/v1`.
- [x] Implementar `GET /api/v1/health` sin autenticación (HTTP 200 + cuerpo de estado).
- [x] Implementar correlación de peticiones (genera o propaga `requestId`, lo expone en cabecera de respuesta y lo deja disponible para logs).
- [x] Implementar filtro global de errores con formato uniforme `{ code, message, requestId }`.
- [x] Documentar el contrato base (versionado, error, correlación, salud) dentro de `memora-backend`.
- [ ] **(Ajuste tras validación)** Exponer `GET /health` sin versionar para probes de infraestructura.

## Criterios de validación (los revisa Kiro)

- Los recursos responden bajo `/api/v1`.
- `GET /health` devuelve 200 sin credenciales.
- Toda respuesta incluye la cabecera de correlación; un `requestId` enviado por el cliente se reutiliza.
- Un 404 y un error genérico devuelven el formato uniforme `{ code, message, requestId }`.
- Existe documentación del contrato en el backend.

## Dependencias

- `global/spec01-estructura-monorepo.md`
- Se implementa concretamente en `memora-backend/spec01-fundacion-backend.md`.
