import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';

/// A property as listed in the Host Control Center (`/api/properties`).
class PropertySummary {
  PropertySummary.fromJson(Map<String, dynamic> j)
      : raw = j,
        id = (j['id'] as num).toInt(),
        serialId = (j['propertySerialId'] as String?) ?? '',
        title = (j['title'] as String?) ?? '',
        city = (j['city'] as String?) ?? '',
        location = (j['location'] as String?) ?? '',
        status = (j['status'] as String?) ?? 'draft',
        propertyType = (j['propertyType'] as String?) ?? '',
        currentStep = (j['current_step'] as String?) ?? '',
        basePrice = (j['basePrice'] as num?)?.toDouble() ?? 0,
        extraGuestCharge = (j['extraGuestCharge'] as num?)?.toDouble() ?? 0,
        advancePercent = (j['advancePercent'] as num?)?.toDouble() ?? 0,
        guests = ((j['capacity'] as Map?)?['guests'] as num?)?.toInt() ?? 0,
        coverPhoto = j['coverPhoto'] as String?,
        bookingUrl = j['booking_url'] as String?,
        roomCount = (j['room_count'] as num?)?.toInt() ??
            ((j['rooms'] as List?)?.length ?? 0),
        unitCount = (j['unit_count'] as num?)?.toInt() ??
            ((j['rooms'] as List?) ?? const [])
                .fold<int>(0, (n, r) => n + ((r as Map)['unit_count'] as num).toInt()),
        rooms = [
          for (final r in (j['rooms'] as List?) ?? const [])
            Room.fromJson((r as Map).cast<String, dynamic>())
        ];

  /// Full API payload (used to reopen the listing wizard on this property).
  final Map<String, dynamic> raw;
  final int id;
  final String serialId;
  final String title;
  final String city;
  final String location;
  final String status;
  final String propertyType;
  final String currentStep;
  final double basePrice;
  final double extraGuestCharge;
  final double advancePercent;
  final int guests;
  final String? coverPhoto;
  final String? bookingUrl;
  final int roomCount;
  final int unitCount;
  final List<Room> rooms;

  bool get isLive => status == 'activated';
  String get displayTitle => title.isEmpty ? 'Untitled draft' : title;

  static String statusLabel(String status) => switch (status) {
        'activated' => 'Published',
        'deactivated' => 'Unpublished',
        'declined' => 'Declined',
        _ => 'Draft',
      };
}

const roomTypes = {
  'room': 'Private room',
  'suite': 'Suite',
  'entire_place': 'Entire place',
  'cottage': 'Cottage',
  'villa': 'Villa',
  'tent': 'Tent',
  'dorm_bed': 'Dorm bed',
};

/// A sellable room type with its inventory (MVP plan §3: rooms & units).
class Room {
  Room.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = (j['name'] as String?) ?? '',
        type = (j['room_type'] as String?) ?? 'room',
        maxAdults = (j['max_adults'] as num?)?.toInt() ?? 2,
        maxChildren = (j['max_children'] as num?)?.toInt() ?? 0,
        unitCount = (j['unit_count'] as num?)?.toInt() ?? 1,
        basePrice = (j['base_price'] as num?)?.toDouble(),
        extraGuestCharge = (j['extra_guest_charge'] as num?)?.toDouble(),
        effectivePrice = (j['effective_price'] as num?)?.toDouble() ?? 0,
        amenities = ((j['amenities'] as List?) ?? const []).cast<String>(),
        status = (j['status'] as String?) ?? 'active';

  final int id;
  final String name;
  final String type;
  final int maxAdults;
  final int maxChildren;
  final int unitCount;
  final double? basePrice;
  final double? extraGuestCharge;
  final double effectivePrice;
  final List<String> amenities;
  final String status;

  int get maxGuests => maxAdults + maxChildren;
  String get typeLabel => roomTypes[type] ?? type;
}

class ActivityEntry {
  ActivityEntry.fromJson(Map<String, dynamic> j)
      : action = (j['action'] as String?) ?? '',
        userName = (j['user_name'] as String?) ?? '',
        fields = ((j['fields'] as List?) ?? const []).map((e) => '$e').toList(),
        at = DateTime.tryParse((j['at'] as String?) ?? '')?.toLocal();

  final String action;
  final String userName;
  final List<String> fields;
  final DateTime? at;

  String get label => switch (action) {
        'created_draft' => 'Created the draft',
        'updated' || 'updated_step' => 'Updated the listing',
        'published' => 'Published the booking page',
        'unpublished' => 'Took the booking page offline',
        'room_added' => 'Added room ${fields.join(', ')}',
        'room_updated' => 'Edited room ${fields.join(', ')}',
        'room_archived' => 'Archived room ${fields.join(', ')}',
        'cloned' => 'Created as a copy',
        'deleted' => 'Archived the property',
        _ => action,
      };
}

/// Properties module state for the Host Control Center: list with search and
/// status filter, plus per-property actions.
class PropertiesController extends ChangeNotifier {
  PropertiesController({required this.api});

  final ApiClient api;

  List<PropertySummary> items = [];
  bool loading = false;
  String? error;
  String query = '';
  String status = 'all';

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final params = <String>[
        if (query.trim().isNotEmpty) 'q=${Uri.encodeQueryComponent(query.trim())}',
        if (status != 'all') 'status=$status',
      ];
      final data = await api.get(
          '/api/properties${params.isEmpty ? '' : '?${params.join('&')}'}') as List;
      items = [
        for (final p in data) PropertySummary.fromJson((p as Map).cast<String, dynamic>())
      ];
    } on ApiException catch (e) {
      error = e.message;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void setQuery(String q) {
    query = q;
    load();
  }

  void setStatus(String s) {
    status = s;
    load();
  }

  Future<PropertySummary> fetch(int id) async =>
      PropertySummary.fromJson((await api.get('/api/properties/$id') as Map).cast<String, dynamic>());

  Future<List<ActivityEntry>> activity(int id) async => [
        for (final a in await api.get('/api/properties/$id/activity') as List)
          ActivityEntry.fromJson((a as Map).cast<String, dynamic>())
      ];

  /// Publish; returns the error message or null.
  Future<String?> publish(int id) => _guard(() => api.post('/api/properties/$id/publish', {}));

  Future<String?> unpublish(int id) => _guard(() => api.post('/api/properties/$id/unpublish', {}));

  Future<String?> saveRoom(int propertyId, Map<String, dynamic> body, {int? roomId}) =>
      _guard(() => roomId == null
          ? api.post('/api/properties/$propertyId/rooms', body)
          : api.patch('/api/properties/$propertyId/rooms/$roomId', body));

  Future<String?> archiveRoom(int propertyId, int roomId) =>
      _guard(() => api.delete('/api/properties/$propertyId/rooms/$roomId'));

  Future<String?> _guard(Future<dynamic> Function() call) async {
    try {
      await call();
      load();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }
}
