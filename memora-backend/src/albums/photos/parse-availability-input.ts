import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../common/exceptions/api.exception';
import { requireStringField } from '../../common/validation/require-string-field';
import { PhotoAvailability } from './photo.model';
import { AvailabilityReport } from './photos.service';

const VALID_AVAILABILITY_VALUES: readonly string[] = [
  'available',
  'unavailable',
];

/** Body of PATCH /api/v1/photos/:photoId/availability. */
export function parseAvailabilityValue(body: unknown): PhotoAvailability {
  const value = (body as Record<string, unknown> | null)?.['availability'];
  if (
    typeof value !== 'string' ||
    !VALID_AVAILABILITY_VALUES.includes(value)
  ) {
    throw invalidField('availability');
  }
  return value as PhotoAvailability;
}

/** Body of POST /api/v1/photos/availability (batch, spec07 P2b). Only
 *  validates SHAPE — whether each photoId belongs to the caller is a
 *  service-level, per-entry concern (an entry failing that check is
 *  skipped, not a 400; see PhotosService.reportAvailabilityBatch). */
export function parseAvailabilityReportsInput(
  body: unknown,
): AvailabilityReport[] {
  const reports = (body as Record<string, unknown> | null)?.['reports'];
  if (!Array.isArray(reports)) {
    throw invalidField('reports');
  }
  return reports.map((entry) => ({
    photoId: requireStringField(entry, 'photoId'),
    availability: parseAvailabilityValue(entry),
  }));
}

function invalidField(field: string): ApiException {
  return new ApiException(
    HttpStatus.BAD_REQUEST,
    'INVALID_REQUEST',
    `${field} no es válido`,
  );
}
