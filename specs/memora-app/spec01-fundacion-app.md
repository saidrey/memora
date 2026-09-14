# spec01 — Fundación de la app (Flutter)

**Ámbito:** memora-app
**Estado de validación:** PASS (validado por Kiro en runtime: capa API real contra backend, conectado→ok, caído→NETWORK_ERROR)

## Objetivo

Implementar sobre el esqueleto ya andamiado de `memora-app` (Flutter, org `app.memora`) una capa de acceso a la API del backend, respetando el límite de que la app solo se comunica con el sistema a través de `memora-backend` (excepto la transferencia de bytes a Google Drive del usuario, que se diseñará en specs posteriores).

## Estado del proyecto (contexto para el implementador)

- `memora-app/` YA está creado con Flutter (org `app.memora`, nombre `memora_app`).
- Flutter SDK ya instalado en el equipo; usa el SDK existente, no lo modifiques.
- NO cambies configuración global de Flutter/Dart ni instales herramientas globales.

## Alcance

- Capa de acceso a la API del backend con base URL configurable.
- Verificación de conectividad contra el endpoint de salud.

## Fuera de alcance

- Captura/selección y optimización de fotografías.
- Autenticación con Google y autorización de Drive.
- Subida directa a Drive (spec posterior).
- Dependencias directas a proveedores de backend.

## Comportamiento esperado

- La app SHALL compilar y `flutter analyze` SHALL pasar sin errores.
- La app SHALL consumir la API del backend a través de una capa dedicada con base URL configurable apuntando a `/api/v1`.
- La app NO SHALL incluir dependencias directas a SDKs de proveedores de backend.

## Checklist de implementación

- [x] Configurar la base URL de la API por entorno/configuración (`--dart-define=API_BASE_URL=...`, con valor por defecto para desarrollo apuntando al backend local; documentado, incluido el gotcha del emulador Android `10.0.2.2`).
- [x] Añadir la dependencia HTTP adecuada (`http`) en `pubspec.yaml`.
- [x] Implementar una capa de acceso a la API (cliente reutilizable) que anteponga la base URL y encapsule las peticiones al backend (`lib/api/*`).
- [x] Implementar una función/servicio que consulte el endpoint de salud del backend (`GET /api/v1/health`) a través de esa capa.
- [x] Implementar una pantalla mínima que muestre el estado de conectividad con el backend (ok / no disponible / reintentar).
- [x] Verificar que `flutter analyze` pasa y el proyecto compila (`flutter build macos` OK).

## Criterios de validación (los revisa Kiro)

- El proyecto compila y `flutter analyze` pasa sin errores.
- La base URL de la API es configurable (no hardcodeada dispersa en el código).
- Toda petición al backend pasa por la capa de acceso a la API.
- La app consulta el endpoint de salud a través de su capa de API y refleja el estado.
- No hay dependencias a SDKs de proveedores de backend (Firebase, Supabase u otros).

## Dependencias

- `global/spec01-estructura-monorepo.md`
- `global/spec02-contrato-api.md`
- `memora-backend/spec01-fundacion-backend.md` (para probar contra `/health`).
