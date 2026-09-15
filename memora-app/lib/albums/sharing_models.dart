/// Models for spec07-compartir-nfc-qr.md — the album's share-link (M7) and
/// its NFC/QR tags (M8), both consumed through [SharingApi].
library;

/// `POST /api/v1/albums/:albumId/share-link` response (also returned by a
/// second call, since the backend's `createOrGetExisting` is idempotent —
/// one link per album, see `memora-backend/spec09-compartir-visor.md`).
class ShareLink {
  const ShareLink({required this.token, required this.url});

  final String token;
  final String url;

  factory ShareLink.fromJson(Map<String, dynamic> json) => ShareLink(
    token: json['token'] as String,
    url: json['url'] as String,
  );
}

/// Which kind of physical tag a [NfcQrTag] is meant for. The `url` is the
/// same shape either way (`/n/{token}`) — only how the app *presents* it
/// differs: rendered as a QR code for `qr`, shown as selectable text (for the
/// user to grab with their own NFC-writing tool) for `nfc` (spec07 decision:
/// native NFC writing is out of scope for this cut).
enum NfcQrTagType {
  nfc,
  qr;

  static NfcQrTagType fromJson(String value) =>
      value == 'QR' ? NfcQrTagType.qr : NfcQrTagType.nfc;

  String toJson() => this == NfcQrTagType.qr ? 'QR' : 'NFC';
}

/// A tag's lifecycle status. `disabled` is a soft-delete — not reactivable in
/// this MVP (`memora-backend/spec10-nfc-qr.md`).
enum NfcQrTagStatus {
  enabled,
  disabled;

  static NfcQrTagStatus fromJson(String value) =>
      value == 'disabled' ? NfcQrTagStatus.disabled : NfcQrTagStatus.enabled;
}

/// `POST /api/v1/albums/:albumId/nfc-qr-tags` and
/// `GET /api/v1/nfc-qr-tags/:id` response shape.
///
/// There is deliberately no `List<NfcQrTag>` model here — the backend has no
/// `GET /albums/:albumId/nfc-qr-tags` (list-by-album) endpoint, only
/// create-under-album and get/disable-by-own-id (see `SharingApi`'s doc
/// comment and this app's CLAUDE.md).
class NfcQrTag {
  const NfcQrTag({
    required this.id,
    required this.albumId,
    required this.type,
    required this.token,
    required this.status,
    required this.url,
    required this.createdAt,
    required this.updatedAt,
    this.disabledAt,
  });

  final String id;
  final String albumId;
  final NfcQrTagType type;
  final String token;
  final NfcQrTagStatus status;
  final String url;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? disabledAt;

  bool get isDisabled => status == NfcQrTagStatus.disabled;

  /// Used locally, after a successful `disable` call, to reflect the new
  /// status in the in-memory list without a round trip to `GET
  /// /nfc-qr-tags/:id` (the 204 response carries no body to parse from).
  NfcQrTag copyWith({NfcQrTagStatus? status}) => NfcQrTag(
    id: id,
    albumId: albumId,
    type: type,
    token: token,
    status: status ?? this.status,
    url: url,
    createdAt: createdAt,
    updatedAt: updatedAt,
    disabledAt: disabledAt,
  );

  factory NfcQrTag.fromJson(Map<String, dynamic> json) => NfcQrTag(
    id: json['id'] as String,
    albumId: json['albumId'] as String,
    type: NfcQrTagType.fromJson(json['type'] as String),
    token: json['token'] as String,
    status: NfcQrTagStatus.fromJson(json['status'] as String),
    url: json['url'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    disabledAt: json['disabledAt'] != null
        ? DateTime.parse(json['disabledAt'] as String)
        : null,
  );
}
