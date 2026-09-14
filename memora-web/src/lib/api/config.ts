/**
 * Default matches memora-backend's own default (`PORT ?? 3000`) for local
 * development. Override via NEXT_PUBLIC_API_BASE_URL — see .env.example.
 */
const DEFAULT_API_BASE_URL = 'http://localhost:3000/api/v1';

/** Base URL of memora-backend's API, including the versioned prefix. */
export function getApiBaseUrl(): string {
  const configured = process.env.NEXT_PUBLIC_API_BASE_URL;
  const base =
    configured && configured.trim().length > 0
      ? configured.trim()
      : DEFAULT_API_BASE_URL;
  return base.replace(/\/+$/, '');
}
