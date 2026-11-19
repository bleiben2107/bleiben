import 'url_strategy_stub.dart' if (dart.library.js_interop) 'url_strategy_web.dart' as impl;

/// Web: clean URLs (bleiben.co.in/host/properties, no "#"). Old "#/…" links
/// (shared booking links, bookmarks) are rewritten to the clean form first.
void useCleanUrls() => impl.useCleanUrls();
