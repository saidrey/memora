import { Invitation, InvitationStatus } from './invitation.model';

export const INVITATION_REPOSITORY = Symbol('INVITATION_REPOSITORY');

export interface InvitationRepository {
  create(input: {
    albumId: string;
    token: string;
    createdBy: string;
    expiresAt: Date;
  }): Promise<Invitation>;
  findById(id: string): Promise<Invitation | null>;
  findByToken(token: string): Promise<Invitation | null>;
  listByAlbum(albumId: string): Promise<Invitation[]>;
  /** Transitions status; optionally records who accepted it. */
  updateStatus(
    id: string,
    status: InvitationStatus,
    acceptedByUserId?: string,
  ): Promise<Invitation>;
  /** Cascade cleanup when an album is deleted (D16). Never touches other albums. */
  deleteAllForAlbum(albumId: string): Promise<void>;
}
