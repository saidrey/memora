import { AuthService } from '../../../auth/auth.service';
import { Photo } from '../photo.model';
import { GoogleDrivePhotoStorage } from './google-drive-photo-storage';

function buildPhoto(overrides: Partial<Photo> = {}): Photo {
  return {
    id: 'photo-1',
    ownerId: 'owner-1',
    storageRef: { provider: 'google-drive', fileId: 'drive-file-1' },
    createdAt: new Date(),
    availability: 'available',
    ...overrides,
  };
}

describe('GoogleDrivePhotoStorage (spec08-abstraccion-almacenamiento)', () => {
  it('getUploadAuthorization wraps AuthService.getDriveAccessToken without duplicating its logic', async () => {
    const getDriveAccessToken = jest.fn().mockResolvedValue({
      accessToken: 'ephemeral-token',
      expiresInSeconds: 3600,
    });
    const authService = { getDriveAccessToken } as unknown as AuthService;
    const storage = new GoogleDrivePhotoStorage(authService);

    const authorization = await storage.getUploadAuthorization('user-1');

    expect(getDriveAccessToken).toHaveBeenCalledWith('user-1');
    expect(authorization).toEqual({
      provider: 'google-drive',
      accessToken: 'ephemeral-token',
      expiresInSeconds: 3600,
    });
  });

  it('getUploadAuthorization propagates AuthService errors (e.g. DRIVE_REAUTHORIZATION_REQUIRED) unchanged', async () => {
    const error = new Error('boom');
    const authService = {
      getDriveAccessToken: jest.fn().mockRejectedValue(error),
    } as unknown as AuthService;
    const storage = new GoogleDrivePhotoStorage(authService);

    await expect(storage.getUploadAuthorization('user-1')).rejects.toBe(
      error,
    );
  });

  it('getReadReference returns a neutral reference without calling Drive', async () => {
    const authService = {
      getDriveAccessToken: jest.fn(),
    } as unknown as AuthService;
    const storage = new GoogleDrivePhotoStorage(authService);
    const photo = buildPhoto();

    const reference = await storage.getReadReference(photo);

    expect(reference).toEqual({ provider: 'google-drive', fileId: 'drive-file-1' });
    expect(authService.getDriveAccessToken).not.toHaveBeenCalled();
  });

  it.each([
    ['describe', () => new GoogleDrivePhotoStorage({} as AuthService).describe(buildPhoto())],
    ['exists', () => new GoogleDrivePhotoStorage({} as AuthService).exists(buildPhoto())],
    ['download', () => new GoogleDrivePhotoStorage({} as AuthService).download(buildPhoto())],
    ['stream', () => new GoogleDrivePhotoStorage({} as AuthService).stream(buildPhoto())],
    ['copy', () => new GoogleDrivePhotoStorage({} as AuthService).copy(buildPhoto(), 'other-owner')],
    ['delete', () => new GoogleDrivePhotoStorage({} as AuthService).delete(buildPhoto())],
  ])(
    '%s is declared but fails with the uniform STORAGE_OPERATION_UNSUPPORTED error, never a raw error',
    async (_name, invoke) => {
      await expect(invoke()).rejects.toMatchObject({
        getStatus: expect.any(Function),
        getResponse: expect.any(Function),
      });
      try {
        await invoke();
        throw new Error('expected invoke() to throw');
      } catch (error: any) {
        expect(error.getStatus()).toBe(501);
        expect(error.getResponse()).toMatchObject({
          code: 'STORAGE_OPERATION_UNSUPPORTED',
        });
      }
    },
  );
});
