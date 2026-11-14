import 'download_stub.dart' if (dart.library.js_interop) 'download_web.dart' as impl;

/// Saves [content] as a file named [filename] (browser download on web).
/// Returns false where downloads aren't supported.
bool downloadText(String filename, String content, {String mime = 'text/csv'}) =>
    impl.downloadText(filename, content, mime: mime);
