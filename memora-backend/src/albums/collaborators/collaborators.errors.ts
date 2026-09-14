import { HttpStatus } from '@nestjs/common';
import { ApiException } from '../../common/exceptions/api.exception';

/** Central place for this module's error codes, same pattern as auth.errors.ts. */

/** P5: accepted/revoked/expired/unknown token → 410, never 404 (the token
 *  itself was real input, unlike a guessed album id). */
export function invitationNotUsable(): ApiException {
  return new ApiException(
    HttpStatus.GONE,
    'INVITATION_NOT_USABLE',
    'Esta invitación ya no se puede usar',
  );
}

/** The owner can't remove themselves via the collaborator-removal endpoint. */
export function cannotRemoveOwner(): ApiException {
  return new ApiException(
    HttpStatus.BAD_REQUEST,
    'CANNOT_REMOVE_OWNER',
    'El owner no puede quitarse a sí mismo del álbum',
  );
}

/** The owner can't "abandon" their own album via the collaborator-leave endpoint. */
export function cannotLeaveAsOwner(): ApiException {
  return new ApiException(
    HttpStatus.BAD_REQUEST,
    'CANNOT_LEAVE_AS_OWNER',
    'El owner no puede abandonar su propio álbum',
  );
}
