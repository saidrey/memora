import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../common/exceptions/api.exception';
import { NfcQrTagType } from './nfc-qr-tag.model';

const VALID_TYPES: readonly string[] = ['NFC', 'QR'];

/** Body of POST /api/v1/albums/:albumId/nfc-qr-tags: manual validation, same
 *  pattern as parse-availability-input.ts (no class-validator). */
export function parseNfcQrTagType(body: unknown): NfcQrTagType {
  const value = (body as Record<string, unknown> | null)?.['type'];
  if (typeof value !== 'string' || !VALID_TYPES.includes(value)) {
    throw new ApiException(
      HttpStatus.BAD_REQUEST,
      'INVALID_REQUEST',
      'type debe ser NFC o QR',
    );
  }
  return value as NfcQrTagType;
}
