import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

import 'nfc_programming_service.dart';
import 'sharing_models.dart';

/// Every state this app's NFC-programming flow (spec09-programar-nfc.md) can
/// be in. Deliberately one enum with a distinct value per error CASE
/// (matches the spec's checklist verbatim: "esperando tag, escribiendo,
/// verificando, éxito, error por caso, cancelado") rather than a single
/// generic `error` + a message string — see [NfcProgrammingController.statusMessage]
/// for why that matters (never a generic message for these).
enum NfcProgrammingStatus {
  idle,
  checkingAvailability,
  waitingForTag,
  confirmingOverwrite,
  writing,
  verifying,
  success,
  cancelled,
  errorIncompatibleTag,
  errorTagLocked,
  errorWriteFailed,
  errorVerificationFailed,
  errorNfcUnavailable,
  errorUnknown,
}

/// Drives ONE [NfcQrTag]'s physical programming attempt (`ChangeNotifier`,
/// same pattern as every other controller in this app). Owns:
///
/// - the write/verify flow ([start]/[retry]/[cancel]/[resolveOverwriteConfirmation]),
///   all state transitions of [NfcProgrammingStatus];
/// - the SEPARATE, explicit "bloquear a solo lectura" action ([lockReadOnly])
///   — spec09 P2: never triggered automatically, never mixed with the write
///   flow above, and only meaningful where [supportsReadOnlyLock] is true.
///
/// Does NOT own creating the tag (`AlbumsController.createNfcQrTag` already
/// did that before this controller exists — P1) nor disabling it in the
/// backend (`AlbumsController.disableNfcQrTag`, P3's "desiste" path) — both
/// stay the screen's responsibility, calling back into `AlbumsController`
/// directly, to avoid this controller depending on it for something outside
/// its job (driving one NFC session).
class NfcProgrammingController extends ChangeNotifier {
  NfcProgrammingController(this._service, this.tag);

  final NfcProgrammingService _service;

  /// The tag whose `url` this controller writes — reused as-is across
  /// [retry] calls (P3: "reintentar con el MISMO token/url").
  final NfcQrTag tag;

  NfcProgrammingStatus status = NfcProgrammingStatus.idle;

  /// Bumped on every [start]/[retry]/[cancel] call. An in-flight attempt's
  /// continuation checks this before applying its result, so a stale attempt
  /// (superseded by a cancel or a fresh retry) can never clobber a newer
  /// one's state — see [start]'s doc comment.
  int _generation = 0;

  Completer<void>? _cancelSignal;
  Completer<bool>? _overwriteConfirmation;

  bool get supportsReadOnlyLock => _service.supportsReadOnlyLock;
  bool isLockingReadOnly = false;
  bool lockedReadOnly = false;
  String? lockReadOnlyErrorMessage;

  bool get isRunning =>
      status == NfcProgrammingStatus.checkingAvailability ||
      status == NfcProgrammingStatus.waitingForTag ||
      status == NfcProgrammingStatus.confirmingOverwrite ||
      status == NfcProgrammingStatus.writing ||
      status == NfcProgrammingStatus.verifying;

  bool get isError =>
      status != NfcProgrammingStatus.idle &&
      status != NfcProgrammingStatus.success &&
      !isRunning;

  /// Starts (or restarts) one programming attempt for [tag]. Safe to call
  /// again after a failure/cancellation — see [retry], its only caller
  /// besides the screen's initial call.
  ///
  /// Cancellation races the underlying [NfcProgrammingService.writeUrl]
  /// future against [_cancelSignal] with `Future.any` rather than relying on
  /// [NfcProgrammingService.cancel] alone to resolve it: Android's
  /// `NfcAdapter` gives this app no "the session was stopped" callback for a
  /// session it stops itself (only iOS's native sheet reports a user-cancel
  /// this way), so without the race, tapping "Cancelar" on Android would
  /// leave this controller hanging in [NfcProgrammingStatus.waitingForTag]
  /// forever even though the OS-level session did stop. `Future.any`
  /// internally attaches a listener to BOTH futures, so the losing one (here,
  /// almost always the real [writeUrl] call, abandoned mid-flight) is never
  /// left as an unhandled/unlistened future — no `Future.ignore()` needed,
  /// unlike the `late final`/reassigned-field cases documented elsewhere in
  /// this app's CLAUDE.md.
  Future<void> start() async {
    final generation = ++_generation;
    _cancelSignal = Completer<void>();
    _overwriteConfirmation = null;

    status = NfcProgrammingStatus.checkingAvailability;
    notifyListeners();

    final availability = await _service.checkAvailability();
    if (generation != _generation) return;
    if (availability != NfcAvailability.enabled) {
      status = NfcProgrammingStatus.errorNfcUnavailable;
      notifyListeners();
      return;
    }

    status = NfcProgrammingStatus.waitingForTag;
    notifyListeners();

    try {
      await Future.any<void>([
        _service.writeUrl(
          url: tag.url,
          confirmOverwrite: (hasExistingContent) =>
              _handleConfirmOverwrite(generation, hasExistingContent),
          onPhase: (phase) => _handlePhase(generation, phase),
        ),
        _cancelSignal!.future.then((_) => throw const NfcCancelledException()),
      ]);
      if (generation != _generation) return;
      status = NfcProgrammingStatus.success;
    } catch (error) {
      if (generation != _generation) return;
      status = _statusFor(error);
    }
    notifyListeners();
  }

  Future<bool> _handleConfirmOverwrite(int generation, bool hasExistingContent) {
    if (!hasExistingContent) return Future.value(true);
    if (generation != _generation) return Future.value(false);
    status = NfcProgrammingStatus.confirmingOverwrite;
    notifyListeners();
    _overwriteConfirmation = Completer<bool>();
    return _overwriteConfirmation!.future;
  }

  void _handlePhase(int generation, NfcProgrammingPhase phase) {
    if (generation != _generation) return;
    status = switch (phase) {
      NfcProgrammingPhase.writing => NfcProgrammingStatus.writing,
      NfcProgrammingPhase.verifying => NfcProgrammingStatus.verifying,
    };
    notifyListeners();
  }

  /// Called by the UI once the user answers the "this tag already has data,
  /// overwrite it?" dialog shown while [status] is
  /// [NfcProgrammingStatus.confirmingOverwrite]. A `false` answer surfaces as
  /// [NfcProgrammingStatus.cancelled] once the underlying write call unwinds
  /// (via [NfcCancelledException]) — declining to overwrite IS a cancellation
  /// of this attempt, not a distinct error case (the spec's error taxonomy
  /// doesn't call for a sixth case here).
  void resolveOverwriteConfirmation(bool confirmed) {
    final completer = _overwriteConfirmation;
    if (completer == null || completer.isCompleted) return;
    completer.complete(confirmed);
  }

  /// Same MEMORA token/url, same [NfcQrTag] — a brand-new NFC session (P3:
  /// "reintentar con el mismo token/url"). Never creates a new backend tag.
  Future<void> retry() => start();

  /// User-initiated cancel while waiting for a tag or mid-overwrite-prompt.
  /// Immediately reflects [NfcProgrammingStatus.cancelled] regardless of
  /// whether the underlying native session ever confirms it stopped (see
  /// [start]'s doc comment on why `Future.any` is needed for this to work
  /// reliably on Android).
  Future<void> cancel() async {
    final generation = _generation;
    final overwriteCompleter = _overwriteConfirmation;
    if (overwriteCompleter != null && !overwriteCompleter.isCompleted) {
      overwriteCompleter.complete(false);
    }
    _cancelSignal?.complete();
    unawaited(_service.cancel());
    if (generation == _generation && isRunning) {
      status = NfcProgrammingStatus.cancelled;
      notifyListeners();
    }
  }

  /// Spec09 P2: a SEPARATE, explicit action, never automatic and never part
  /// of [start]'s flow. The screen is responsible for showing the
  /// irreversibility warning and getting the user's explicit confirmation
  /// BEFORE calling this — and for never offering it at all where
  /// [supportsReadOnlyLock] is false (iOS).
  Future<void> lockReadOnly() async {
    if (!supportsReadOnlyLock) return;
    isLockingReadOnly = true;
    lockReadOnlyErrorMessage = null;
    notifyListeners();
    try {
      await _service.lockReadOnly();
      lockedReadOnly = true;
    } on NfcIncompatibleTagException {
      lockReadOnlyErrorMessage =
          'La etiqueta detectada no es compatible con el bloqueo.';
    } catch (_) {
      lockReadOnlyErrorMessage = 'No se pudo bloquear la etiqueta. Intenta de nuevo.';
    }
    isLockingReadOnly = false;
    notifyListeners();
  }

  NfcProgrammingStatus _statusFor(Object error) {
    if (error is NfcCancelledException) return NfcProgrammingStatus.cancelled;
    if (error is NfcIncompatibleTagException) {
      return NfcProgrammingStatus.errorIncompatibleTag;
    }
    if (error is NfcTagLockedException) return NfcProgrammingStatus.errorTagLocked;
    if (error is NfcWriteFailedException) {
      return NfcProgrammingStatus.errorWriteFailed;
    }
    if (error is NfcVerificationFailedException) {
      return NfcProgrammingStatus.errorVerificationFailed;
    }
    return NfcProgrammingStatus.errorUnknown;
  }

  /// A fixed, distinct, user-facing message per [status] — deliberately
  /// never a shared generic string for the error cases (spec09: "errores por
  /// caso, mensajes distintos y claros"). `null` while idle/successful,
  /// where the screen shows its own dedicated UI instead of a message.
  String? get statusMessage => switch (status) {
    NfcProgrammingStatus.idle => null,
    NfcProgrammingStatus.checkingAvailability => 'Comprobando el NFC del teléfono...',
    NfcProgrammingStatus.waitingForTag =>
      'Acerca la etiqueta NFC a la parte trasera del teléfono.',
    NfcProgrammingStatus.confirmingOverwrite =>
      'Esta etiqueta ya tiene datos guardados.',
    NfcProgrammingStatus.writing => 'Escribiendo la etiqueta...',
    NfcProgrammingStatus.verifying => 'Verificando la escritura...',
    NfcProgrammingStatus.success => null,
    NfcProgrammingStatus.cancelled => 'La programación fue cancelada.',
    NfcProgrammingStatus.errorIncompatibleTag =>
      'Esta etiqueta no es compatible (no es NDEF/Tipo 2).',
    NfcProgrammingStatus.errorTagLocked =>
      'Esta etiqueta está bloqueada y no admite escritura.',
    NfcProgrammingStatus.errorWriteFailed => 'No se pudo escribir en la etiqueta.',
    NfcProgrammingStatus.errorVerificationFailed =>
      'Se escribió la etiqueta, pero no se pudo verificar su contenido — '
          'no se considera programada.',
    NfcProgrammingStatus.errorNfcUnavailable =>
      'El NFC no está disponible o está desactivado en este dispositivo.',
    NfcProgrammingStatus.errorUnknown => 'Ocurrió un error al programar la etiqueta.',
  };
}
