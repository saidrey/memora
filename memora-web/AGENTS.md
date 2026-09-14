<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# memora-web — convenciones y gotchas

Toda comunicación con el backend pasa por `src/lib/api/`:

- **`client.ts`** — `apiFetch<T>(path, options)` es el único punto de entrada
  HTTP hacia `memora-backend`. Ningún otro archivo debe usar `fetch` directo
  contra el backend. Fuerza `no-store` por defecto (nada de datos cacheados
  obsoletos) y normaliza cualquier error a `ApiError`
  `{ code, message, requestId, status }` (formato uniforme de
  `specs/global/spec02-contrato-api.md`).
- **`config.ts`** — `getApiBaseUrl()` lee `NEXT_PUBLIC_API_BASE_URL`
  (fallback `http://localhost:3000/api/v1`). Configurar copiando
  `.env.example` a `.env.local`, nunca hardcodear la URL.

Para el estado de lo implementado spec por spec, ver `README.md` de esta
carpeta (ahí se documenta el avance porque `specs/` no se edita).

## Reglas de entorno

- No modificar `.npmrc`. No `npm install -g`. No cambiar config global de npm.
- `next dev` y `memora-backend` usan el puerto 3000 por defecto — si corres
  ambos a la vez, arrancar uno en otro puerto (`PORT=3001 npm run dev`).

## Tests

- `npm run build` debe pasar limpio antes de reportar terminado.
- Aún no hay un patrón de tests establecido más allá de spec01 (capa mínima
  de acceso a API) — al introducir el primero (unitario o e2e), documentar
  aquí el patrón elegido para que las siguientes specs lo reutilicen.
