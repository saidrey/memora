import 'album_models.dart';

/// An invitation's lifecycle status (spec05-ui-colaboradores.md /
/// `memora-backend`'s `InvitationStatus`). `'expired'` is detected lazily by
/// the backend (checked against `expiresAt` on every read) — the app never
/// computes this itself, it only ever reflects whatever the backend last
/// returned.
enum InvitationStatus {
  pending,
  accepted,
  revoked,
  expired;

  static InvitationStatus fromJson(String value) => switch (value) {
    'pending' => InvitationStatus.pending,
    'accepted' => InvitationStatus.accepted,
    'revoked' => InvitationStatus.revoked,
    _ => InvitationStatus.expired,
  };
}

/// `POST /api/v1/albums/:albumId/invitations` response — always carries
/// `token`/`url` (unlike [InvitationListItem], where the backend omits both
/// once the invitation is no longer `pending`).
class InvitationCreated {
  const InvitationCreated({
    required this.id,
    required this.token,
    required this.url,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String token;
  final String url;
  final InvitationStatus status;
  final DateTime expiresAt;
  final DateTime createdAt;

  factory InvitationCreated.fromJson(Map<String, dynamic> json) =>
      InvitationCreated(
        id: json['id'] as String,
        token: json['token'] as String,
        url: json['url'] as String,
        status: InvitationStatus.fromJson(json['status'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}

/// One entry of `GET /api/v1/albums/:albumId/invitations` (owner-only).
///
/// [token]/[url] are only present when [status] is `pending` — the backend
/// (`InvitationsService.toListItem`) deliberately omits both for any
/// invitation that's already accepted/revoked/expired, so they're nullable
/// here too rather than assumed present.
class InvitationListItem {
  const InvitationListItem({
    required this.id,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    this.acceptedByUserId,
    this.token,
    this.url,
  });

  final String id;
  final InvitationStatus status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final String? acceptedByUserId;
  final String? token;
  final String? url;

  bool get isPending => status == InvitationStatus.pending;

  factory InvitationListItem.fromJson(Map<String, dynamic> json) =>
      InvitationListItem(
        id: json['id'] as String,
        status: InvitationStatus.fromJson(json['status'] as String),
        createdBy: json['createdBy'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        acceptedByUserId: json['acceptedByUserId'] as String?,
        token: json['token'] as String?,
        url: json['url'] as String?,
      );
}

/// One entry of `GET /api/v1/albums/:albumId/collaborators` (owner-only).
///
/// Deliberately just [userId] — an internal id, NOT an email or display
/// name. The backend (`CollaboratorsService.list`, `memora-backend`) does
/// not expose any PII for a collaborator today; see the note in this app's
/// `CLAUDE.md` ("Colaboradores: sin PII, solo `userId`") — this is a real
/// UX limitation flagged for Kiro, not something to paper over with
/// invented data.
class CollaboratorListItem {
  const CollaboratorListItem({
    required this.userId,
    required this.role,
    required this.joinedAt,
  });

  final String userId;
  final AlbumRole role;
  final DateTime joinedAt;

  factory CollaboratorListItem.fromJson(Map<String, dynamic> json) =>
      CollaboratorListItem(
        userId: json['userId'] as String,
        role: AlbumRole.fromJson(json['role'] as String),
        joinedAt: DateTime.parse(json['joinedAt'] as String),
      );
}
