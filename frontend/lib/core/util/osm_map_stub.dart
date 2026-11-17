import 'package:flutter/widgets.dart';

Widget osmMapView({double? lat, double? lon, required Widget fallback}) => fallback;

Future<({double lat, double lon})?> currentPosition() async => null;
