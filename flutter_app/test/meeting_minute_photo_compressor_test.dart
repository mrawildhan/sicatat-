import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sicatat_flutter/data/reports/meeting_minute_photo_compressor.dart';

/// Camera-like picture: random pixels compress poorly as PNG, like a photo.
image.Image _photoLike(int width, int height) {
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
  return picture;
}

void main() {
  test(
    'foto notulen dinormalisasi sebagai JPEG kecil berukuran maksimum 1280',
    () {
      final Uint8List raw = Uint8List.fromList(
        image.encodePng(_photoLike(1800, 1200)),
      );

      final CompressedMeetingMinutePhoto compressed =
          MeetingMinutePhotoCompressor.compress(
            bytes: raw,
            fileName: 'Bukti Lapangan.PNG',
          );
      final image.Image? decoded = image.decodeJpg(compressed.bytes);

      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(1280));
      expect(decoded.height, lessThanOrEqualTo(1280));
      expect(compressed.fileName, 'Bukti Lapangan.jpg');
      expect(compressed.mimeType, 'image/jpeg');
      expect(compressed.bytes.lengthInBytes, lessThanOrEqualTo(600 * 1024));
      expect(compressed.bytes.lengthInBytes, lessThan(raw.lengthInBytes));
    },
  );

  test('foto yang sudah kecil tetap disimpan apa adanya', () {
    final image.Image source = image.Image(width: 900, height: 600);
    image.fill(source, color: image.ColorRgb8(11, 61, 46));
    final Uint8List raw = Uint8List.fromList(image.encodePng(source));

    final CompressedMeetingMinutePhoto compressed =
        MeetingMinutePhotoCompressor.compress(bytes: raw, fileName: 'logo.png');

    expect(compressed.bytes, same(raw));
    expect(compressed.fileName, 'logo.png');
    expect(compressed.mimeType, 'image/png');
  });

  test('foto dengan orientasi EXIF selalu dire-encode agar tidak miring', () {
    final image.Image source = _photoLike(40, 20);
    source.exif.imageIfd.orientation = 6;
    final Uint8List raw = Uint8List.fromList(image.encodeJpg(source));

    final CompressedMeetingMinutePhoto compressed =
        MeetingMinutePhotoCompressor.compress(
          bytes: raw,
          fileName: 'miring.jpg',
        );

    expect(compressed.mimeType, 'image/jpeg');
    final image.Image? decoded = image.decodeJpg(compressed.bytes);
    expect(decoded, isNotNull);
    // Orientation 6 turns the picture a quarter turn, so it stands upright.
    expect(decoded!.width, 20);
    expect(decoded.height, 40);
  });
}
