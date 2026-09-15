import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../api/api_exception.dart';
import 'drive_token_api.dart';
import 'drive_upload_service.dart';
import 'photo_models.dart';
import 'photo_optimizer.dart';
import 'photos_api.dart';

enum PhotoUploadStatus {
  queued,
  optimizing,
  uploading,
  registering,
  done,
  error,
}

/// Per-photo state for one batch. [id] is a local, non-sensitive identifier
/// (the picked file's display name) used only as a widget/list key — never
/// logged alongside any token.
class PhotoUploadItem {
  PhotoUploadItem({required this.id, required this.file});

  final String id;
  final XFile file;
  PhotoUploadStatus status = PhotoUploadStatus.queued;
  String? errorMessage;
  Photo? photo;

  /// True iff [status] is `error` specifically because of
  /// `DRIVE_REAUTHORIZATION_REQUIRED` — as opposed to any other failure
  /// (network, a plain expired-session 401, etc.). Lets
  /// [PhotoUploadController.retryAfterDriveReconnect] retry only the items a
  /// successful Drive reconnect can actually fix, not every failed item.
  bool failedDueToDriveReauth = false;
}

/// Orchestrates the per-batch flow from spec03-fotografias.md, decision 4:
/// N photos processed IN SEQUENCE (not parallel), each going
/// optimize -> (shared) drive-token -> upload to Drive -> register in
/// backend, with per-photo progress and partial failures — one photo
/// failing never stops or corrupts the rest of the batch.
///
/// A plain [ChangeNotifier], same pattern as [AuthController]. Never calls
/// into auth/session logic itself: a `DRIVE_REAUTHORIZATION_REQUIRED`
/// failure is surfaced as a message, never a sign-out (D10) — actually
/// reconnecting Drive is `AuthController.reconnectDrive()`
/// (spec06-sesion-y-reauth-drive.md, A1.6); this controller only exposes
/// [retryAfterDriveReconnect] for the caller to invoke once that succeeds.
class PhotoUploadController extends ChangeNotifier {
  PhotoUploadController({
    required this.imagePicker,
    required this.photoOptimizer,
    required this.driveTokenApi,
    required this.driveUploadService,
    required this.photosApi,
  });

  final ImagePicker imagePicker;
  final PhotoOptimizer photoOptimizer;
  final DriveTokenApi driveTokenApi;
  final DriveUploadService driveUploadService;
  final PhotosApi photosApi;

  List<PhotoUploadItem> items = [];
  bool isRunning = false;

  /// True iff at least one item in [items] is currently failed specifically
  /// because of `DRIVE_REAUTHORIZATION_REQUIRED` — drives whether the UI
  /// offers a "Reconectar Google Drive" action instead of (or alongside) the
  /// plain error text.
  bool get hasDriveReauthFailures =>
      items.any((item) => item.failedDueToDriveReauth);

  /// Batch-level message — set for `DRIVE_REAUTHORIZATION_REQUIRED` and for
  /// a failure to even open the picker. Never contains raw error/token
  /// details.
  String? batchErrorMessage;

  DriveToken? _driveToken;

  /// True once a `DRIVE_REAUTHORIZATION_REQUIRED` has been seen in the
  /// current batch: short-circuits any further token requests for the rest
  /// of the batch instead of repeating a call that will only fail again.
  bool _driveReauthorizationRequired = false;

  /// Opens the system photo picker for one or more images and runs the
  /// full batch. [albumId], if given, associates every registered photo
  /// with that album (D11: without it, photos land only in the library).
  Future<void> pickAndUploadPhotos({String? albumId}) async {
    if (isRunning) return;

    final List<XFile> picked;
    try {
      // requestFullMetadata: false — this app strips EXIF/GPS itself
      // (PhotoOptimizer, D8) and never needs the picker's own metadata, so
      // there's no reason to ask iOS's PHPicker for full library access.
      picked = await imagePicker.pickMultiImage(requestFullMetadata: false);
    } catch (_) {
      batchErrorMessage = 'No se pudo abrir la galería de fotos.';
      notifyListeners();
      return;
    }
    if (picked.isEmpty) return;

    await uploadPickedFiles(picked, albumId: albumId);
  }

  /// The batch itself, split out from picking so it's callable (and
  /// testable) with any list of [XFile]s — real ones from the gallery, or
  /// fakes built with `XFile.fromData` in tests.
  Future<void> uploadPickedFiles(List<XFile> files, {String? albumId}) async {
    if (isRunning) return;

    items = [
      for (final file in files) PhotoUploadItem(id: file.name, file: file),
    ];
    batchErrorMessage = null;
    _driveReauthorizationRequired = false;
    isRunning = true;
    notifyListeners();

    for (final item in items) {
      await _processItem(item, albumId: albumId);
      notifyListeners();
    }

    isRunning = false;
    // Discard the batch's Drive token once the batch is done — it's never
    // held onto beyond what's needed to finish in-flight uploads.
    _driveToken = null;
    notifyListeners();
  }

  /// Re-runs the pipeline (spec06-sesion-y-reauth-drive.md, A1.6) for only
  /// the items that failed with `DRIVE_REAUTHORIZATION_REQUIRED` in the last
  /// batch — never the ones that already finished (`done`) or failed for an
  /// unrelated reason (network, expired session, etc.), since a Drive
  /// reconnect can't fix those. Call this after
  /// `AuthController.reconnectDrive()` succeeds.
  Future<void> retryAfterDriveReconnect({String? albumId}) async {
    if (isRunning) return;

    final toRetry = items
        .where((item) => item.failedDueToDriveReauth)
        .toList(growable: false);
    if (toRetry.isEmpty) return;

    // A fresh Drive authorization means the short-circuit from the previous
    // attempt no longer applies — without resetting this, every retried
    // item would immediately re-throw DriveReauthorizationRequiredException
    // from _ensureDriveToken without ever calling the backend again.
    _driveReauthorizationRequired = false;
    batchErrorMessage = null;
    isRunning = true;
    notifyListeners();

    for (final item in toRetry) {
      item.status = PhotoUploadStatus.queued;
      item.errorMessage = null;
      item.failedDueToDriveReauth = false;
      notifyListeners();
      await _processItem(item, albumId: albumId);
      notifyListeners();
    }

    isRunning = false;
    _driveToken = null;
    notifyListeners();
  }

  Future<void> _processItem(PhotoUploadItem item, {String? albumId}) async {
    try {
      item.status = PhotoUploadStatus.optimizing;
      notifyListeners();
      final sourceBytes = await item.file.readAsBytes();
      final optimized = await photoOptimizer.optimize(sourceBytes);

      item.status = PhotoUploadStatus.uploading;
      notifyListeners();
      final token = await _ensureDriveToken();
      final fileId = await driveUploadService.uploadFile(
        accessToken: token.accessToken,
        bytes: optimized.bytes,
        fileName: '${DateTime.now().microsecondsSinceEpoch}.jpg',
        mimeType: 'image/jpeg',
      );

      item.status = PhotoUploadStatus.registering;
      notifyListeners();
      final photo = await photosApi.registerPhoto(
        fileId: fileId,
        width: optimized.width,
        height: optimized.height,
        mimeType: 'image/jpeg',
        sizeBytes: optimized.bytes.length,
        albumId: albumId,
      );

      item.photo = photo;
      item.status = PhotoUploadStatus.done;
    } on DriveReauthorizationRequiredException {
      _driveReauthorizationRequired = true;
      _driveToken = null;
      item.status = PhotoUploadStatus.error;
      item.errorMessage = _reauthorizationMessage;
      item.failedDueToDriveReauth = true;
      batchErrorMessage = _reauthorizationMessage;
    } catch (error) {
      item.status = PhotoUploadStatus.error;
      // A 401 here always means the session JWT expired (spec02/A1.5's
      // known, out-of-scope gap: no automatic refresh yet) — surfaced
      // distinctly so the user knows to log back in, instead of the
      // generic message.
      item.errorMessage = error is ApiException && error.statusCode == 401
          ? _sessionExpiredMessage
          : 'No se pudo subir esta foto. Intenta de nuevo.';
    }
  }

  Future<DriveToken> _ensureDriveToken() async {
    if (_driveReauthorizationRequired) {
      throw const DriveReauthorizationRequiredException();
    }
    final cached = _driveToken;
    if (cached != null && !cached.isExpired) return cached;
    final token = await driveTokenApi.getDriveToken();
    _driveToken = token;
    return token;
  }

  static const _reauthorizationMessage =
      'Hace falta reconectar Google Drive para poder subir fotos.';
  static const _sessionExpiredMessage =
      'Tu sesión expiró. Vuelve a iniciar sesión.';
}
