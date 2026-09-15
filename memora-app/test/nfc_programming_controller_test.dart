import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora_app/albums/nfc_programming_controller.dart';
import 'package:memora_app/albums/nfc_programming_service.dart';
import 'package:memora_app/albums/sharing_models.dart';
import 'package:nfc_manager/nfc_manager.dart' show NfcAvailability;

/// Tests `NfcProgrammingController`'s state machine (spec09-programar-nfc.md)
/// against a FAKE `NfcProgrammingService` — same pattern as
/// `AuthController`'s fakes in `test/auth_controller_test.dart` (subclass
/// and override, since none of `NfcProgrammingService`'s methods are
/// `final`): no real NFC session, no plugin channel, no device required.
/// Real hardware interaction (`nfc_manager`, an actual tag/reader) is NOT
/// testable here — see CLAUDE.md/README.md for what's verified in-device.
void main() {
  final tag = NfcQrTag(
    id: 'tag-1',
    albumId: 'album-1',
    type: NfcQrTagType.nfc,
    token: 'tok-1',
    status: NfcQrTagStatus.enabled,
    url: 'https://memora.app/n/tok-1',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  test('success: goes waitingForTag -> writing -> verifying -> success', () async {
    final service = _ScriptedNfcProgrammingService();
    final controller = NfcProgrammingController(service, tag);

    await controller.start();

    expect(controller.status, NfcProgrammingStatus.success);
    expect(service.reportedPhases, [
      NfcProgrammingPhase.writing,
      NfcProgrammingPhase.verifying,
    ]);
    expect(service.requestedUrls, [tag.url]);
  });

  test('a tag with existing content surfaces confirmingOverwrite and waits '
      'for resolveOverwriteConfirmation before writing', () async {
    final service = _ScriptedNfcProgrammingService(hasExistingContent: true);
    final controller = NfcProgrammingController(service, tag);

    final startFuture = controller.start();
    // Flushes the microtask queue: checkAvailability resolving, then every
    // purely-synchronous step chained after it (up to and including
    // confirmOverwrite being awaited inside the fake's writeUrl, which sets
    // status = confirmingOverwrite) all happen within that SAME microtask
    // turn — a single Duration.zero timer reliably runs only after the
    // ENTIRE microtask queue accumulated so far has drained.
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, NfcProgrammingStatus.confirmingOverwrite);
    expect(service.reportedPhases, isEmpty); // never reached writing yet

    controller.resolveOverwriteConfirmation(true);
    await startFuture;

    expect(controller.status, NfcProgrammingStatus.success);
    expect(service.reportedPhases, [
      NfcProgrammingPhase.writing,
      NfcProgrammingPhase.verifying,
    ]);
  });

  test('declining the overwrite confirmation surfaces as cancelled, never writes', () async {
    final service = _ScriptedNfcProgrammingService(hasExistingContent: true);
    final controller = NfcProgrammingController(service, tag);

    final startFuture = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, NfcProgrammingStatus.confirmingOverwrite);

    controller.resolveOverwriteConfirmation(false);
    await startFuture;

    expect(controller.status, NfcProgrammingStatus.cancelled);
    expect(service.reportedPhases, isEmpty);
  });

  test('cancel() while waiting for a tag reflects cancelled immediately, even '
      'if the underlying session never itself confirms it stopped (Android)', () async {
    final service = _HangingNfcProgrammingService();
    final controller = NfcProgrammingController(service, tag);

    final startFuture = controller.start();
    await Future<void>.delayed(Duration.zero);
    expect(controller.status, NfcProgrammingStatus.waitingForTag);

    await controller.cancel();

    expect(controller.status, NfcProgrammingStatus.cancelled);
    expect(service.cancelCallCount, 1);
    // The abandoned real session's future never settles on its own, but the
    // controller must not hang waiting for it — `start()` itself must
    // complete because of the Future.any race against the cancel signal.
    await startFuture.timeout(const Duration(seconds: 1));
  });

  test('errorNfcUnavailable when NFC is off/unsupported — never starts a session', () async {
    final service = _ScriptedNfcProgrammingService(
      availability: NfcAvailability.disabled,
    );
    final controller = NfcProgrammingController(service, tag);

    await controller.start();

    expect(controller.status, NfcProgrammingStatus.errorNfcUnavailable);
    expect(service.writeUrlCallCount, 0);
  });

  final errorCases = <String, Exception Function()>{
    'errorIncompatibleTag': () => const NfcIncompatibleTagException(),
    'errorTagLocked': () => const NfcTagLockedException(),
    'errorWriteFailed': () => const NfcWriteFailedException(),
    'errorVerificationFailed': () => const NfcVerificationFailedException(),
  };
  final expectedStatuses = <String, NfcProgrammingStatus>{
    'errorIncompatibleTag': NfcProgrammingStatus.errorIncompatibleTag,
    'errorTagLocked': NfcProgrammingStatus.errorTagLocked,
    'errorWriteFailed': NfcProgrammingStatus.errorWriteFailed,
    'errorVerificationFailed': NfcProgrammingStatus.errorVerificationFailed,
  };

  for (final caseName in errorCases.keys) {
    test('maps $caseName to its own distinct status/message, never a generic one', () async {
      final service = _ScriptedNfcProgrammingService(error: errorCases[caseName]!);
      final controller = NfcProgrammingController(service, tag);

      await controller.start();

      expect(controller.status, expectedStatuses[caseName]);
      expect(controller.statusMessage, isNotNull);
    });
  }

  test('every error/cancelled status has its own distinct message text', () {
    final messages = <NfcProgrammingStatus, String?>{};
    for (final status in NfcProgrammingStatus.values) {
      final controller = NfcProgrammingController(_ScriptedNfcProgrammingService(), tag)
        ..status = status;
      messages[status] = controller.statusMessage;
    }
    final nonNullMessages = messages.values.whereType<String>().toList();
    expect(nonNullMessages.toSet().length, nonNullMessages.length);
  });

  test('an unrecognized exception maps to errorUnknown, not silently to success', () async {
    final service = _ScriptedNfcProgrammingService(error: () => StateError('boom'));
    final controller = NfcProgrammingController(service, tag);

    await controller.start();

    expect(controller.status, NfcProgrammingStatus.errorUnknown);
  });

  test('retry() reuses the SAME tag/url, never creates a new one', () async {
    final service = _ScriptedNfcProgrammingService(
      error: () => const NfcWriteFailedException(),
    );
    final controller = NfcProgrammingController(service, tag);

    await controller.start();
    expect(controller.status, NfcProgrammingStatus.errorWriteFailed);

    service.error = null; // second attempt succeeds
    await controller.retry();

    expect(controller.status, NfcProgrammingStatus.success);
    expect(service.requestedUrls, [tag.url, tag.url]);
    expect(controller.tag, same(tag));
  });

  group('lockReadOnly (spec09 P2 — separate, explicit, platform-gated)', () {
    test('is a no-op where the platform does not support it (iOS)', () async {
      final service = _ScriptedNfcProgrammingService(supportsLock: false);
      final controller = NfcProgrammingController(service, tag);

      expect(controller.supportsReadOnlyLock, isFalse);
      await controller.lockReadOnly();

      expect(service.lockCallCount, 0);
      expect(controller.lockedReadOnly, isFalse);
      expect(controller.lockReadOnlyErrorMessage, isNull);
    });

    test('locks successfully where supported (Android)', () async {
      final service = _ScriptedNfcProgrammingService(supportsLock: true);
      final controller = NfcProgrammingController(service, tag);

      await controller.lockReadOnly();

      expect(service.lockCallCount, 1);
      expect(controller.lockedReadOnly, isTrue);
      expect(controller.isLockingReadOnly, isFalse);
      expect(controller.lockReadOnlyErrorMessage, isNull);
    });

    test('surfaces a specific message for an incompatible tag', () async {
      final service = _ScriptedNfcProgrammingService(
        supportsLock: true,
        lockError: const NfcIncompatibleTagException(),
      );
      final controller = NfcProgrammingController(service, tag);

      await controller.lockReadOnly();

      expect(controller.lockedReadOnly, isFalse);
      expect(controller.lockReadOnlyErrorMessage, contains('no es compatible'));
    });

    test('surfaces a generic-but-present message for any other lock failure', () async {
      final service = _ScriptedNfcProgrammingService(
        supportsLock: true,
        lockError: StateError('native failure'),
      );
      final controller = NfcProgrammingController(service, tag);

      await controller.lockReadOnly();

      expect(controller.lockedReadOnly, isFalse);
      expect(controller.lockReadOnlyErrorMessage, isNotNull);
    });
  });
}

/// A scriptable fake — configure [availability]/[hasExistingContent]/[error]
/// before calling `start()`/`retry()` to simulate one attempt's outcome, and
/// read [requestedUrls]/[reportedPhases]/[writeUrlCallCount] afterwards.
class _ScriptedNfcProgrammingService extends NfcProgrammingService {
  _ScriptedNfcProgrammingService({
    this.availability = NfcAvailability.enabled,
    this.hasExistingContent = false,
    this.error,
    this.supportsLock = false,
    this.lockError,
  });

  final NfcAvailability availability;
  final bool hasExistingContent;

  /// Mutable (not final) so `retry()` tests can reconfigure a scripted
  /// failure into a success between calls.
  Object Function()? error;

  final bool supportsLock;
  final Object? lockError;

  final List<String> requestedUrls = [];
  final List<NfcProgrammingPhase> reportedPhases = [];
  int writeUrlCallCount = 0;
  int lockCallCount = 0;

  @override
  bool get supportsReadOnlyLock => supportsLock;

  @override
  Future<NfcAvailability> checkAvailability() async => availability;

  @override
  Future<void> writeUrl({
    required String url,
    required Future<bool> Function(bool hasExistingContent) confirmOverwrite,
    void Function(NfcProgrammingPhase phase)? onPhase,
  }) async {
    writeUrlCallCount++;
    requestedUrls.add(url);

    final confirmed = await confirmOverwrite(hasExistingContent);
    if (!confirmed) throw const NfcCancelledException();

    onPhase?.call(NfcProgrammingPhase.writing);
    reportedPhases.add(NfcProgrammingPhase.writing);
    onPhase?.call(NfcProgrammingPhase.verifying);
    reportedPhases.add(NfcProgrammingPhase.verifying);

    final scriptedError = error;
    if (scriptedError != null) throw scriptedError();
  }

  @override
  Future<void> cancel() async {}

  @override
  Future<void> lockReadOnly() async {
    lockCallCount++;
    final scriptedLockError = lockError;
    if (scriptedLockError != null) throw scriptedLockError;
  }
}

/// Simulates Android's real constraint: a session this app stops itself
/// (via `cancel()`) never resolves `writeUrl`'s future on its own — the
/// controller must not depend on it ever completing to reflect a cancel.
class _HangingNfcProgrammingService extends NfcProgrammingService {
  final Completer<void> _neverCompletes = Completer<void>();
  int cancelCallCount = 0;

  @override
  Future<NfcAvailability> checkAvailability() async => NfcAvailability.enabled;

  @override
  Future<void> writeUrl({
    required String url,
    required Future<bool> Function(bool hasExistingContent) confirmOverwrite,
    void Function(NfcProgrammingPhase phase)? onPhase,
  }) => _neverCompletes.future;

  @override
  Future<void> cancel() async {
    cancelCallCount++;
    // Deliberately does NOT complete `_neverCompletes` — on real Android
    // hardware, nothing tells this app's Dart side that the native session
    // actually stopped; `NfcProgrammingController.cancel()` must not rely on
    // it doing so.
  }
}
