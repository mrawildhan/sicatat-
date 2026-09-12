import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

void downloadFile({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) {
  final web.BlobPart bytesPart = bytes.toJS as web.BlobPart;
  final web.Blob blob = web.Blob(
    <web.BlobPart>[bytesPart].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final String url = web.URL.createObjectURL(blob);
  final web.HTMLAnchorElement anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
}
