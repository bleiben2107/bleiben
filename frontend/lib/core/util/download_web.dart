import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

bool downloadText(String filename, String content, {String mime = 'text/csv'}) =>
    _save(filename, web.Blob([content.toJS].toJS, web.BlobPropertyBag(type: mime)));

bool downloadBytes(String filename, Uint8List bytes, {String mime = 'application/octet-stream'}) =>
    _save(filename, web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime)));

bool _save(String filename, web.Blob blob) {
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(a);
  a.click();
  a.remove();
  web.URL.revokeObjectURL(url);
  return true;
}
