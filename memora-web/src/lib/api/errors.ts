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
