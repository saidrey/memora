import { Kysely } from 'kysely';

export interface UsersTable {
  id: string;
  google_id: string;
  email: string;
  name: string | null;
}
export interface AlbumsTable {
  id: string;
  owner_id: string;
  name: string;
  visibility: string;
  created_at: Date;
  updated_at: Date;
}
export interface PhotosTable {
  id: string;
  owner_id: string;
  storage_provider: string;
  storage_file_id: string;
  created_at: Date;
  captured_at: Date | null;
  width: number | null;
  height: number | null;
  mime_type: string | null;
  size_bytes: number | null;
  availability: string;
  availability_checked_at: Date | null;
}
export interface AlbumPhotosTable {
  album_id: string;
  photo_id: string;
}
export interface MembershipsTable {
  album_id: string;
  user_id: string;
  joined_at: Date;
}
export interface InvitationsTable {
  id: string;
  album_id: string;
  token: string;
  created_by: string;
  status: string;
  expires_at: Date;
  accepted_by_user_id: string | null;
  created_at: Date;
}
export interface ShareLinksTable {
  id: string;
  album_id: string;
  token: string;
  status: string;
  created_at: Date;
}
export interface NfcQrTagsTable {
  id: string;
  album_id: string;
  type: string;
  token: string;
  status: string;
  created_at: Date;
  updated_at: Date;
  disabled_at: Date | null;
}
export interface RefreshTokensTable {
  user_id: string;
  ciphertext: string;
  nonce: string;
  auth_tag: string;
  updated_at: Date;
}
export interface SessionJtisTable {
  user_id: string;
  jti: string;
  created_at: Date;
}

export interface Database {
  users: UsersTable;
  albums: AlbumsTable;
  photos: PhotosTable;
  album_photos: AlbumPhotosTable;
  memberships: MembershipsTable;
  invitations: InvitationsTable;
  share_links: ShareLinksTable;
  nfc_qr_tags: NfcQrTagsTable;
  refresh_tokens: RefreshTokensTable;
  session_jtis: SessionJtisTable;
}

export const KYSELY = Symbol('KYSELY');
export type Db = Kysely<Database>;
