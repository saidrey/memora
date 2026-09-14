import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../exceptions/api.exception';

/**
 * Extracts and validates a required string field from an unknown request
 * body. Shared by any module needing this exact shape of check (auth,
 * albums) so the rule can't drift between them.
 */
export function requireStringField(
  body: unknown,
  field: string,
  options: { maxLength?: number } = {},
): string {
  const value = (body as Record<string, unknown> | null)?.[field];
  if (typeof value !== 'string') {
    throw invalidField(field);
  }
  const trimmed = value.trim();
  if (trimmed.length === 0) {
    throw invalidField(field);
  }
  if (options.maxLength !== undefined && trimmed.length > options.maxLength) {
    throw invalidField(field);
  }
  return trimmed;
}

function invalidField(field: string): ApiException {
  return new ApiException(
    HttpStatus.BAD_REQUEST,
    'INVALID_REQUEST',
    `${field} no es válido`,
  );
}
