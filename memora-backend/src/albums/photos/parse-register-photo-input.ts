import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../common/exceptions/api.exception';
import { requireStringField } from '../../common/validation/require-string-field';
import { StorageProvider } from './photo.model';
import { RegisterPhotoInput } from './photos.service';

/** spec08: the only value accepted in the MVP — anything else is a 400,
 *  not silently coerced, so a future 2nd provider is a deliberate change. */
const SUPPORTED_PROVIDERS: readonly StorageProvider[] = ['google-drive'];

/**
 * Only `storageRef.fileId` is required — everything else (dimensions,
 * mimeType, capturedAt, albumId) is optional, since the spec's D8 metadata
 * list doesn't mandate the client always has all of it. `storageRef.provider`
 * is also optional (spec08, "Nota de contrato de API") — the MVP has a
 * single provider and defaults to it; PhotosService.register applies that
 * default, this parser only validates it when the client does send one.
 */
export function parseRegisterPhotoInput(body: unknown): RegisterPhotoInput {
  const record = (body as Record<string, unknown>) ?? {};
  const storageRef = requireStorageRef(record);

  return {
    storageRef,
    capturedAt: optionalDate(record, 'capturedAt'),
    width: optionalPositiveNumber(record, 'width'),
    height: optionalPositiveNumber(record, 'height'),
    sizeBytes: optionalPositiveNumber(record, 'sizeBytes'),
    mimeType: optionalString(record, 'mimeType'),
    albumId: optionalString(record, 'albumId'),
  };
}

function requireStorageRef(
  record: Record<string, unknown>,
): { fileId: string; provider?: StorageProvider } {
  const value = record.storageRef;
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    throw invalidField('storageRef');
  }
  const fileId = requireStringField(value, 'fileId');
  const provider = (value as Record<string, unknown>).provider;
  if (provider === undefined || provider === null) {
    return { fileId };
  }
  if (
    typeof provider !== 'string' ||
    !SUPPORTED_PROVIDERS.includes(provider as StorageProvider)
  ) {
    throw invalidField('storageRef.provider');
  }
  return { fileId, provider: provider as StorageProvider };
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
