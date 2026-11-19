import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/razorpay.dart';
import '../bookings/bookings_api.dart' show money, prettyDate, ymd;

/// Guest-facing direct booking page (`/p/<slug>`): MVP plan §6 —
/// guest selects dates → enters details → Bleiben holds the room → payment is
/// verified → the reservation is confirmed. No login needed.
class PublicBookingScreen extends StatefulWidget {
  const PublicBookingScreen({super.key, required this.api, required this.slug, this.initialRange});

  final ApiClient api;
  final String slug;

  /// Dates from the link (?checkin=YYYY-MM-DD&checkout=YYYY-MM-DD).
  final DateTimeRange? initialRange;

  @override
  State<PublicBookingScreen> createState() => _PublicBookingScreenState();
}

enum _Step { browse, details, pay, done }

class _PublicBookingScreenState extends State<PublicBookingScreen> {
  Map<String, dynamic>? _stay;
  String? _error;
  DateTimeRange? _dates;
  int _adults = 2;
  int _children = 0;
  Map<int, Map<String, dynamic>> _quotes = {};
  bool _quoting = false;
  int? _roomId;
  _Step _step = _Step.browse;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  bool _busy = false;

  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _payment;
  String? _token;
  String? _payMessage;
  Timer? _tick;

  String get _base => '/api/public/stays/${Uri.encodeComponent(widget.slug)}';

  @override
  void initState() {
    super.initState();
    _dates = widget.initialRange;
    _load().then((_) => _quote());
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final c in [_name, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await widget.api.get(_base);
      if (mounted) setState(() => _stay = (s as Map).cast());
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : 'This booking page could not load.');
    }
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 540)),
      initialDateRange: _dates,
      helpText: 'Check-in and check-out',
    );
    if (r == null || !r.end.isAfter(r.start)) return;
    setState(() => _dates = r);
    _quote();
  }

  Future<void> _quote() async {
    final d = _dates;
    if (d == null) return;
    setState(() => _quoting = true);
    try {
      final r = await widget.api.post('$_base/quote', {'check_in': ymd(d.start), 'check_out': ymd(d.end), 'adults': _adults, 'children': _children}, auth: false) as Map;
      if (!mounted) return;
      setState(() {
        _quotes = {for (final q in (r['rooms'] as List).cast<Map>()) (q['room_id'] as num).toInt(): q.cast<String, dynamic>()};
        if (_roomId != null && _quotes[_roomId]?['available'] != true) _roomId = null;
      });
    } catch (e) {
      if (mounted) _snack(e is ApiException ? e.message : 'Could not check prices');
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _book() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final r = (await widget.api.post('$_base/book', {
        'room_id': _roomId,
        'check_in': ymd(_dates!.start),
        'check_out': ymd(_dates!.end),
        'adults': _adults,
        'children': _children,
        'guest': {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim()},
        'notes': _notes.text.trim(),
      }, auth: false) as Map)
          .cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _booking = (r['booking'] as Map).cast();
        _token = r['token'] as String;
        _payment = (r['payment'] as Map?)?.cast();
        _step = _payment == null ? _Step.done : _Step.pay;
      });
      if (_payment != null) _startTimer();
    } catch (e) {
      if (mounted) _snack(e is ApiException ? e.message : 'Could not book. Please try again.');
      _quote();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startTimer() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Duration get _holdLeft {
    final iso = _booking?['hold_expires_at'] as String?;
    if (iso == null) return Duration.zero;
    final d = DateTime.parse(iso).difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  Future<void> _pay() async {
    final p = _payment!;
    setState(() {
      _busy = true;
      _payMessage = null;
    });
    try {
      Map<String, dynamic> body;
      if (p['provider'] == 'test') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Test payment'),
            content: Text('This host is in test mode — no real money moves.\nAmount: ${money(p['amount'] as num)}'),
            actions: [
              TextButton(key: const Key('test-fail'), onPressed: () => Navigator.pop(ctx, false), child: const Text('Simulate failure')),
              TextButton(key: const Key('test-pay'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Pay (test)')),
            ],
          ),
        );
        if (ok == null) return;
        body = {'test_outcome': ok ? 'success' : 'failure'};
      } else {
        final r = await openRazorpayCheckout(
          keyId: p['key_id'] as String,
          orderId: p['order_id'] as String,
          amountPaise: ((p['amount'] as num) * 100).round(),
          name: _stay?['title'] as String? ?? 'Booking',
          description: 'Booking ${_booking?['code']}',
          prefillName: _name.text.trim(),
          prefillEmail: _email.text.trim(),
          prefillPhone: _phone.text.trim(),
        );
        if (r == null) return; // closed the window
        body = r.containsKey('error') ? {'error': {'description': r['error']}} : r;
      }
      final v = (await widget.api.post('/api/public/payments/${p['attempt_id']}/verify', {...body, 'token': _token}, auth: false) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _booking = (v['booking'] as Map).cast();
        _payMessage = v['message'] as String?;
        if (v['payment_status'] != 'failed') {
          _step = _Step.done;
          _tick?.cancel();
        }
      });
    } catch (e) {
      if (mounted) _snack(e is ApiException ? e.message : 'Payment could not be checked. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    try {
      final r = (await widget.api.post('/api/public/bookings/${_booking!['code']}/retry-payment', {'token': _token}, auth: false) as Map).cast<String, dynamic>();
      setState(() {
        _payment = r;
        _payMessage = null;
      });
      await _pay();
    } catch (e) {
      if (mounted) _snack(e is ApiException ? e.message : 'Could not start the payment');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _stay;
    return Scaffold(
      backgroundColor: AppTheme.paper,
      body: s == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!, textAlign: TextAlign.center, style: AppFonts.sans(fontSize: 17, color: AppTheme.muted)),
                    ),
            )
          : LayoutBuilder(builder: (context, c) {
              final wide = c.maxWidth >= 960;
              final main = _details(s);
              final side = _panel(s);
              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 14, vertical: 20),
                      child: wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(child: main),
                              const SizedBox(width: 28),
                              SizedBox(width: 400, child: side),
                            ])
                          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [side, const SizedBox(height: 20), main]),
                    ),
                  ),
                ),
              );
            }),
    );
  }

  Widget _photo(String url, {double h = 260, double w = double.infinity}) => ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url',
          height: h,
          width: w,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(height: h, width: w, color: AppTheme.sage, child: const Icon(Icons.image_outlined, color: AppTheme.muted)),
        ),
      );

  Widget _details(Map<String, dynamic> s) {
    final photos = (s['photos'] as List).cast<String>();
    final amenities = (s['amenities'] as List).map((e) => '$e').toList();
    final rules = (s['house_rules'] as Map?) ?? const {};
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s['title'] as String, style: AppFonts.display(fontSize: 34, fontWeight: FontWeight.w600)),
      const SizedBox(height: 4),
      Text([s['property_type'], s['location']].where((e) => e != null && '$e'.isNotEmpty).join(' · '), style: AppFonts.sans(color: AppTheme.muted, fontSize: 15)),
      const SizedBox(height: 16),
      if (photos.isNotEmpty) ...[
        _photo(photos.first),
        if (photos.length > 1) ...[
          const SizedBox(height: 8),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: photos.length - 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) => _photo(photos[i + 1], h: 90, w: 130),
            ),
          ),
        ],
      ],
      if ((s['description'] as String).isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(s['description'] as String, style: AppFonts.sans(fontSize: 15.5, height: 1.5)),
      ],
      if (amenities.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text('Amenities', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final a in amenities) Chip(label: Text(a.replaceAll('_', ' ')))]),
      ],
      const SizedBox(height: 20),
      Text('Rooms', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      for (final r in (s['rooms'] as List).cast<Map>()) _roomTile(r),
      const SizedBox(height: 20),
      Text('Good to know', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      if ('${s['check_in_time']}'.isNotEmpty) Text('Check-in from ${s['check_in_time']}'),
      if ('${s['check_out_time']}'.isNotEmpty) Text('Check-out by ${s['check_out_time']}'),
      if ('${s['cancellation_policy']}'.isNotEmpty) Text('Cancellation policy: ${'${s['cancellation_policy']}'.replaceAll('_', ' ')}'),
      if (rules['smokingAllowed'] == false) const Text('No smoking'),
      if (rules['partiesAllowed'] == false) const Text('No parties'),
      if (rules['petsAllowed'] == false) const Text('No pets'),
      if ('${rules['additionalRules'] ?? ''}'.isNotEmpty) Text('${rules['additionalRules']}'),
      const SizedBox(height: 30),
      Text('Booked directly with the host · powered by Bleiben', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.hint)),
    ]);
  }

  Widget _roomTile(Map r) {
    final id = (r['id'] as num).toInt();
    final q = _quotes[id];
    final selected = _roomId == id;
    final available = q?['available'] == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: BorderSide(color: selected ? AppTheme.forest : AppTheme.border, width: selected ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['name'] as String, style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700)),
              Text('Up to ${r['max_guests']} guests · from ${money(r['price_from'] as num)} / night', style: AppFonts.sans(color: AppTheme.muted, fontSize: 13.5)),
              if (q != null)
                Text(
                  available ? '${q['nights']} night(s) · ${money(q['total'] as num)}' : (q['reason'] as String? ?? 'Not available'),
                  style: AppFonts.sans(fontWeight: FontWeight.w600, color: available ? AppTheme.forest : AppTheme.danger),
                ),
            ]),
          ),
          if (_step == _Step.browse)
            OutlinedButton(
              key: Key('select-room-$id'),
              onPressed: _dates == null
                  ? _pickDates
                  : available
                      ? () => setState(() => _roomId = id)
                      : null,
              child: Text(_dates == null ? 'Pick dates' : selected ? 'Selected' : 'Select'),
            ),
        ]),
      ),
    );
  }

  Widget _counter(String label, int v, int min, ValueChanged<int> on) => Row(children: [
        Expanded(child: Text(label)),
        IconButton(tooltip: 'Fewer $label', onPressed: v > min ? () => on(v - 1) : null, icon: const Icon(Icons.remove_circle_outline)),
        Text('$v', style: AppFonts.sans(fontWeight: FontWeight.w700)),
        IconButton(tooltip: 'More $label', onPressed: v < 20 ? () => on(v + 1) : null, icon: const Icon(Icons.add_circle_outline)),
      ]);

  Widget _panel(Map<String, dynamic> s) {
    final mode = s['booking_mode'] as String;
    Widget card(Widget child) => Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
          child: child,
        );
    if (mode == 'closed') {
      return card(Text("This stay isn't taking online bookings right now. Please contact the host.", style: AppFonts.sans(color: AppTheme.muted)));
    }
    switch (_step) {
      case _Step.done:
        return card(_doneView(mode));
      case _Step.pay:
        return card(_payView());
      case _Step.details:
        return card(_guestForm(mode));
      case _Step.browse:
        final q = _roomId == null ? null : _quotes[_roomId];
        return card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(mode == 'instant' ? 'Book your stay' : 'Request to book', style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('pick-dates'),
            onPressed: _pickDates,
            icon: const Icon(Icons.date_range_outlined),
            label: Text(_dates == null ? 'Add dates' : '${prettyDate(ymd(_dates!.start))} → ${prettyDate(ymd(_dates!.end), year: true)}'),
          ),
          const SizedBox(height: 6),
          _counter('Adults', _adults, 1, (v) {
            setState(() => _adults = v);
            _quote();
          }),
          _counter('Children', _children, 0, (v) {
            setState(() => _children = v);
            _quote();
          }),
          if (_quoting) const LinearProgressIndicator(minHeight: 2),
          if (_dates != null && !_quoting && _quotes.values.every((x) => x['available'] != true))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('No rooms are free for these dates and guests. Try other dates.', style: AppFonts.sans(color: AppTheme.danger)),
            ),
          if (q != null) ...[
            const Divider(height: 24),
            _line('${money((q['stay'] as num) / (q['nights'] as num))} × ${q['nights']} night(s)', money(q['stay'] as num)),
            if ((q['extra_guest_charge'] as num) > 0) _line('Extra guests', money(q['extra_guest_charge'] as num)),
            _line('Total', money(q['total'] as num), bold: true),
            if (mode == 'instant' && (s['advance_percent'] as num) > 0 && (s['advance_percent'] as num) < 100)
              Text('Pay ${s['advance_percent']}% now (${money(((q['total'] as num) * (s['advance_percent'] as num) / 100).ceil())}), the rest at the property.',
                  style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
          ],
          const SizedBox(height: 14),
          ElevatedButton(
            key: const Key('continue-booking'),
            onPressed: q == null ? null : () => setState(() => _step = _Step.details),
            child: Text(_roomId == null ? (_dates == null ? 'Add dates to see prices' : 'Select a room') : 'Continue'),
          ),
        ]));
    }
  }

  Widget _line(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(child: Text(a, style: AppFonts.sans(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
          Text(b, style: AppFonts.sans(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );

  Widget _guestForm(String mode) {
    final q = _quotes[_roomId]!;
    final room = (_stay!['rooms'] as List).cast<Map>().firstWhere((r) => r['id'] == _roomId);
    return Form(
      key: _form,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(tooltip: 'Back', onPressed: () => setState(() => _step = _Step.browse), icon: const Icon(Icons.arrow_back)),
          Text('Your details', style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700)),
        ]),
        Text('${room['name']} · ${prettyDate(ymd(_dates!.start))} → ${prettyDate(ymd(_dates!.end), year: true)} · ${money(q['total'] as num)}',
            style: AppFonts.sans(color: AppTheme.muted)),
        const SizedBox(height: 12),
        TextFormField(
          key: const Key('guest-name'),
          controller: _name,
          decoration: const InputDecoration(labelText: 'Full name'),
          validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('guest-phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone (WhatsApp)'),
          validator: (v) => RegExp(r'^\+?[0-9 ()-]{7,20}$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid phone number',
        ),
        const SizedBox(height: 10),
        TextFormField(
          key: const Key('guest-email'),
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email (for your confirmation)'),
          validator: (v) => (v ?? '').trim().isEmpty || RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$').hasMatch(v!.trim()) ? null : 'Enter a valid email',
        ),
        const SizedBox(height: 10),
        TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Message to the host (optional)')),
        const SizedBox(height: 16),
        ElevatedButton(
          key: const Key('book-now'),
          onPressed: _busy ? null : _book,
          child: Text(_busy ? 'Please wait…' : mode == 'instant' ? 'Book and pay' : 'Send booking request'),
        ),
        const SizedBox(height: 6),
        Text(
          mode == 'instant' ? 'We hold the room for 15 minutes while you pay.' : 'The host confirms availability and contacts you to complete the booking.',
          style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted),
        ),
      ]),
    );
  }

  Widget _payView() {
    final left = _holdLeft;
    final expired = left == Duration.zero;
    final mm = left.inMinutes.toString().padLeft(2, '0');
    final ss = (left.inSeconds % 60).toString().padLeft(2, '0');
    final b = _booking!;
    final failed = _payMessage != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Complete your payment', style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text('Booking ${b['code']} · ${b['room']} · ${prettyDate(b['check_in'] as String)} → ${prettyDate(b['check_out'] as String, year: true)}',
          style: AppFonts.sans(color: AppTheme.muted)),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: expired ? AppTheme.dangerSoft : AppTheme.warningSoft, borderRadius: BorderRadius.circular(10)),
        child: Text(
          expired ? 'Your hold has expired. Start again to check the dates.' : 'Room held for you: $mm:$ss left',
          key: const Key('hold-timer'),
          style: AppFonts.sans(fontWeight: FontWeight.w600, color: expired ? AppTheme.danger : AppTheme.warningInk),
        ),
      ),
      const SizedBox(height: 12),
      _line('Total stay', money(b['total'] as num)),
      _line('Pay now', money(b['amount_due_now'] as num), bold: true),
      if ((b['total'] as num) > (b['amount_due_now'] as num)) _line('Pay at the property', money((b['total'] as num) - (b['amount_due_now'] as num))),
      if (failed) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_payMessage!, style: AppFonts.sans(color: AppTheme.danger))),
      const SizedBox(height: 14),
      ElevatedButton(
        key: const Key('pay-now'),
        onPressed: _busy
            ? null
            : expired
                ? () => setState(() {
                      _step = _Step.browse;
                      _booking = null;
                      _quote();
                    })
                : failed
                    ? _retry
                    : _pay,
        child: Text(_busy ? 'Please wait…' : expired ? 'Start again' : failed ? 'Try again' : 'Pay ${money(b['amount_due_now'] as num)}'),
      ),
      if (_payment?['provider'] == 'test')
        Padding(padding: const EdgeInsets.only(top: 6), child: Text('Test mode: no real money is charged.', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted))),
    ]);
  }

  Widget _doneView(String mode) {
    final b = _booking!;
    final confirmed = b['status'] == 'confirmed';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Icon(confirmed ? Icons.check_circle : Icons.mark_email_read_outlined, color: AppTheme.forest, size: 44),
      const SizedBox(height: 8),
      Text(confirmed ? 'Booking confirmed!' : b['status'] == 'inquiry' ? 'Request sent' : 'Payment received',
          key: const Key('booking-done'), textAlign: TextAlign.center, style: AppFonts.sans(fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      Text(
        confirmed
            ? 'Your booking ${b['code']} is confirmed. ${_email.text.trim().isNotEmpty ? 'A confirmation is on its way to ${_email.text.trim()}.' : 'The host will send you the details.'}'
            : b['status'] == 'inquiry'
                ? 'The host will check availability and contact you on ${_phone.text.trim()}. Reference ${b['code']}.'
                : (_payMessage ?? ''),
        textAlign: TextAlign.center,
      ),
      const Divider(height: 26),
      _line('Stay', '${prettyDate(b['check_in'] as String)} → ${prettyDate(b['check_out'] as String, year: true)}'),
      _line('Room', '${b['room']}'),
      _line('Guests', '${b['adults']} adult(s)${(b['children'] as num) > 0 ? ', ${b['children']} child(ren)' : ''}'),
      _line('Total', money(b['total'] as num)),
      if (confirmed) ...[
        _line('Paid', money(b['paid'] as num)),
        if ((b['balance'] as num) > 0) _line('Balance at the property', money(b['balance'] as num), bold: true),
      ],
    ]);
  }
}
