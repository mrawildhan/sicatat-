import 'dart:typed_data';

import 'meeting_minute_photo_compressor.dart';

/// A reminder attachment that is ready to upload.
class PreparedReminderEvidence {
  const PreparedReminderEvidence({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;
}

/// Shrinks reminder attachments before they reach the private
/// `reminder-evidence` bucket, because the Supabase plan has little storage.
///
/// Photos reuse the meeting minute compressor (JPEG, longest side 1280 px).
/// PDFs cannot be recompressed in the app, so they get a tight size cap.
class ReminderEvidencePreparer {
  static const int maxPickedBytes = 10 * 1024 * 1024;
  static const int maxPdfBytes = 2 * 1024 * 1024;

  const ReminderEvidencePreparer._();

  /// Throws a [FormatException] with a message that can be shown to the user.
  static PreparedReminderEvidence prepare({
    required String fileName,
    required Uint8List bytes,
  }) {
    if (bytes.length > maxPickedBytes) {
      throw FormatException('$fileName lebih besar dari 10 MB.');
    }
    switch (fileName.split('.').last.toLowerCase()) {
      case 'pdf':
        if (bytes.length > maxPdfBytes) {
          throw FormatException(
            '$fileName lebih besar dari 2 MB. Kecilkan PDF terlebih dahulu atau unggah fotonya.',
          );
        }
        return PreparedReminderEvidence(
          name: fileName,
          bytes: bytes,
          mimeType: 'application/pdf',
        );
      case 'jpg' || 'jpeg' || 'png':
        final CompressedMeetingMinutePhoto compressed;
        try {
          compressed = MeetingMinutePhotoCompressor.compress(
            bytes: bytes,
            fileName: fileName,
          );
        } on FormatException {
          throw FormatException('$fileName tidak dapat dibaca sebagai gambar.');
        }
        // An already compact picture can grow when re-encoded; keep whichever
        // version uses less storage.
        if (compressed.bytes.length >= bytes.length) {
          return PreparedReminderEvidence(
            name: fileName,
            bytes: bytes,
            mimeType: fileName.toLowerCase().endsWith('.png')
                ? 'image/png'
                : 'image/jpeg',
          );
        }
        return PreparedReminderEvidence(
          name: compressed.fileName,
          bytes: compressed.bytes,
          mimeType: CompressedMeetingMinutePhoto.mimeType,
        );
      default:
        throw FormatException('$fileName bukan PDF, JPG, JPEG, atau PNG.');
    }
  }
}
