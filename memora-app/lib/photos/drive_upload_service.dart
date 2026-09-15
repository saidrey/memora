import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown on any failure talking to the Google Drive API (network, non-2xx,
/// unexpected body). Never carries token contents.
class DriveUploadException implements Exception {
  const DriveUploadException(this.message);

  final String message;

  @override
  String toString() => 'DriveUploadException($message)';
}

/// Uploads optimized photo bytes directly to the user's Google Drive.
///
/// This is the ONE deliberate exception to "every backend call goes through
/// ApiClient": Drive is a different host with a different, short-lived
/// token (`driveAccessToken`, scope `drive.file`) that must never reach
/// memora-backend. Per spec03-fotografias.md decision 5, it's treated as a
/// plain HTTP endpoint via `package:http` — no Google Drive SDK is added.
///
/// Decision 1 (approved): all uploads go into a single "Memora" folder in
/// "My Drive" (no per-album folders — albums are a Memora-only concept).
/// The folder's `fileId` is cached on this instance so a batch (and any
/// later batch reusing the same service instance) doesn't repeat the
/// search/create round-trip.
class DriveUploadService {
  DriveUploadService({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  static const _filesEndpoint = 'https://www.googleapis.com/drive/v3/files';
  static const _uploadEndpoint =
      'https://www.googleapis.com/upload/drive/v3/files';
  static const _folderName = 'Memora';
  static const _folderMimeType = 'application/vnd.google-apps.folder';

  final http.Client _httpClient;

  /// In-memory only — never persisted, and irrelevant without a live
  /// [accessToken] to pair it with.
  String? _cachedFolderId;

  /// Uploads [bytes] as a new Drive file named [fileName] inside the
  /// "Memora" folder (resolving/creating it first if needed), and returns
  /// the new file's `fileId`. [accessToken] is sent only in this request's
  /// `Authorization` header — never logged, never sent elsewhere.
  Future<String> uploadFile({
    required String accessToken,
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final folderId = await _ensureMemoraFolderId(accessToken);

    const boundary = 'memora-drive-upload-boundary';
    final metadata = jsonEncode({
      'name': fileName,
      'parents': [folderId],
    });
    final body = BytesBuilder()
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
        utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      )
      ..add(utf8.encode(metadata))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(utf8.encode('Content-Type: $mimeType\r\n\r\n'))
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));

    final uri = Uri.parse(
      _uploadEndpoint,
    ).replace(queryParameters: {'uploadType': 'multipart', 'fields': 'id'});

    final response = await _guarded(
      () => _httpClient.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body.toBytes(),
      ),
      failureMessage: 'No se pudo subir la foto a Google Drive.',
    );

    final decoded = _decodeJson(response);
    final fileId = decoded['id'] as String?;
    if (fileId == null) {
      throw const DriveUploadException(
        'No se pudo subir la foto a Google Drive.',
      );
    }
    return fileId;
  }

  Future<String> _ensureMemoraFolderId(String accessToken) async {
    final cached = _cachedFolderId;
    if (cached != null) return cached;

    final existingId = await _findMemoraFolder(accessToken);
    final folderId = existingId ?? await _createMemoraFolder(accessToken);
    _cachedFolderId = folderId;
    return folderId;
  }

  Future<String?> _findMemoraFolder(String accessToken) async {
    final query =
        "name = '$_folderName' and mimeType = '$_folderMimeType' "
        'and trashed = false';
    final uri = Uri.parse(_filesEndpoint).replace(
      queryParameters: {
        'q': query,
        'spaces': 'drive',
        'fields': 'files(id,name)',
      },
    );

    final response = await _guarded(
      () => _httpClient.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      ),
      failureMessage: 'No se pudo acceder a Google Drive.',
    );

    final decoded = _decodeJson(response);
    final files = decoded['files'] as List<dynamic>? ?? const [];
    if (files.isEmpty) return null;
    return (files.first as Map<String, dynamic>)['id'] as String?;
  }

  Future<String> _createMemoraFolder(String accessToken) async {
    final response = await _guarded(
      () => _httpClient.post(
        Uri.parse(_filesEndpoint),
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'name': _folderName, 'mimeType': _folderMimeType}),
      ),
      failureMessage: 'No se pudo crear la carpeta de Memora en Drive.',
    );

    final decoded = _decodeJson(response);
    final folderId = decoded['id'] as String?;
    if (folderId == null) {
      throw const DriveUploadException(
        'No se pudo crear la carpeta de Memora en Drive.',
      );
    }
    return folderId;
  }

  Future<http.Response> _guarded(
    Future<http.Response> Function() send, {
    required String failureMessage,
  }) async {
    final http.Response response;
    try {
      response = await send();
    } catch (_) {
      throw DriveUploadException(failureMessage);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DriveUploadException(failureMessage);
    }
    return response;
  }

  Map<String, dynamic> _decodeJson(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Falls through to the generic failure below.
    }
    throw const DriveUploadException('Respuesta inesperada de Google Drive.');
  }

  void dispose() => _httpClient.close();
}
