import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

final _registered = <String>{};

String _embedUrl(double? lat, double? lon) {
  if (lat == null || lon == null) {
    // India.
    return 'https://www.openstreetmap.org/export/embed.html?bbox=68.0%2C6.5%2C97.5%2C35.7&layer=mapnik';
  }
  const dLon = 0.012;
  const dLat = 0.007;
  final bbox = '${lon - dLon}%2C${lat - dLat}%2C${lon + dLon}%2C${lat + dLat}';
  return 'https://www.openstreetmap.org/export/embed.html?bbox=$bbox&layer=mapnik&marker=$lat%2C$lon';
}

Widget osmMapView({double? lat, double? lon, required Widget fallback}) {
  final url = _embedUrl(lat, lon);
  final viewType = 'osm-map-${url.hashCode}';
  if (_registered.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) {
      return web.HTMLIFrameElement()
        ..src = url
        ..style.border = '0'
        ..style.width = '100%'
        ..style.height = '100%'
        ..title = 'Property location map'
        ..referrerPolicy = 'strict-origin-when-cross-origin';
    });
  }
  return HtmlElementView(key: ValueKey(viewType), viewType: viewType);
}

Future<({double lat, double lon})?> currentPosition() {
  final done = Completer<({double lat, double lon})?>();
  try {
    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition p) {
        if (!done.isCompleted) done.complete((lat: p.coords.latitude, lon: p.coords.longitude));
      }).toJS,
      ((web.GeolocationPositionError _) {
        if (!done.isCompleted) done.complete(null);
      }).toJS,
      web.PositionOptions(enableHighAccuracy: true, timeout: 15000),
    );
  } catch (_) {
    if (!done.isCompleted) done.complete(null);
  }
  return done.future.timeout(const Duration(seconds: 20), onTimeout: () => null);
}
