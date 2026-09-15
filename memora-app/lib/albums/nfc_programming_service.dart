import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager/nfc_manager_ios.dart' show NfcReaderErrorCodeIos;
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

/// Native NFC read/write for spec09-programar-nfc.md, wrapping `nfc_manager`
/// (4.x — a very different, split-by-concern API from older versions: no
/// more `NfcManager.instance.startSession(onDiscovered:)` + a single
/// `Ndef.from(tag)` helper baked into the core package; that unified `Ndef`
/// abstraction now lives in the separate `nfc_manager_ndef` package, which
/// this app also depends on specifically for it — see this app's CLAUDE.md
/// for the exact versions resolved and why).
///
/// **Hard rule (spec09):** the ONLY thing ever written to a tag is a single
/// well-known NFC Forum URI record (RTD-URI) containing the album's `url`
/// (`https://memora.app/n/{token}`) — never photos, album name, internal ids
/// or any other PII. `ndef_record` 1.4.x ships no URI-record builder/decoder
/// (unlike the old `NdefRecord.createUri` helper from pre-4.0 `nfc_manager`),
/// so [buildUriRecord]/[messageHasVerifiedUri] implement the NFC Forum URI
/// Record Type Definition ourselves — see their doc comments. Both are pure,
/// device-free functions, unit-tested directly in
/// `test/nfc_programming_service_test.dart`.
///
/// None of the instance methods here are `final` (same pattern as
/// `GoogleAuthService`/`AuthApi` in spec06's CLAUDE.md note): a test fake
/// subclasses this class and overrides them, so `NfcProgrammingController`
/// is testable without ever touching a real NFC session.
class NfcProgrammingService {
  const NfcProgrammingService();

  /// Whether this platform can lock a tag to read-only in a way this app
  /// considers reliable enough to offer (spec09 P2 + normative requirement).
  /// Android's `NfcAdapter`/`Ndef.makeReadOnly()` is well-established; Core
  /// NFC (iOS) DOES technically expose an equivalent (`writeLock`, forwarded
  /// by `nfc_manager_ndef`'s unified `Ndef.writeLock()` on both platforms —
  /// see its source), but the spec's own compatibility analysis is explicit
  /// that iOS's version isn't reliable across tag hardware, so the app never
  /// offers the action there even though the plugin *could* attempt it.
  bool get supportsReadOnlyLock => defaultTargetPlatform == TargetPlatform.android;

  Future<NfcAvailability> checkAvailability() => NfcManager.instance.checkAvailability();

  /// Runs ONE full programming attempt inside a single NFC session: waits
  /// for a tag, reads its current NDEF content, asks [confirmOverwrite]
  /// (called with whether the tag already had content) before writing if
  /// needed, writes the URI record, then re-reads and verifies it round
  /// -trips correctly — all before the session is stopped. [onPhase] is an
  /// optional progress callback (fired for [NfcProgrammingPhase.writing] and
  /// [NfcProgrammingPhase.verifying]) so a caller can reflect those as
  /// distinct UI states without this method itself needing to be a
  /// `ChangeNotifier`.
  ///
  /// Throws [NfcCancelledException] (user declined the overwrite prompt, or
  /// cancelled from the native iOS sheet), [NfcIncompatibleTagException]
  /// (not NDEF/Type 2), [NfcTagLockedException] (NDEF but not writable),
  /// [NfcWriteFailedException], or [NfcVerificationFailedException]. Never
  /// swallows an error silently — a caller that doesn't see one of these can
  /// assume the tag now carries [url].
  Future<void> writeUrl({
    required String url,
    required Future<bool> Function(bool hasExistingContent) confirmOverwrite,
    void Function(NfcProgrammingPhase phase)? onPhase,
  }) async {
    final completer = Completer<void>();
    var settled = false;
    void settle(void Function() action) {
      if (settled) return;
      settled = true;
      action();
    }

    await NfcManager.instance.startSession(
      pollingOptions: const {
        // Type 2 (MIFARE Ultralight, the spec's reference hardware) and
        // Type 5 tags both support NDEF read/write — iso18092 (FeliCa) is
        // deliberately excluded, it's not an NDEF-URI use case this spec
        // targets.
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
      },
      alertMessageIos: 'Acerca la etiqueta NFC al teléfono.',
      onDiscovered: (tag) async {
        try {
          await _writeAndVerify(
            tag,
            url: url,
            confirmOverwrite: confirmOverwrite,
            onPhase: onPhase,
          );
          await NfcManager.instance.stopSession(
            alertMessageIos: 'Etiqueta programada.',
          );
          settle(completer.complete);
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession(
            errorMessageIos: 'No se pudo programar la etiqueta.',
          );
          settle(() => completer.completeError(error, stackTrace));
        }
      },
      onSessionErrorIos: (error) {
        // Only reachable on iOS — the native sheet was dismissed/cancelled
        // or the session otherwise died before onDiscovered ran (or after,
        // in which case `settle` below is already a no-op).
        settle(() {
          if (error.code ==
              NfcReaderErrorCodeIos.readerSessionInvalidationErrorUserCanceled) {
            completer.completeError(const NfcCancelledException());
          } else {
            completer.completeError(NfcWriteFailedException(error.message));
          }
        });
      },
    );

    return completer.future;
  }

  Future<void> _writeAndVerify(
    NfcTag tag, {
    required String url,
    required Future<bool> Function(bool hasExistingContent) confirmOverwrite,
    void Function(NfcProgrammingPhase phase)? onPhase,
  }) async {
    final ndef = Ndef.from(tag);
    if (ndef == null) throw const NfcIncompatibleTagException();
    if (!ndef.isWritable) throw const NfcTagLockedException();

    final existing = ndef.cachedMessage;
    final hasExistingContent = existing != null && existing.records.isNotEmpty;
    final confirmed = await confirmOverwrite(hasExistingContent);
    if (!confirmed) throw const NfcCancelledException();

    onPhase?.call(NfcProgrammingPhase.writing);
    final message = NdefMessage(records: [buildUriRecord(url)]);
    try {
      await ndef.write(message: message);
    } catch (error) {
      throw NfcWriteFailedException(error.toString());
    }

    onPhase?.call(NfcProgrammingPhase.verifying);
    NdefMessage? readBack;
    try {
      readBack = await ndef.read();
    } catch (error) {
      throw NfcVerificationFailedException(error.toString());
    }
    if (!messageHasVerifiedUri(readBack, url)) {
      throw const NfcVerificationFailedException();
    }
  }

  /// Best-effort: asks the native session to stop. On Android this is the
  /// ONLY way this app can express "the user tapped Cancelar while waiting
  /// for a tag" — there is no equivalent to iOS's `onSessionErrorIos`
  /// user-cancel callback there, so [NfcProgrammingController] does not rely
  /// on this call itself resolving [writeUrl]'s future; it races it instead
  /// (see the controller's doc comment).
  Future<void> cancel() =>
      NfcManager.instance.stopSession(errorMessageIos: 'Cancelado.');

  /// Starts a SEPARATE NFC session (spec09 P2: never part of [writeUrl],
  /// always its own explicit action) to permanently lock a tag to read-only.
  /// Throws [NfcReadOnlyLockUnsupportedException] if [supportsReadOnlyLock]
  /// is false — a safety net; the UI must never surface this action on a
  /// platform where it isn't supported in the first place.
  Future<void> lockReadOnly() async {
    if (!supportsReadOnlyLock) {
      throw const NfcReadOnlyLockUnsupportedException();
    }
    final completer = Completer<void>();
    var settled = false;
    void settle(void Function() action) {
      if (settled) return;
      settled = true;
      action();
    }

    await NfcManager.instance.startSession(
      pollingOptions: const {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null) throw const NfcIncompatibleTagException();
          await ndef.writeLock();
          await NfcManager.instance.stopSession();
          settle(completer.complete);
        } catch (error, stackTrace) {
          await NfcManager.instance.stopSession();
          settle(() => completer.completeError(error, stackTrace));
        }
      },
    );
    return completer.future;
  }
}

/// Mid-attempt progress reported by [NfcProgrammingService.writeUrl] — lets
/// [NfcProgrammingController] surface "escribiendo"/"verificando" as
/// distinct states without the service itself being a `ChangeNotifier`.
enum NfcProgrammingPhase { writing, verifying }

/// NFC Forum URI Record Type Definition (RTD-URI) abbreviation codes this
/// app knows how to produce/parse — enough to round-trip the `https://` URLs
/// the backend gives it; not a general-purpose implementation of every code
/// in the spec (tel:, mailto:, etc. are unused by this app but included
/// since they cost nothing extra and keep decoding correct for tags written
/// by other tools).
const _uriAbbreviations = <int, String>{
  0x01: 'http://www.',
  0x02: 'https://www.',
  0x03: 'http://',
  0x04: 'https://',
  0x05: 'tel:',
  0x06: 'mailto:',
};

/// Builds the single NDEF record this app ever writes to a tag: a
/// well-known-type URI record (TNF = well-known, type = `'U'`) whose payload
/// is `[abbreviation code byte, ...UTF-8 bytes of the rest of the URL]` —
/// the standard NFC Forum URI encoding, which lets a phone/reader that scans
/// the tag resolve it as a normal link. Picks the longest matching
/// abbreviation prefix (checked longest-first so `https://www.` is never
/// shadowed by `https://`) to keep the payload minimal, falling back to the
/// "no abbreviation" code (`0x00`) with the full string if [url] doesn't
/// start with any known prefix.
NdefRecord buildUriRecord(String url) {
  final sortedPrefixes = _uriAbbreviations.entries.toList()
    ..sort((a, b) => b.value.length.compareTo(a.value.length));
  for (final entry in sortedPrefixes) {
    if (url.startsWith(entry.value)) {
      final rest = url.substring(entry.value.length);
      return NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: Uint8List.fromList([0x55]),
        identifier: Uint8List(0),
        payload: Uint8List.fromList([entry.key, ...utf8.encode(rest)]),
      );
    }
  }
  return NdefRecord(
    typeNameFormat: TypeNameFormat.wellKnown,
    type: Uint8List.fromList([0x55]),
    identifier: Uint8List(0),
    payload: Uint8List.fromList([0x00, ...utf8.encode(url)]),
  );
}

/// Decodes a single URI record's payload back into a full URL string
/// (re-prepending its abbreviation prefix), or `null` if [record] isn't a
/// well-known-type URI record (`'U'`) at all.
String? decodeUriRecord(NdefRecord record) {
  if (record.typeNameFormat != TypeNameFormat.wellKnown) return null;
  if (record.type.length != 1 || record.type[0] != 0x55) return null;
  if (record.payload.isEmpty) return '';
  final code = record.payload[0];
  final rest = utf8.decode(record.payload.sublist(1));
  final prefix = code == 0x00 ? '' : (_uriAbbreviations[code] ?? '');
  return '$prefix$rest';
}

/// Whether [message] contains a URI record that decodes to EXACTLY
/// [expectedUrl] (string-for-string) — used for the post-write verification
/// step spec09 requires ("re-leer y verificar que el NDEF escrito coincide
/// con la url"). Deliberately strict equality, not a prefix/contains check —
/// a partially-written or truncated tag must fail verification.
bool messageHasVerifiedUri(NdefMessage? message, String expectedUrl) {
  if (message == null) return false;
  for (final record in message.records) {
    if (decodeUriRecord(record) == expectedUrl) return true;
  }
  return false;
}

/// The user declined to overwrite a tag that already had content, or
/// cancelled the native NFC prompt (iOS) / this app's own "Cancelar" while
/// waiting for a tag (Android has no native cancel signal for that case —
/// see [NfcProgrammingService.cancel]'s doc comment).
class NfcCancelledException implements Exception {
  const NfcCancelledException();
}

/// The detected tag isn't NDEF-formatted, or isn't a type this app's NDEF
/// layer supports (`Ndef.from(tag)` returned `null`) — e.g. not NFC Forum
/// Type 2/MIFARE Ultralight.
class NfcIncompatibleTagException implements Exception {
  const NfcIncompatibleTagException();
}

/// The tag is NDEF but reports `isWritable == false` — already locked to
/// read-only (by this app or another tool), or otherwise not modifiable.
class NfcTagLockedException implements Exception {
  const NfcTagLockedException();
}

/// The native write call itself failed (I/O error, tag moved away
/// mid-write, unexpected platform error). [detail] is for local debugging
/// only — never logged with the `url`/token attached (see this app's
/// CLAUDE.md on not logging `NfcQrTag.token`/`url`).
class NfcWriteFailedException implements Exception {
  const NfcWriteFailedException([this.detail]);
  final String? detail;
}

/// The write call itself reported success, but the immediate re-read
/// afterwards didn't come back with the expected URL — per spec09, this
/// means the programming is NOT considered successful.
class NfcVerificationFailedException implements Exception {
  const NfcVerificationFailedException([this.detail]);
  final String? detail;
}

/// Thrown by [NfcProgrammingService.lockReadOnly] if called on a platform
/// where [NfcProgrammingService.supportsReadOnlyLock] is `false`. A safety
/// net only — the UI must never present the "Bloquear como solo lectura"
/// action there in the first place (spec09's normative requirement).
class NfcReadOnlyLockUnsupportedException implements Exception {
  const NfcReadOnlyLockUnsupportedException();
}
