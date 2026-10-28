/** Uniform error body defined by global/spec02-contrato-api.md. */
export interface ApiErrorBody {
  code: string;
  message: string;
  requestId?: string;
}

/** Thrown by apiFetch for any non-2xx response or network failure. */
export class ApiError extends Error {
  readonly status: number;
  readonly code: string;
  readonly requestId?: string;

  constructor(status: number, body: ApiErrorBody) {
    super(body.message);
    this.name = 'ApiError';
    this.status = status;
    this.code = body.code;
    this.requestId = body.requestId;
  }
}

export function userFacingError(error: unknown, fallback = 'No se pudo completar la operación.'): string {
  if (!(error instanceof ApiError)) return fallback;
  if (error.code === 'NOT_FOUND') return 'Este álbum no está disponible.';
  if (error.code === 'INVITATION_NOT_USABLE') return 'Esta invitación ya no está disponible.';
  if (error.code === 'DRIVE_REAUTHORIZATION_REQUIRED') return 'Vuelve a conectar Google Drive para ver estas fotos.';
  if (error.code === 'GOOGLE_AUTH_FAILED') return 'Google no pudo validar este inicio de sesión. Revisa que el Client ID y el secreto correspondan al mismo cliente OAuth.';
  if (error.code === 'SESSION_REFRESH_INVALID' || error.status === 401) return 'Tu sesión expiró. Vuelve a iniciar sesión.';
  return error.message || fallback;
}
