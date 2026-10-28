import { getApiBaseUrl } from './config';
import { ApiError, ApiErrorBody } from './errors';

export interface ApiRequestOptions {
  method?: string;
  body?: unknown;
  auth?: boolean;
  cache?: RequestCache;
  signal?: AbortSignal;
}

let accessToken: string | null = null;
let refreshToken: string | null = null;
let refreshInFlight: Promise<string | null> | null = null;
let onSessionRefreshed: ((access: string, refresh: string) => void) | null = null;
let onSessionInvalidated: (() => void) | null = null;

export function configureSession(options: {
  accessToken?: string | null;
  refreshToken?: string | null;
  onSessionRefreshed?: (access: string, refresh: string) => void;
  onSessionInvalidated?: () => void;
}): void {
  accessToken = options.accessToken ?? null;
  refreshToken = options.refreshToken ?? null;
  onSessionRefreshed = options.onSessionRefreshed ?? null;
  onSessionInvalidated = options.onSessionInvalidated ?? null;
}

async function refreshSession(): Promise<string | null> {
  if (refreshInFlight) return refreshInFlight;
  if (!refreshToken) return null;
  refreshInFlight = (async () => {
    try {
      const response = await fetch(`${getApiBaseUrl()}/auth/refresh`, {
        method: 'POST',
        cache: 'no-store',
        headers: { Accept: 'application/json', 'Content-Type': 'application/json' },
        body: JSON.stringify({ sessionRefreshToken: refreshToken }),
      });
      const body = (await response.json().catch(() => null)) as Record<string, unknown> | null;
      if (!response.ok || typeof body?.sessionAccessToken !== 'string') throw new Error('refresh failed');
      const nextAccess = body.sessionAccessToken;
      const nextRefresh = typeof body.sessionRefreshToken === 'string' ? body.sessionRefreshToken : refreshToken;
      accessToken = nextAccess;
      refreshToken = nextRefresh;
      onSessionRefreshed?.(nextAccess, nextRefresh);
      return nextAccess;
    } catch {
      accessToken = null;
      refreshToken = null;
      onSessionInvalidated?.();
      return null;
    } finally {
      refreshInFlight = null;
    }
  })();
  return refreshInFlight;
}

function isApiErrorBody(value: unknown): value is ApiErrorBody {
  return (
    typeof value === 'object' &&
    value !== null &&
    'code' in value &&
    'message' in value
  );
}

/**
 * Single entry point for talking to memora-backend. Every request to the
 * API must go through this function rather than a bare `fetch` with an
 * embedded URL — per global/spec01-estructura-monorepo.md ("los clientes
 * solo acceden a través de la API") and memora-web/spec01-fundacion-web.md.
 */
export async function apiFetch<T>(
  path: string,
  options: ApiRequestOptions = {},
  retry = true,
): Promise<T> {
  const url = `${getApiBaseUrl()}${path.startsWith('/') ? path : `/${path}`}`;

  let response: Response;
  try {
    const headers: Record<string, string> = {
      Accept: 'application/json',
      ...(options.body === undefined ? {} : { 'Content-Type': 'application/json' }),
      ...(accessToken && options.auth !== false ? { Authorization: `Bearer ${accessToken}` } : {}),
    };
    response = await fetch(url, {
      method: options.method ?? 'GET',
      cache: options.cache ?? 'no-store',
      signal: options.signal,
      headers,
      body: options.body === undefined ? undefined : JSON.stringify(options.body),
    });
  } catch {
    throw new ApiError(0, {
      code: 'NETWORK_ERROR',
      message: 'No se pudo contactar al backend',
    });
  }

  const body: unknown = await response.json().catch(() => null);

  if (!response.ok) {
    const errorBody: ApiErrorBody = isApiErrorBody(body)
      ? body
      : {
          code: 'UNKNOWN_ERROR',
          message: `Error inesperado (HTTP ${response.status})`,
        };
    if (response.status === 401 && retry && options.auth !== false && errorBody.code !== 'DRIVE_REAUTHORIZATION_REQUIRED') {
      const nextAccess = await refreshSession();
      if (nextAccess) return apiFetch<T>(path, options, false);
    }
    throw new ApiError(response.status, errorBody);
  }

  return body as T;
}
