import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { STATUS_CODES } from 'node:http';
import { Request, Response } from 'express';
import { REQUEST_ID_HEADER } from '../middleware/request-id.middleware';

/** Uniform error body required by global/spec02-contrato-api.md. */
export interface ApiErrorBody {
  code: string;
  message: string;
  requestId?: string;
}

function codeForStatus(status: number): string {
  const phrase = STATUS_CODES[status] ?? 'Error';
  return phrase
    .toUpperCase()
    .replace(/[^A-Z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

/**
 * Prefers an explicit `code` on the exception's response body (set via
 * ApiException) over the generic status-derived one, so two errors sharing
 * an HTTP status (e.g. two different 401s) can still be told apart.
 */
function codeForException(exception: unknown, status: number): string {
  if (exception instanceof HttpException) {
    const body = exception.getResponse();
    if (
      body &&
      typeof body === 'object' &&
      typeof (body as { code?: unknown }).code === 'string'
    ) {
      return (body as { code: string }).code;
    }
  }
  return codeForStatus(status);
}

function messageForException(exception: unknown, status: number): string {
  if (exception instanceof HttpException) {
    const body = exception.getResponse();
    if (typeof body === 'string') return body;
    if (body && typeof body === 'object' && 'message' in body) {
      const message = (body as { message: unknown }).message;
      return Array.isArray(message) ? message.join(', ') : String(message);
    }
    return exception.message;
  }
  return status >= 500 ? 'Internal server error' : 'Unexpected error';
}

/**
 * Single global error handler: every thrown exception (HttpException or not)
 * lands here and is normalized to { code, message, requestId }, per
 * global/spec02-contrato-api.md.
 */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger(AllExceptionsFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const requestIdHeader = request.headers[REQUEST_ID_HEADER];
    const requestId =
      typeof requestIdHeader === 'string' ? requestIdHeader : undefined;

    if (status >= 500) {
      this.logger.error(
        exception instanceof Error ? exception.stack : exception,
      );
    }

    const body: ApiErrorBody = {
      code: codeForException(exception, status),
      message: messageForException(exception, status),
      requestId,
    };

    response.status(status).json(body);
  }
}
