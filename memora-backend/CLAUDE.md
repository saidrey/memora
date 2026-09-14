# memora-backend — convenciones y gotchas

NestJS 10, Node 20, TypeScript. Backend = única puerta de entrada a la
lógica; nunca maneja bytes de fotos (solo referencias/metadatos — ver
`producto-mvp.md`, principio "Memora no es custodio").

Para el estado de lo implementado spec por spec, ver `README.md` de esta
carpeta (ahí se documenta el avance porque `specs/` no se edita).

## Reglas de entorno

- No modificar `.npmrc`. No `npm install -g`. No cambiar config global de npm.
- Mantener NestJS 10 / Node 20.
- `@nestjs/jwt` fijado en **11.0.2** — la 12.x es ESM-only y rompe este
  proyecto CJS (`SyntaxError: Cannot use import statement outside a module`).
  No actualizar sin resolver antes la incompatibilidad ESM/CJS.
- `tsconfig.json` debe mantener `"isolatedModules": true`. Sin eso, ts-jest
  type-checkea el programa completo en cada test file — con dependencias de
  tipos pesadas (p. ej. `google-auth-library`) eso pasó de ~1s a ~300s por
  test run.

## Patrones establecidos (seguirlos, no reinventarlos)

- **Repository pattern con DI tokens**: interfaz + `Symbol('X_REPOSITORY')` +
  implementación in-memory. Nada de DB/SDKs de proveedores reales todavía —
  eso es una migración futura que no debe tocar la lógica de negocio.
- **`requireOwned<T extends {ownerId}>()`**
  (`src/common/authorization/require-owned.ts`) para checks de propiedad:
  recurso ajeno o inexistente → 404 uniforme (nunca 403 — no revelar
  existencia de recursos de otros usuarios).
- **`requireStringField()`** (`src/common/validation/`) para validar campos
  de entrada — no se usa `class-validator`, es una elección deliberada de
  mínima complejidad.
- **Contrato de error uniforme** `{ code, message, requestId }` vía
  `AllExceptionsFilter` — `ApiException(status, code, message)` para fijar un
  `code` explícito; si no, se deriva del status HTTP.
- **Relaciones N:M** (p. ej. álbum↔foto) se modelan como
  `Map<id, Set<relatedId>>` en el repositorio in-memory — el `Set` evita
  duplicados por construcción.
- Módulos que necesiten reusar `SessionAuthGuard` deben importar
  `AuthModule`, que exporta tanto el guard como `SessionTokenService` (su
  dependencia). Exportar solo el guard rompe la DI en el módulo consumidor.

## Tests

- Los e2e usan `beforeAll`/`afterAll` (una app Nest por archivo de test, no
  por test) — con `beforeEach`/`afterEach` aparece un flake intermitente de
  socket (`Parse Error: Expected HTTP/`, `ECONNRESET`) al crecer la suite.
  Ver la nota de infraestructura de tests en `README.md` para el detalle
  completo y la tasa residual aceptada.
- Evitar `Promise.all()` para disparar requests concurrentes de supertest
  dentro de un mismo test — aumenta la probabilidad de ese mismo flake.
  Preferir awaits secuenciales.
- Si un test se ve "colgado" o cascada de fallos sin relación aparente con el
  código: correr `ps aux | grep jest` antes de asumir un bug de lógica — ya
  hubo un proceso jest huérfano de una sesión anterior corriendo 4+ horas que
  causó timeouts de 300s+ en toda la suite.
- Escribir tests unitarios Y e2e para cada endpoint/comportamiento nuevo.
- Antes de reportar terminado: `npm run build`, `npm run test`,
  `npm run test:e2e` deben pasar limpio.

## Autorización (fase actual)

Solo el dueño de un recurso puede leerlo/mutarlo (álbumes, fotos). No hay
colaboradores todavía (eso es una spec futura) — no implementar accesos
compartidos por adelantado.
