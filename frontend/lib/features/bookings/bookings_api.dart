import '../../core/network/api_client.dart';

/// Shared models + API for Calendar, Reservations and Dashboard
/// (backend: /api/calendar, /api/bookings).

const bookingSources = {
  'phone': 'Phone',
  'whatsapp': 'WhatsApp',
  'walk_in': 'Walk-in',
  'manual': 'Manual',
  'direct': 'Bleiben Direct',
  'airbnb': 'Airbnb',
  'booking_com': 'Booking.com',
  'makemytrip': 'MakeMyTrip',
  'goibibo': 'Goibibo',
  'agoda': 'Agoda',
};

const paymentMethods = {
  'cash': 'Cash',
  'upi': 'UPI',
  'card': 'Card',
  'bank_transfer': 'Bank transfer',
  'payment_link': 'Payment link',
  'ota': 'Paid to OTA',
};

const statusLabels = {
  'inquiry': 'Inquiry',
  'held': 'On hold',
  'pending_payment': 'Pending payment',
  'confirmed': 'Confirmed',
  'checked_in': 'Checked in',
  'checked_out': 'Checked out',
  'cancelled': 'Cancelled',
  'expired': 'Expired',
  'no_show': 'No-show',
};

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseYmd(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// "12 Nov" / "12 Nov 2026".
String prettyDate(String s, {bool year = false}) {
  final d = parseYmd(s);
  return '${d.day} ${_months[d.month - 1]}${year ? ' ${d.year}' : ''}';
}

String money(num v) {
  final neg = v < 0;
  final n = v.abs().round();
  final s = n.toString();
  // Indian grouping: 12,34,567
  String out;
  if (s.length <= 3) {
    out = s;
  } else {
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    out = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$out';
}

class CalendarCell {
  CalendarCell.fromJson(Map<String, dynamic> j)
      : date = j['date'] as String,
        price = (j['price'] as num).toDouble(),
        customPrice = (j['custom_price'] as bool?) ?? false,
        units = (j['units'] as num).toInt(),
        booked = (j['booked'] as num).toInt(),
        blocked = (j['blocked'] as bool?) ?? false,
        blockReason = j['block_reason'] as String?,
        blockNotes = j['block_notes'] as String?,
        available = (j['available'] as num).toInt();

  final String date;
  final double price;
  final bool customPrice;
  final int units;
  final int booked;
  final bool blocked;
  final String? blockReason;
  final String? blockNotes;
  final int available;
}

class BookingBar {
  BookingBar.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        code = (j['code'] as String?) ?? '',
        guestName = (j['guest_name'] as String?) ?? '',
        guests = (j['guests'] as num?)?.toInt() ?? 1,
        source = (j['source'] as String?) ?? 'manual',
        status = (j['status'] as String?) ?? 'confirmed',
        checkIn = j['check_in'] as String,
        checkOut = j['check_out'] as String,
        balance = (j['balance'] as num?)?.toDouble() ?? 0;

  final int id;
  final String code;
  final String guestName;
  final int guests;
  final String source;
  final String status;
  final String checkIn;
  final String checkOut;
  final double balance;
}

class CalendarRoom {
  CalendarRoom.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        name = (j['name'] as String?) ?? '',
        units = (j['units'] as num?)?.toInt() ?? 1,
        maxGuests = (j['max_guests'] as num?)?.toInt() ?? 2,
        basePrice = (j['base_price'] as num?)?.toDouble() ?? 0,
        occupancy = (j['occupancy'] as num?)?.toInt() ?? 0,
        cells = [for (final c in j['cells'] as List) CalendarCell.fromJson((c as Map).cast())],
        bookings = [for (final b in (j['bookings'] as List?) ?? const []) BookingBar.fromJson((b as Map).cast())];

  final int id;
  final String name;
  final int units;
  final int maxGuests;
  final double basePrice;
  final int occupancy;
  final List<CalendarCell> cells;
  final List<BookingBar> bookings;
}

class CalendarProperty {
  CalendarProperty.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        serialId = (j['serial_id'] as String?) ?? '',
        title = (j['title'] as String?) ?? '',
        city = (j['city'] as String?) ?? '',
        rooms = [for (final r in j['rooms'] as List) CalendarRoom.fromJson((r as Map).cast())];

  final int id;
  final String serialId;
  final String title;
  final String city;
  final List<CalendarRoom> rooms;
}

class CalendarData {
  CalendarData.fromJson(Map<String, dynamic> j)
      : from = j['from'] as String,
        to = j['to'] as String,
        days = (j['days'] as List).cast<String>(),
        totalProperties = (j['total_properties'] as num?)?.toInt() ?? 0,
        properties = [for (final p in j['properties'] as List) CalendarProperty.fromJson((p as Map).cast())];

  final String from;
  final String to;
  final List<String> days;
  final int totalProperties;
  final List<CalendarProperty> properties;
}

class Payment {
  Payment.fromJson(Map<String, dynamic> j)
      : amount = (j['amount'] as num).toDouble(),
        method = (j['method'] as String?) ?? 'cash',
        kind = (j['kind'] as String?) ?? 'payment',
        reference = (j['reference'] as String?) ?? '',
        at = (j['at'] as String?) ?? '',
        by = (j['by'] as String?) ?? '';

  final double amount;
  final String method;
  final String kind;
  final String reference;
  final String at;
  final String by;
}

class BookingEvent {
  BookingEvent.fromJson(Map<String, dynamic> j)
      : at = (j['at'] as String?) ?? '',
        by = (j['by'] as String?) ?? '',
        action = (j['action'] as String?) ?? '',
        detail = (j['detail'] as String?) ?? '';

  final String at;
  final String by;
  final String action;
  final String detail;
}

class Booking {
  Booking.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        code = (j['code'] as String?) ?? '',
        status = (j['status'] as String?) ?? 'confirmed',
        tripStatus = (j['trip_status'] as String?) ?? 'upcoming',
        source = (j['source'] as String?) ?? 'manual',
        sourceLabel = (j['source_label'] as String?) ?? '',
        propertyId = ((j['property'] as Map?)?['id'] as num?)?.toInt(),
        propertyTitle = ((j['property'] as Map?)?['title'] as String?) ?? '',
        roomId = ((j['room'] as Map?)?['id'] as num?)?.toInt(),
        roomName = ((j['room'] as Map?)?['name'] as String?) ?? '',
        checkIn = j['check_in'] as String,
        checkOut = j['check_out'] as String,
        nights = (j['nights'] as num?)?.toInt() ?? 1,
        guestName = ((j['guest'] as Map?)?['name'] as String?) ?? '',
        guestPhone = ((j['guest'] as Map?)?['phone'] as String?) ?? '',
        guestEmail = ((j['guest'] as Map?)?['email'] as String?) ?? '',
        adults = (j['adults'] as num?)?.toInt() ?? 1,
        children = (j['children'] as num?)?.toInt() ?? 0,
        total = (j['total'] as num?)?.toDouble() ?? 0,
        paid = (j['paid'] as num?)?.toDouble() ?? 0,
        balance = (j['balance'] as num?)?.toDouble() ?? 0,
        paymentStatus = (j['payment_status'] as String?) ?? 'pending',
        payments = [for (final p in (j['payments'] as List?) ?? const []) Payment.fromJson((p as Map).cast())],
        events = [for (final e in (j['events'] as List?) ?? const []) BookingEvent.fromJson((e as Map).cast())],
        notes = (j['notes'] as String?) ?? '',
        holdExpiresAt = j['hold_expires_at'] as String?,
        cancelReason = j['cancel_reason'] as String?,
        bookedAt = (j['booked_at'] as String?) ?? '';

  final int id;
  final String code;
  final String status;
  final String tripStatus;
  final String source;
  final String sourceLabel;
  final int? propertyId;
  final String propertyTitle;
  final int? roomId;
  final String roomName;
  final String checkIn;
  final String checkOut;
  final int nights;
  final String guestName;
  final String guestPhone;
  final String guestEmail;
  final int adults;
  final int children;
  final double total;
  final double paid;
  final double balance;
  final String paymentStatus;
  final List<Payment> payments;
  final List<BookingEvent> events;
  final String notes;
  final String? holdExpiresAt;
  final String? cancelReason;
  final String bookedAt;

  int get guests => adults + children;
  bool get isOpen => !['cancelled', 'expired', 'no_show', 'checked_out'].contains(status);
}

class BookingPage {
  BookingPage.fromJson(Map<String, dynamic> j)
      : items = [for (final b in j['items'] as List) Booking.fromJson((b as Map).cast())],
        total = (j['total'] as num).toInt(),
        page = (j['page'] as num).toInt(),
        pageSize = (j['page_size'] as num).toInt(),
        counts = ((j['counts'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as num).toInt()));

  final List<Booking> items;
  final int total;
  final int page;
  final int pageSize;
  final Map<String, int> counts;
}

/// Thin typed wrapper; errors surface as [ApiException] with the API's message.
class BookingsApi {
  BookingsApi(this.api);

  final ApiClient api;

  Future<CalendarData> calendar({required String from, int days = 15, String search = ''}) async {
    final q = 'from=$from&days=$days${search.isEmpty ? '' : '&search=${Uri.encodeQueryComponent(search)}'}';
    return CalendarData.fromJson((await api.get('/api/calendar?$q') as Map).cast());
  }

  Future<void> block(List<int> roomIds, String from, String to, {String reason = '', String notes = '', List<int>? days}) =>
      api.post('/api/calendar/blocks', {'room_ids': roomIds, 'from': from, 'to': to, 'reason': reason, 'notes': notes, if (days != null) 'days_of_week': days});

  Future<void> unblock(List<int> roomIds, String from, String to, {List<int>? days}) =>
      api.post('/api/calendar/unblock', {'room_ids': roomIds, 'from': from, 'to': to, if (days != null) 'days_of_week': days});

  Future<void> updateBlockReason(List<int> roomIds, String from, String to, {String? reason, String? notes}) =>
      api.patch('/api/calendar/blocks', {'room_ids': roomIds, 'from': from, 'to': to, if (reason != null) 'reason': reason, if (notes != null) 'notes': notes});

  Future<int> setRates(List<int> roomIds, String from, String to, {double? price, double? percent, List<int>? days}) async {
    final r = await api.put('/api/calendar/rates', {
      'room_ids': roomIds,
      'from': from,
      'to': to,
      if (price != null) 'price': price,
      if (percent != null) 'percent': percent,
      if (days != null) 'days_of_week': days,
    }) as Map;
    return (r['updated'] as num).toInt();
  }

  Future<BookingPage> list(Map<String, String> query) async {
    final q = query.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return BookingPage.fromJson((await api.get('/api/bookings?$q') as Map).cast());
  }

  Future<String> exportCsv(Map<String, String> query) async {
    final q = query.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return (await api.get('/api/bookings/export?$q')).toString();
  }

  Future<Map<String, dynamic>> quote(Map<String, dynamic> body) async => (await api.post('/api/bookings/quote', body) as Map).cast();

  Future<Booking> create(Map<String, dynamic> body) async => Booking.fromJson((await api.post('/api/bookings', body) as Map).cast());

  Future<Booking> get(int id) async => Booking.fromJson((await api.get('/api/bookings/$id') as Map).cast());

  Future<Booking> update(int id, Map<String, dynamic> body) async => Booking.fromJson((await api.patch('/api/bookings/$id', body) as Map).cast());

  /// action: confirm | check-in | check-out | no-show | cancel
  Future<Booking> action(int id, String action, [Map<String, dynamic> body = const {}]) async =>
      Booking.fromJson((await api.post('/api/bookings/$id/$action', body) as Map).cast());

  Future<Booking> addPayment(int id, Map<String, dynamic> body) async =>
      Booking.fromJson((await api.post('/api/bookings/$id/payments', body) as Map).cast());

  /// Properties with their active rooms (for pickers).
  Future<List<({int id, String title, List<({int id, String name, int maxGuests})> rooms})>> roomCatalog() async {
    final list = await api.get('/api/properties') as List;
    final out = <({int id, String title, List<({int id, String name, int maxGuests})> rooms})>[];
    for (final p in list) {
      final m = (p as Map).cast<String, dynamic>();
      final detail = (await api.get('/api/properties/${m['id']}') as Map).cast<String, dynamic>();
      final rooms = [
        for (final r in (detail['rooms'] as List?) ?? const [])
          (
            id: ((r as Map)['id'] as num).toInt(),
            name: (r['name'] as String?) ?? '',
            maxGuests: (r['max_guests'] as num?)?.toInt() ?? 2,
          )
      ];
      if (rooms.isNotEmpty) out.add((id: (m['id'] as num).toInt(), title: (m['title'] as String?)?.isNotEmpty == true ? m['title'] as String : 'Untitled property', rooms: rooms));
    }
    return out;
  }
}
