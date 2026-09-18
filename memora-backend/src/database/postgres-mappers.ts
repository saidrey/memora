import { Album } from '../albums/album.model';
import { Photo } from '../albums/photos/photo.model';
import { AlbumMembership } from '../albums/collaborators/album-membership.model';
import { Invitation } from '../albums/collaborators/invitation.model';
import { ShareLink } from '../albums/shared/share-link.model';
import { NfcQrTag } from '../albums/nfc-qr/nfc-qr-tag.model';
import { User } from '../auth/users/user-repository.interface';
import {
  AlbumsTable,
  InvitationsTable,
  NfcQrTagsTable,
  PhotosTable,
  ShareLinksTable,
  UsersTable,
  MembershipsTable,
} from './database.types';

export const album = (r: AlbumsTable): Album => ({
  id: r.id,
  ownerId: r.owner_id,
  name: r.name,
  visibility: r.visibility as Album['visibility'],
  createdAt: new Date(r.created_at),
  updatedAt: new Date(r.updated_at),
});
export const photo = (r: PhotosTable): Photo => ({
  id: r.id,
  ownerId: r.owner_id,
  storageRef: {
    provider: r.storage_provider as 'google-drive',
    fileId: r.storage_file_id,
  },
  createdAt: new Date(r.created_at),
  ...(r.captured_at ? { capturedAt: new Date(r.captured_at) } : {}),
  ...(r.width == null ? {} : { width: r.width }),
  ...(r.height == null ? {} : { height: r.height }),
  ...(r.mime_type == null ? {} : { mimeType: r.mime_type }),
  ...(r.size_bytes == null ? {} : { sizeBytes: r.size_bytes }),
  availability: r.availability as Photo['availability'],
  ...(r.availability_checked_at
    ? { availabilityCheckedAt: new Date(r.availability_checked_at) }
    : {}),
});
export const membership = (r: MembershipsTable): AlbumMembership => ({
  albumId: r.album_id,
  userId: r.user_id,
  role: 'collaborator',
  joinedAt: new Date(r.joined_at),
});
export const invitation = (r: InvitationsTable): Invitation => ({
  id: r.id,
  albumId: r.album_id,
  token: r.token,
  createdBy: r.created_by,
  status: r.status as Invitation['status'],
  expiresAt: new Date(r.expires_at),
  ...(r.accepted_by_user_id ? { acceptedByUserId: r.accepted_by_user_id } : {}),
  createdAt: new Date(r.created_at),
});
export const shareLink = (r: ShareLinksTable): ShareLink => ({
  id: r.id,
  albumId: r.album_id,
  token: r.token,
  status: r.status as ShareLink['status'],
  createdAt: new Date(r.created_at),
});
export const tag = (r: NfcQrTagsTable): NfcQrTag => ({
  id: r.id,
  albumId: r.album_id,
  type: r.type as NfcQrTag['type'],
  token: r.token,
  status: r.status as NfcQrTag['status'],
  createdAt: new Date(r.created_at),
  updatedAt: new Date(r.updated_at),
  ...(r.disabled_at ? { disabledAt: new Date(r.disabled_at) } : {}),
});
export const user = (r: UsersTable): User => ({
  id: r.id,
  googleId: r.google_id,
  email: r.email,
  ...(r.name == null ? {} : { name: r.name }),
});
