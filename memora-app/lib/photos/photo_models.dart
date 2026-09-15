/// Where a photo's bytes live. Only Google Drive is supported today
/// (`memora-backend/spec08-abstraccion-almacenamiento.md`); `provider` is
/// still modeled (from the response) even though the app never sends it on
/// registration (the backend defaults it to `'google-drive'`).
class StorageRef {
  const StorageRef({required this.provider, required this.fileId});

  final String provider;
  final String fileId;

  factory StorageRef.fromJson(Map<String, dynamic> json) => StorageRef(
    provider: json['provider'] as String,
    fileId: json['fileId'] as String,
  );
}

/// Whether a photo's bytes are still reachable at its `storageRef` (checked
/// client-side against the storage provider, per
/// `memora-backend/spec07-disponibilidad.md`) — added in
/// spec04-ui-albumes.md so the album grid can flag photos that vanished
/// from Drive without hiding them (M6). Defaults to `available` when the
/// field is missing from a response, matching the backend's own default at
/// registration time.
enum PhotoAvailability {
  available,
  unavailable;

  static PhotoAvailability fromJson(String? value) =>
      value == 'unavailable'
      ? PhotoAvailability.unavailable
      : PhotoAvailability.available;
}

/// A photo as registered in memora-backend (`POST /api/v1/photos` response,
/// and the shape of each entry in `AlbumDetail.photos`).
class Photo {
  const Photo({
    required this.id,
    required this.storageRef,
    this.width,
    this.height,
    this.mimeType,
    this.sizeBytes,
    this.capturedAt,
    this.albumId,
    this.availability = PhotoAvailability.available,
  });

  final String id;
  final StorageRef storageRef;
  final int? width;
  final int? height;
  final String? mimeType;
  final int? sizeBytes;
  final DateTime? capturedAt;
  final String? albumId;
  final PhotoAvailability availability;

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
    id: json['id'] as String,
    storageRef: StorageRef.fromJson(json['storageRef'] as Map<String, dynamic>),
    width: json['width'] as int?,
    height: json['height'] as int?,
    mimeType: json['mimeType'] as String?,
    sizeBytes: json['sizeBytes'] as int?,
    capturedAt: json['capturedAt'] != null
        ? DateTime.tryParse(json['capturedAt'] as String)
        : null,
    albumId: json['albumId'] as String?,
    availability: PhotoAvailability.fromJson(json['availability'] as String?),
  );
}
