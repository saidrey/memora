import { randomBytes } from 'node:crypto';
import { Inject, Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { AlbumAccessService } from './album-access.service';
import { invitationNotUsable } from './collaborators.errors';
import { Invitation, InvitationStatus } from './invitation.model';
import {
  INVITATION_REPOSITORY,
  InvitationRepository,
} from './invitation-repository.interface';
import {
  MEMBERSHIP_REPOSITORY,
  MembershipRepository,
} from './membership-repository.interface';

const DEFAULT_TTL_DAYS = 7;
const DEFAULT_BASE_URL = 'https://memora.app/invite/{token}';
const DAY_MS = 24 * 60 * 60 * 1000;

export interface InvitationCreated {
  id: string;
  token: string;
  url: string;
  status: InvitationStatus;
  expiresAt: Date;
  createdAt: Date;
}

export interface InvitationListItem {
  id: string;
  status: InvitationStatus;
  createdBy: string;
  createdAt: Date;
  expiresAt: Date;
  acceptedByUserId?: string;
  /** Only present for a still-`pending` invitation (P5: never for accepted/dead ones). */
  token?: string;
  url?: string;
}

/**
 * D12/D13: create/list/revoke invitations (owner-only), and accept them
 * (any authenticated user). Reads `APP_INVITE_BASE_URL` / `INVITATION_TTL_DAYS`
 * via ConfigService — the same pattern as GoogleOAuthClient/SessionTokenService
 * — never `process.env` directly.
 */
@Injectable()
export class InvitationsService {
  constructor(
    @Inject(INVITATION_REPOSITORY)
    private readonly invitations: InvitationRepository,
    @Inject(MEMBERSHIP_REPOSITORY)
    private readonly memberships: MembershipRepository,
    private readonly albumAccess: AlbumAccessService,
    private readonly configService: ConfigService,
  ) {}

  async create(ownerId: string, albumId: string): Promise<InvitationCreated> {
    await this.albumAccess.requireOwner(albumId, ownerId);

    const token = generateInvitationToken();
    const expiresAt = new Date(Date.now() + this.ttlDays * DAY_MS);
    const invitation = await this.invitations.create({
      albumId,
      token,
      createdBy: ownerId,
      expiresAt,
    });

    return {
      id: invitation.id,
      token: invitation.token,
      url: this.buildUrl(invitation.token),
      status: invitation.status,
      expiresAt: invitation.expiresAt,
      createdAt: invitation.createdAt,
    };
  }

  async list(ownerId: string, albumId: string): Promise<InvitationListItem[]> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    const invitations = await this.invitations.listByAlbum(albumId);
    const resolved = await Promise.all(
      invitations.map((invitation) => this.resolveEffectiveStatus(invitation)),
    );
    return resolved.map((invitation) => this.toListItem(invitation));
  }

  /** Revokes a `pending` invitation. Idempotent: revoking a non-pending one
   *  (already accepted/revoked/expired) is a no-op — it's already unusable. */
  async revoke(
    ownerId: string,
    albumId: string,
    invitationId: string,
  ): Promise<void> {
    await this.albumAccess.requireOwner(albumId, ownerId);
    const invitation = await this.invitations.findById(invitationId);
    if (!invitation || invitation.albumId !== albumId) {
      throw invitationNotFound();
    }
    const resolved = await this.resolveEffectiveStatus(invitation);
    if (resolved.status === 'pending') {
      await this.invitations.updateStatus(resolved.id, 'revoked');
    }
  }

  /**
   * P5 ordering: "already a member" is checked BEFORE the invitation's
   * status, so re-hitting accept on your own already-used link (or any
   * link, once you're already in) is idempotent (204) even if the
   * invitation itself is no longer pending. Only a caller who is NOT yet a
   * member is subject to the pending/expired/revoked/unknown-token check
   * (410 INVITATION_NOT_USABLE) — this is also what makes a token single-use
   * for anyone ELSE (P6): once accepted, its status is no longer 'pending',
   * so a different caller (not yet a member) is rejected.
   */
  async accept(userId: string, token: string): Promise<void> {
    const invitation = await this.invitations.findByToken(token);
    if (!invitation) {
      throw invitationNotUsable();
    }

    const role = await this.albumAccess.getRole(invitation.albumId, userId);
    if (role) {
      return;
    }

    const resolved = await this.resolveEffectiveStatus(invitation);
    if (resolved.status !== 'pending') {
      throw invitationNotUsable();
    }

    await this.memberships.addCollaborator(invitation.albumId, userId);
    await this.invitations.updateStatus(invitation.id, 'accepted', userId);
  }

  /** Lazily detects and persists expiry — the in-memory store has no clock
   *  of its own, so this is checked on every read (list/revoke/accept). */
  private async resolveEffectiveStatus(
    invitation: Invitation,
  ): Promise<Invitation> {
    if (
      invitation.status === 'pending' &&
      invitation.expiresAt.getTime() <= Date.now()
    ) {
      return this.invitations.updateStatus(invitation.id, 'expired');
    }
    return invitation;
  }

  private toListItem(invitation: Invitation): InvitationListItem {
    const showToken = invitation.status === 'pending';
    return {
      id: invitation.id,
      status: invitation.status,
      createdBy: invitation.createdBy,
      createdAt: invitation.createdAt,
      expiresAt: invitation.expiresAt,
      acceptedByUserId: invitation.acceptedByUserId,
      ...(showToken
        ? { token: invitation.token, url: this.buildUrl(invitation.token) }
        : {}),
    };
  }

  private buildUrl(token: string): string {
    return this.baseUrl.replace('{token}', token);
  }

  private get baseUrl(): string {
    return (
      this.configService.get<string>('APP_INVITE_BASE_URL') ?? DEFAULT_BASE_URL
    );
  }

  private get ttlDays(): number {
    const raw = this.configService.get<string>('INVITATION_TTL_DAYS');
    const parsed = raw !== undefined ? Number(raw) : NaN;
    return Number.isFinite(parsed) && parsed > 0 ? parsed : DEFAULT_TTL_DAYS;
  }
}

function generateInvitationToken(): string {
  // Opaque, random, unguessable (spec05: "no un id secuencial") — 256 bits
  // of entropy, URL-safe so it drops straight into APP_INVITE_BASE_URL.
  return randomBytes(32).toString('base64url');
}

function invitationNotFound(): NotFoundException {
  // A foreign/nonexistent invitationId under an owner-verified album is
  // just "not found" (same 404 pattern as everywhere else) — 410 is
  // reserved for a real invitation TOKEN that can no longer be used (P5).
  return new NotFoundException('Invitación no encontrada');
}
