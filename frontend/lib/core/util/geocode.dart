import 'dart:convert';

import 'package:http/http.dart' as http;

/// A found place: coordinates plus the address parts we fill in.
class GeoPlace {
  GeoPlace({required this.lat, required this.lon, required this.label, this.city = '', this.state = '', this.postcode = '', this.country = ''});

  final double lat;
  final double lon;
  final String label;
  final String city;
  final String state;
  final String postcode;
  final String country;

  static GeoPlace? fromNominatim(Map<String, dynamic> j) {
    final lat = double.tryParse('${j['lat']}');
    final lon = double.tryParse('${j['lon']}');
    if (lat == null || lon == null) return null;
    final a = (j['address'] as Map?)?.cast<String, dynamic>() ?? const {};
    String pick(List<String> keys) => keys.map((k) => '${a[k] ?? ''}').firstWhere((v) => v.isNotEmpty, orElse: () => '');
    return GeoPlace(
      lat: lat,
      lon: lon,
      label: '${j['display_name'] ?? ''}',
      city: pick(['city', 'town', 'village', 'suburb', 'county', 'state_district']),
      state: pick(['state']),
      postcode: pick(['postcode']),
      country: pick(['country']),
    );
  }
}

/// Address lookup with OpenStreetMap Nominatim (free, no key; light use only).
class Geocoder {
  Geocoder({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _base = 'https://nominatim.openstreetmap.org';

  Future<GeoPlace?> search(String query) async {
    final q = query.trim();
    if (q.length < 3) return null;
    final uri = Uri.parse('$_base/search').replace(queryParameters: {'format': 'jsonv2', 'limit': '1', 'addressdetails': '1', 'countrycodes': 'in', 'q': q});
    try {
      final r = await _http.get(uri, headers: {'Accept-Language': 'en'}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      final list = jsonDecode(r.body) as List;
      return list.isEmpty ? null : GeoPlace.fromNominatim((list.first as Map).cast());
    } catch (_) {
      return null;
    }
  }

  Future<GeoPlace?> reverse(double lat, double lon) async {
    final uri = Uri.parse('$_base/reverse').replace(queryParameters: {'format': 'jsonv2', 'addressdetails': '1', 'lat': '$lat', 'lon': '$lon'});
    try {
      final r = await _http.get(uri, headers: {'Accept-Language': 'en'}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;
      return GeoPlace.fromNominatim((jsonDecode(r.body) as Map).cast());
    } catch (_) {
      return null;
    }
  }
}
