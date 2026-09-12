import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:sicatat_flutter/data/reports/meeting_minute_photo_compressor.dart';

void main() {
  test(
    'foto notulen dinormalisasi sebagai JPEG kecil berukuran maksimum 1280',
    () {
      final image.Image source = image.Image(width: 1800, height: 1200);
      for (int y = 0; y < source.height; y += 1) {
        for (int x = 0; x < source.width; x += 1) {
          source.setPixelRgba(x, y, x % 256, y % 256, (x + y) % 256, 255);
        }
      }
      final Uint8List raw = Uint8List.fromList(image.encodePng(source));

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
      expect(compressed.bytes.lengthInBytes, lessThanOrEqualTo(600 * 1024));
    },
  );
}
