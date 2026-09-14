import { Injectable } from '@nestjs/common';
import { AuthService } from '../../../auth/auth.service';
import { Photo } from '../photo.model';
import { storageOperationUnsupported } from './photo-storage.errors';
import {
  PhotoStorage,
  ReadReference,
  UploadAuthorization,
} from './photo-storage.interface';

/**
 * The MVP's only PhotoStorage implementation (spec08). Wraps what already
 * exists in auth (the `drive-token` broker, spec02) instead of duplicating
 * the refresh-token lookup / Google API call here — AuthService stays the
 * single owner of that logic. This class never calls the Drive API itself
 * and never touches bytes (producto-mvp.md: "Memora no es custodio").
 */
@Injectable()
export class GoogleDrivePhotoStorage implements PhotoStorage {
  constructor(private readonly authService: AuthService) {}

  async getUploadAuthorization(userId: string): Promise<UploadAuthorization> {
    const token = await this.authService.getDriveAccessToken(userId);
    return {
      provider: 'google-drive',
      accessToken: token.accessToken,
      expiresInSeconds: token.expiresInSeconds,
    };
  }

  async getReadReference(photo: Photo): Promise<ReadReference> {
    // Purely neutral data — no call to Drive. The client/viewer resolves
    // the actual read (which endpoint, which of its own tokens) itself.
    return {
      provider: photo.storageRef.provider,
      fileId: photo.storageRef.fileId,
    };
  }

  async describe(): Promise<unknown> {
    // Not supported server-side in the MVP (spec07-disponibilidad.md, P1):
    // only the file's owner-scoped token can query it, and the backend
    // doesn't hold one for arbitrary photos. The client verifies and
    // reports via PhotosService.reportAvailability(Batch) instead.
    throw storageOperationUnsupported('describe');
  }

  async exists(): Promise<boolean> {
    throw storageOperationUnsupported('exists');
  }

  async download(): Promise<unknown> {
    throw storageOperationUnsupported('download');
  }

  async stream(): Promise<unknown> {
    throw storageOperationUnsupported('stream');
  }

  async copy(): Promise<Photo> {
    // M5 (spec06-adoptar.md) — explicitly deferred, not this spec's scope.
    throw storageOperationUnsupported('copy');
  }

  async delete(): Promise<void> {
    // Memora never deletes from the user's own Drive (product principle).
    throw storageOperationUnsupported('delete');
  }
}
