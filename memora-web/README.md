This is a [Next.js](https://nextjs.org) project bootstrapped with [`create-next-app`](https://nextjs.org/docs/app/api-reference/cli/create-next-app).

## Capa de acceso a la API

Implementa `specs/memora-web/spec01-fundacion-web.md`. Toda comunicación con
`memora-backend` pasa por `src/lib/api/`:

- **`config.ts`** — `getApiBaseUrl()` lee `NEXT_PUBLIC_API_BASE_URL` (con
  fallback a `http://localhost:3000/api/v1`, el default local del backend).
  Configúrala copiando `.env.example` a `.env.local`.
- **`client.ts`** — `apiFetch<T>(path, options)`, único punto de entrada
  HTTP hacia el backend. Antepone la base URL, exige `no-store` por defecto
  (nada de datos cacheados obsoletos) y normaliza cualquier error (de red o
  HTTP no-2xx) a `ApiError` con `{ code, message, requestId, status }`.
  Ningún otro archivo debe usar `fetch` directo contra el backend.
- **`health.ts`** — `getHealth()`: `GET /api/v1/health` a través de
  `apiFetch`.
- **`errors.ts`** — tipo `ApiErrorBody` (formato uniforme de
  `global/spec02-contrato-api.md`) y la clase `ApiError`.

`src/app/page.tsx` es la vista mínima: un Server Component que llama a
`getHealth()` y muestra "Backend: ok" o "Backend: no disponible" (con el
motivo). No es una pantalla diseñada — la identidad visual de Memora está
pendiente de una spec/decisión aparte.

## Desarrollo

```bash
cp .env.example .env.local   # ajusta NEXT_PUBLIC_API_BASE_URL si hace falta
npm run dev
npm run build
```

`next dev` y `memora-backend` (`start:dev`) usan el puerto 3000 por
defecto — si corres ambos a la vez localmente, arranca uno en otro puerto,
p. ej. `PORT=3001 npm run dev`.

---

Getting started (plantilla original de `create-next-app`):

```bash
npm run dev
```

Open [http://localhost:3000](http://localhost:3000) with your browser to see the result.

This project uses [`next/font`](https://nextjs.org/docs/app/building-your-application/optimizing/fonts) to automatically optimize and load [Geist](https://vercel.com/font), a new font family for Vercel.

## Learn More

To learn more about Next.js, take a look at the following resources:

- [Next.js Documentation](https://nextjs.org/docs) - learn about Next.js features and API.
- [Learn Next.js](https://nextjs.org/learn) - an interactive Next.js tutorial.
