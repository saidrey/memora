import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../../common/exceptions/api.exception';

/**
 * Central place for this module's error code, same pattern as
 * auth.errors.ts / collaborators' errors file. Used by every PhotoStorage
 * operation that's declared but not supported in the MVP (spec08) — never
 * a raw/uncaught error, always this uniform, machine-readable signal.
 */
export function storageOperationUnsupported(operation: string): ApiException {
  return new ApiException(
    HttpStatus.NOT_IMPLEMENTED,
    'STORAGE_OPERATION_UNSUPPORTED',
    `La operación de almacenamiento "${operation}" no está soportada`,
  );
}
