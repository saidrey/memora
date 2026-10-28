import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../common/exceptions/api.exception';

export function drivePermissionMissing(): ApiException {
  return new ApiException(HttpStatus.CONFLICT, 'DRIVE_PERMISSION_MISSING', 'No se puede revocar el permiso de Drive heredado');
}

export function albumStorageFailed(): ApiException {
  return new ApiException(HttpStatus.BAD_GATEWAY, 'ALBUM_STORAGE_FAILED', 'No se pudo preparar el almacenamiento del álbum');
}
