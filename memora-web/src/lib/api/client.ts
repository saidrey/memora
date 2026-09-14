import { getApiBaseUrl } from './config';
import { ApiError, ApiErrorBody } from './errors';

export interface ApiRequestOptions {
  method?: string;
  cache?: RequestCache;
  signal?: AbortSignal;
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
): Promise<T> {
  const url = `${getApiBaseUrl()}${path.startsWith('/') ? path : `/${path}`}`;

  let response: Response;
  try {
    response = await fetch(url, {
      method: options.method ?? 'GET',
      cache: options.cache ?? 'no-store',
      signal: options.signal,
      headers: { Accept: 'application/json' },
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
    throw new ApiError(response.status, errorBody);
  }

  return body as T;
}
