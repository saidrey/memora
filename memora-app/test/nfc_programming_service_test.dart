import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora_app/albums/nfc_programming_service.dart';
import 'package:nfc_manager/ndef_record.dart';

/// Pure-logic tests for spec09-programar-nfc.md's NDEF URI record
/// encode/decode/verify helpers — no NFC hardware or plugin channel
/// involved, `NdefMessage`/`NdefRecord`/`TypeNameFormat` are plain Dart
/// classes from `package:ndef_record`. Real hardware interaction
/// (`NfcManager.instance.startSession`, an actual tag) is NOT testable here
/// — see this app's CLAUDE.md / README.md for what's verified in-device
/// instead.
void main() {
  group('buildUriRecord', () {
    test('encodes an https URL with the https:// abbreviation code', () {
      final record = buildUriRecord('https://memora.app/n/abc123');

      expect(record.typeNameFormat, TypeNameFormat.wellKnown);
      expect(record.type, Uint8List.fromList([0x55])); // 'U'
      expect(record.payload[0], 0x04); // https://
      expect(
        String.fromCharCodes(record.payload.sublist(1)),
        'memora.app/n/abc123',
      );
    });

    test('encodes an http URL with the http:// abbreviation code', () {
      final record = buildUriRecord('http://memora.app/n/abc123');

      expect(record.payload[0], 0x03); // http://
      expect(
        String.fromCharCodes(record.payload.sublist(1)),
        'memora.app/n/abc123',
      );
    });

    test('prefers the longer https://www. prefix over https://', () {
      final record = buildUriRecord('https://www.memora.app/n/abc123');

      expect(record.payload[0], 0x02); // https://www.
      expect(
        String.fromCharCodes(record.payload.sublist(1)),
        'memora.app/n/abc123',
      );
    });

    test('falls back to no-abbreviation (0x00) for an unrecognized scheme', () {
      final record = buildUriRecord('ftp://memora.app/n/abc123');

      expect(record.payload[0], 0x00);
      expect(
        String.fromCharCodes(record.payload.sublist(1)),
        'ftp://memora.app/n/abc123',
      );
    });

    test('writes ONLY the url — no other fields end up in type/identifier', () {
      final record = buildUriRecord('https://memora.app/n/abc123');

      expect(record.identifier, isEmpty);
      expect(record.type.length, 1);
    });
  });

  group('decodeUriRecord / messageHasVerifiedUri', () {
    test('round-trips a URL built by buildUriRecord', () {
      const url = 'https://memora.app/n/abc123';
      final record = buildUriRecord(url);

      expect(decodeUriRecord(record), url);
    });

    test('round-trips every abbreviation prefix this app might encounter', () {
      for (final url in [
        'https://memora.app/n/x',
        'http://memora.app/n/x',
        'https://www.memora.app/n/x',
        'http://www.memora.app/n/x',
        'ftp://memora.app/n/x',
      ]) {
        expect(decodeUriRecord(buildUriRecord(url)), url, reason: url);
      }
    });

    test('returns null for a non-URI (e.g. plain text) record', () {
      final textRecord = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: Uint8List.fromList('T'.codeUnits),
        identifier: Uint8List(0),
        payload: Uint8List.fromList('hello'.codeUnits),
      );

      expect(decodeUriRecord(textRecord), isNull);
    });

    test('messageHasVerifiedUri matches only an exact string match', () {
      const url = 'https://memora.app/n/abc123';
      final message = NdefMessage(records: [buildUriRecord(url)]);

      expect(messageHasVerifiedUri(message, url), isTrue);
      expect(messageHasVerifiedUri(message, '$url-tampered'), isFalse);
      expect(messageHasVerifiedUri(message, url.substring(0, url.length - 1)), isFalse);
    });

    test('messageHasVerifiedUri is false for null or empty messages', () {
      expect(messageHasVerifiedUri(null, 'https://memora.app/n/x'), isFalse);
      expect(
        messageHasVerifiedUri(const NdefMessage(records: []), 'https://memora.app/n/x'),
        isFalse,
      );
    });

    test('messageHasVerifiedUri ignores unrelated records but still finds the URI one', () {
      const url = 'https://memora.app/n/abc123';
      final textRecord = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: Uint8List.fromList('T'.codeUnits),
        identifier: Uint8List(0),
        payload: Uint8List.fromList('unrelated'.codeUnits),
      );
      final message = NdefMessage(records: [textRecord, buildUriRecord(url)]);

      expect(messageHasVerifiedUri(message, url), isTrue);
    });
  });
}
