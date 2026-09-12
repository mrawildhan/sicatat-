import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Produces a compact JPEG suitable for the private Notulen Rapat bucket.
///
/// The storage plan is limited, so every evidence photo is normalized before
/// upload: EXIF orientation is applied, the longest side is capped, and JPEG
/// quality is reduced only as far as needed to reach the storage target.
class MeetingMinutePhotoCompressor {
  static const int maxDimension = 1280;
  static const int targetBytes = 600 * 1024;
  static const int minimumQuality = 48;

  const MeetingMinutePhotoCompressor._();

  static CompressedMeetingMinutePhoto compress({
    required Uint8List bytes,
    required String fileName,
  }) {
    final image.Image? decoded = image.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException(
        'Foto JPG, JPEG, atau PNG tidak dapat dibaca.',
      );
    }
    image.Image normalized = image.bakeOrientation(decoded);
    if (normalized.width > maxDimension || normalized.height > maxDimension) {
      if (normalized.width >= normalized.height) {
        normalized = image.copyResize(normalized, width: maxDimension);
      } else {
        normalized = image.copyResize(normalized, height: maxDimension);
      }
    }

    int quality = 72;
    Uint8List output = Uint8List.fromList(
      image.encodeJpg(normalized, quality: quality),
    );
    while (output.lengthInBytes > targetBytes && quality > minimumQuality) {
      quality -= 8;
      output = Uint8List.fromList(
        image.encodeJpg(normalized, quality: quality),
      );
    }
    while (output.lengthInBytes > targetBytes &&
        (normalized.width > 800 || normalized.height > 800)) {
      normalized = image.copyResize(
        normalized,
        width: (normalized.width * 0.85).round(),
        height: (normalized.height * 0.85).round(),
      );
      output = Uint8List.fromList(
        image.encodeJpg(normalized, quality: minimumQuality),
      );
    }
    return CompressedMeetingMinutePhoto(
      bytes: output,
      fileName: _jpegFileName(fileName),
    );
  }

  static String _jpegFileName(String fileName) {
    final String trimmed = fileName.trim();
    final int extensionStart = trimmed.lastIndexOf('.');
    final String stem = extensionStart > 0
        ? trimmed.substring(0, extensionStart)
        : (trimmed.isEmpty ? 'foto-notulen' : trimmed);
    return '$stem.jpg';
  }
}

class CompressedMeetingMinutePhoto {
  const CompressedMeetingMinutePhoto({
    required this.bytes,
    required this.fileName,
  });

  final Uint8List bytes;
  final String fileName;
  static const String mimeType = 'image/jpeg';
}
