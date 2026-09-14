import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../common/exceptions/api.exception';

/** Central place for this module's error codes, so message text can't drift. */
export function googleAuthFailed(message: string): ApiException {
  return new ApiException(
    HttpStatus.UNAUTHORIZED,
    'GOOGLE_AUTH_FAILED',
    message,
  );
}

export function sessionRefreshInvalid(): ApiException {
  return new ApiException(
    HttpStatus.UNAUTHORIZED,
    'SESSION_REFRESH_INVALID',
    'La sesión no es válida, vuelve a iniciar sesión',
  );
}

export function driveReauthorizationRequired(): ApiException {
  return new ApiException(
    HttpStatus.UNAUTHORIZED,
    'DRIVE_REAUTHORIZATION_REQUIRED',
    'Es necesario volver a autorizar el acceso a Drive',
  );
}
