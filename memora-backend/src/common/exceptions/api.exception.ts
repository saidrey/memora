import { HttpException } from '@nestjs/common';

/**
 * Throws a uniform { code, message } body that AllExceptionsFilter reads
 * verbatim, instead of deriving `code` purely from the HTTP status text.
 * Use this whenever the client needs a more specific machine-readable
 * signal than the status code alone conveys — e.g. distinguishing an
 * invalid session refresh token from "Drive needs re-authorization", both
 * HTTP 401 (see memora-backend/spec02-autenticacion-google.md).
 */
export class ApiException extends HttpException {
  constructor(status: number, code: string, message: string) {
    super({ code, message }, status);
  }
}
