import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../common/exceptions/api.exception';
import { requireStringField } from '../../common/validation/require-string-field';
import { RegisterPhotoInput } from './photos.service';

/**
 * Only driveFileId is required — everything else (dimensions, mimeType,
 * capturedAt, albumId) is optional, since the spec's D8 metadata list
 * doesn't mandate the client always has all of it.
 */
export function parseRegisterPhotoInput(body: unknown): RegisterPhotoInput {
  const driveFileId = requireStringField(body, 'driveFileId');
  const record = (body as Record<string, unknown>) ?? {};

  return {
    driveFileId,
    capturedAt: optionalDate(record, 'capturedAt'),
    width: optionalPositiveNumber(record, 'width'),
    height: optionalPositiveNumber(record, 'height'),
    sizeBytes: optionalPositiveNumber(record, 'sizeBytes'),
    mimeType: optionalString(record, 'mimeType'),
    albumId: optionalString(record, 'albumId'),
  };
}

function invalidField(field: string): ApiException {
  return new ApiException(
    HttpStatus.BAD_REQUEST,
    'INVALID_REQUEST',
    `${field} no es válido`,
  );
}

function optionalString(
  record: Record<string, unknown>,
  field: string,
): string | undefined {
  const value = record[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string' || value.trim().length === 0) {
    throw invalidField(field);
  }
  return value.trim();
}

function optionalPositiveNumber(
  record: Record<string, unknown>,
  field: string,
): number | undefined {
  const value = record[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) {
    throw invalidField(field);
  }
  return value;
}

function optionalDate(
  record: Record<string, unknown>,
  field: string,
): Date | undefined {
  const value = record[field];
  if (value === undefined || value === null) return undefined;
  if (typeof value !== 'string') {
    throw invalidField(field);
  }
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) {
    throw invalidField(field);
  }
  return parsed;
}
