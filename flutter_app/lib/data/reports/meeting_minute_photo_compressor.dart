import 'dart:typed_data';

import 'package:image/image.dart' as image;

/// Produces a compact photo suitable for the private Notulen Rapat bucket.
///
/// The storage plan is limited, so every evidence photo is normalized before
/// upload: EXIF orientation is applied, the longest side is capped, and JPEG
/// quality is reduced only as far as needed to reach the storage target.
class MeetingMinutePhotoCompressor {
  static const int maxDimension = 1280;
  static const int targetBytes = 600 * 1024;
  static const int minimumQuality = 48;
  static const String jpegMimeType = 'image/jpeg';
  static const String pngMimeType = 'image/png';

  const MeetingMinutePhotoCompressor._();

  /// [maxDimension] and [targetBytes] default to the Notulen limits; Major
  /// Job passes smaller ones because its photos are printed 5.4 cm wide and
  /// live in a 1 GB Cloudflare KV namespace.
  static CompressedMeetingMinutePhoto compress({
    required Uint8List bytes,
    required String fileName,
    int maxDimension = MeetingMinutePhotoCompressor.maxDimension,
    int targetBytes = MeetingMinutePhotoCompressor.targetBytes,
  }) {
    image.Image? decoded;
    try {
      decoded = image.decodeImage(bytes);
    } on Object {
      // Corrupt files make some decoders throw RangeError instead of
      // returning null; report them the same way.
      decoded = null;
    }
    if (decoded == null) {
      throw const FormatException(
        'Foto JPG, JPEG, atau PNG tidak dapat dibaca.',
      );
    }
    final bool isRotated =
        decoded.exif.imageIfd.hasOrientation &&
        decoded.exif.imageIfd.orientation != 1;
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
    // A picture that is already compact grows when it is re-encoded, so the
    // original costs less storage. A rotated original must still be re-encoded
    // because exports draw the pixels without reading EXIF.
    if (!isRotated && output.lengthInBytes >= bytes.lengthInBytes) {
      return CompressedMeetingMinutePhoto(
        bytes: bytes,
        fileName: fileName,
        mimeType: _originalMimeType(fileName),
        width: decoded.width,
        height: decoded.height,
      );
    }
    return CompressedMeetingMinutePhoto(
      bytes: output,
      fileName: _jpegFileName(fileName),
      mimeType: jpegMimeType,
      width: normalized.width,
      height: normalized.height,
    );
  }

  static String _originalMimeType(String fileName) =>
      fileName.trim().toLowerCase().endsWith('.png')
      ? pngMimeType
      : jpegMimeType;

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
    required this.mimeType,
    this.width = 0,
    this.height = 0,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;

  /// Pixel size of [bytes], so a caller can lay the photo out before upload.
  final int width;
  final int height;
}
