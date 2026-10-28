import '../photos/photo_models.dart';

/// `PRIVATE`/`PUBLIC` (D17, `producto-mvp.md`) — default `PRIVATE`, editable
/// only by the album's owner via `PATCH /api/v1/albums/:id`.
enum AlbumVisibility {
  private,
  public;

  static AlbumVisibility fromJson(String value) =>
      value == 'PUBLIC' ? AlbumVisibility.public : AlbumVisibility.private;

  String toJson() => this == AlbumVisibility.public ? 'PUBLIC' : 'PRIVATE';
}

/// A user's relationship to an album (D1, `producto-mvp.md`): only the
/// `owner` administers the album (rename/visibility/delete); a
/// `collaborator` can view everything and contribute photos, never admin
/// actions.
enum AlbumRole {
  owner,
  collaborator;

  static AlbumRole fromJson(String value) =>
      value == 'owner' ? AlbumRole.owner : AlbumRole.collaborator;
}

/// `POST /api/v1/albums` and `PATCH /api/v1/albums/:id` response shape.
class AlbumSummary {
  const AlbumSummary({
    required this.id,
    required this.name,
    required this.visibility,
    required this.photoCount,
    required this.createdAt,
    required this.updatedAt,
    this.driveFolderId,
    this.uploadTarget,
  });

  final String id;
  final String name;
  final AlbumVisibility visibility;
  final int photoCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? driveFolderId;
  final AlbumUploadTarget? uploadTarget;

  factory AlbumSummary.fromJson(Map<String, dynamic> json) => AlbumSummary(
    id: json['id'] as String,
    name: json['name'] as String,
    visibility: AlbumVisibility.fromJson(json['visibility'] as String),
    photoCount: json['photoCount'] as int,
    createdAt: DateTime.parse(json['createdAt'] as String),
    updatedAt: DateTime.parse(json['updatedAt'] as String),
    driveFolderId: json['driveFolderId'] as String?,
    uploadTarget: json['uploadTarget'] is Map<String, dynamic>
        ? AlbumUploadTarget.fromJson(
            json['uploadTarget'] as Map<String, dynamic>,
          )
        : null,
  );
}

class AlbumUploadTarget {
  const AlbumUploadTarget({required this.provider, required this.folderId});

  final String provider;
  final String folderId;

  factory AlbumUploadTarget.fromJson(Map<String, dynamic> json) =>
      AlbumUploadTarget(
        provider: json['provider'] as String,
        folderId: json['folderId'] as String,
      );
}

/// One entry of `GET /api/v1/albums` — an [AlbumSummary] plus the caller's
/// [role] in it. Covers both owned albums and albums the caller
/// collaborates on (P3, `memora-backend/spec05-colaboradores.md`).
class AlbumListItem extends AlbumSummary {
  const AlbumListItem({
    required super.id,
    required super.name,
    required super.visibility,
    required super.photoCount,
    required super.createdAt,
    required super.updatedAt,
    super.driveFolderId,
    super.uploadTarget,
    required this.role,
  });

  final AlbumRole role;

  factory AlbumListItem.fromJson(Map<String, dynamic> json) {
    final summary = AlbumSummary.fromJson(json);
    return AlbumListItem(
      id: summary.id,
      name: summary.name,
      visibility: summary.visibility,
      photoCount: summary.photoCount,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      role: AlbumRole.fromJson(json['role'] as String),
      driveFolderId: summary.driveFolderId,
      uploadTarget: summary.uploadTarget,
    );
  }
}

/// `GET /api/v1/albums/:id` response — an [AlbumSummary] plus its photos.
///
/// Deliberately does NOT carry a `role` field: unlike `AlbumListItem`,
/// `memora-backend`'s `AlbumDetail` (see `albums.service.ts`) never
/// includes one — only the combined list endpoint does. Callers that need
/// the caller's role while viewing a detail screen must carry it over from
/// the `AlbumListItem` used to navigate there (see
/// `AlbumsController.loadAlbumDetail`'s `role` parameter).
class AlbumDetail extends AlbumSummary {
  const AlbumDetail({
    required super.id,
    required super.name,
    required super.visibility,
    required super.photoCount,
    required super.createdAt,
    required super.updatedAt,
    required this.photos,
    super.driveFolderId,
    super.uploadTarget,
  });

  final List<Photo> photos;

  factory AlbumDetail.fromJson(Map<String, dynamic> json) {
    final summary = AlbumSummary.fromJson(json);
    final rawPhotos = json['photos'] as List<dynamic>? ?? const [];
    return AlbumDetail(
      id: summary.id,
      name: summary.name,
      visibility: summary.visibility,
      photoCount: summary.photoCount,
      createdAt: summary.createdAt,
      updatedAt: summary.updatedAt,
      photos: rawPhotos
          .map((entry) => Photo.fromJson(entry as Map<String, dynamic>))
          .toList(),
      driveFolderId: summary.driveFolderId,
      uploadTarget: summary.uploadTarget,
    );
  }
}
