import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sicatat_flutter/data/reports/reminder_evidence_preparer.dart';

/// Camera-like picture: random pixels compress poorly as PNG, like a photo.
Uint8List _photoLikePng(int width, int height) {
  final image.Image picture = image.Image(width: width, height: height);
  int seed = 7;
  int next() => seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      // High bits: the low bits of this generator repeat every 256 steps.
      picture.setPixelRgb(
        x,
        y,
        (next() >> 16) & 0xff,
        (next() >> 16) & 0xff,
        (next() >> 16) & 0xff,
      );
    }
  }
  return Uint8List.fromList(image.encodePng(picture));
}

/// Flat picture: tiny as PNG, so re-encoding would only make it bigger.
Uint8List _flatPng(int width, int height) {
  final image.Image picture = image.Image(width: width, height: height);
  image.fill(picture, color: image.ColorRgb8(11, 61, 46));
  return Uint8List.fromList(image.encodePng(picture));
}

void main() {
  test('photos are compressed to a smaller JPEG within 1280 px', () {
    final Uint8List png = _photoLikePng(1800, 1200);
    final PreparedReminderEvidence prepared = ReminderEvidencePreparer.prepare(
      fileName: 'bukti.png',
      bytes: png,
    );
    expect(prepared.mimeType, 'image/jpeg');
    expect(prepared.name, 'bukti.jpg');
    expect(prepared.bytes.length, lessThan(png.length));
    final image.Image? decoded = image.decodeImage(prepared.bytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, lessThanOrEqualTo(1280));
    expect(decoded.height, lessThanOrEqualTo(1280));
  });

  test('an already compact picture keeps its original bytes', () {
    final Uint8List png = _flatPng(900, 600);
    final PreparedReminderEvidence prepared = ReminderEvidencePreparer.prepare(
      fileName: 'logo.png',
      bytes: png,
    );
    expect(prepared.mimeType, 'image/png');
    expect(prepared.name, 'logo.png');
    expect(prepared.bytes, same(png));
  });

  test('small PDFs are kept as they are', () {
    final Uint8List pdf = Uint8List.fromList('%PDF-1.4 test'.codeUnits);
    final PreparedReminderEvidence prepared = ReminderEvidencePreparer.prepare(
      fileName: 'surat.PDF',
      bytes: pdf,
    );
    expect(prepared.mimeType, 'application/pdf');
    expect(prepared.bytes, same(pdf));
  });

  test('PDFs above 2 MB and unsupported files are refused', () {
    expect(
      () => ReminderEvidencePreparer.prepare(
        fileName: 'besar.pdf',
        bytes: Uint8List(ReminderEvidencePreparer.maxPdfBytes + 1),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ReminderEvidencePreparer.prepare(
        fileName: 'catatan.txt',
        bytes: Uint8List(10),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => ReminderEvidencePreparer.prepare(
        fileName: 'rusak.jpg',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
      throwsA(
        isA<FormatException>().having(
          (FormatException error) => error.message,
          'message',
          'rusak.jpg tidak dapat dibaca sebagai gambar.',
        ),
      ),
    );
  });
}
