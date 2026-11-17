import 'package:flutter/widgets.dart';

import 'osm_map_stub.dart' if (dart.library.js_interop) 'osm_map_web.dart' as impl;

/// Live OpenStreetMap view centred on [lat]/[lon] with a pin (web). With no
/// coordinates it shows India. Other platforms get [fallback].
Widget osmMapView({double? lat, double? lon, required Widget fallback}) =>
    impl.osmMapView(lat: lat, lon: lon, fallback: fallback);

/// The device's current position (asks the browser for permission), or null.
Future<({double lat, double lon})?> currentPosition() => impl.currentPosition();
