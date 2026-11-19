import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

void useCleanUrls() {
  final hash = web.window.location.hash; // e.g. "#/host/calendar" or "#/p/pine?checkin=…"
  if (hash.startsWith('#/')) {
    web.window.history.replaceState(null, '', hash.substring(1));
  }
  usePathUrlStrategy();
}
