import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_models.dart';
import 'bookings_api.dart';

void showSnack(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

String errorText(Object e) => e is ApiException ? e.message : 'Something went wrong. Try again.';

/// Coloured pill for a booking status.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.label});

  final String status;
  final String? label;

  static (Color, Color) colors(String status) => switch (status) {
        'confirmed' || 'paid' => (AppTheme.successSoft, AppTheme.success),
        'checked_in' || 'ongoing' => (const Color(0xFFDDE8F3), const Color(0xFF2F5C8A)),
        'pending_payment' || 'held' || 'pending' || 'partial' || 'upcoming' => (AppTheme.warningSoft, AppTheme.warningInk),
        'cancelled' || 'expired' || 'no_show' => (AppTheme.dangerSoft, AppTheme.danger),
        _ => (AppTheme.sage, AppTheme.inkSoft),
      };

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = colors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label ?? statusLabels[status] ?? status,
          style: AppFonts.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

typedef RoomCatalog = List<({int id, String title, List<({int id, String name, int maxGuests})> rooms})>;

/// Create Booking (calendar selection or Reservations button). Returns the
/// new booking, or null when dismissed.
Future<Booking?> showCreateBookingDialog(
  BuildContext context, {
  required BookingsApi api,
  int? roomId,
  String? checkIn,
  String? checkOut,
}) =>
    showDialog<Booking>(
      context: context,
      builder: (_) => _CreateBookingDialog(api: api, roomId: roomId, checkIn: checkIn, checkOut: checkOut),
    );

class _CreateBookingDialog extends StatefulWidget {
  const _CreateBookingDialog({required this.api, this.roomId, this.checkIn, this.checkOut});

  final BookingsApi api;
  final int? roomId;
  final String? checkIn;
  final String? checkOut;

  @override
  State<_CreateBookingDialog> createState() => _CreateBookingDialogState();
}

class _CreateBookingDialogState extends State<_CreateBookingDialog> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _notes = TextEditingController();
  final _advance = TextEditingController();
  final _total = TextEditingController();

  RoomCatalog? _catalog;
  int? _roomId;
  late DateTime _in;
  late DateTime _out;
  int _adults = 2;
  int _children = 0;
  String _source = 'phone';
  String _method = 'cash';
  bool _hold = false;
  Map<String, dynamic>? _quote;
  String? _error;
  bool _saving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _in = widget.checkIn != null ? parseYmd(widget.checkIn!) : DateTime(today.year, today.month, today.day);
    _out = widget.checkOut != null ? parseYmd(widget.checkOut!) : _in.add(const Duration(days: 1));
    _roomId = widget.roomId;
    widget.api.roomCatalog().then((c) {
      if (!mounted) return;
      setState(() {
        _catalog = c;
        _roomId ??= c.isNotEmpty ? c.first.rooms.first.id : null;
      });
      _refreshQuote();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = errorText(e));
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    for (final c in [_name, _phone, _email, _notes, _advance, _total]) {
      c.dispose();
    }
    super.dispose();
  }

  void _refreshQuote() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      if (_roomId == null) return;
      try {
        final q = await widget.api.quote({
          'room_id': _roomId,
          'check_in': ymd(_in),
          'check_out': ymd(_out),
          'adults': _adults,
          'children': _children,
        });
        if (mounted) setState(() => _quote = q);
      } catch (e) {
        if (mounted) setState(() => _quote = {'available': false, 'detail': errorText(e)});
      }
    });
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
      initialDateRange: DateTimeRange(start: _in, end: _out),
      helpText: 'Check-in and check-out',
    );
    if (r == null || !r.end.isAfter(r.start)) return;
    setState(() {
      _in = r.start;
      _out = r.end;
    });
    _refreshQuote();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate() || _roomId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final advance = double.tryParse(_advance.text.trim()) ?? 0;
      final b = await widget.api.create({
        'room_id': _roomId,
        'check_in': ymd(_in),
        'check_out': ymd(_out),
        'guest': {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim()},
        'adults': _adults,
        'children': _children,
        'source': _source,
        'notes': _notes.text.trim(),
        if (_hold) 'hold': true,
        if (_total.text.trim().isNotEmpty) 'total': double.parse(_total.text.trim()),
        if (!_hold && advance > 0) 'payment': {'amount': advance, 'method': _method},
      });
      if (mounted) Navigator.of(context).pop(b);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _counter(String label, int value, int min, ValueChanged<int> onChanged) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: AppFonts.sans(fontSize: 14)),
        IconButton(
            tooltip: 'Fewer $label',
            onPressed: value > min ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove_circle_outline)),
        Text('$value', style: AppFonts.sans(fontWeight: FontWeight.w600)),
        IconButton(tooltip: 'More $label', onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
      ]);

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final q = _quote;
    final available = q?['available'] == true;
    return AlertDialog(
      title: const Text('Create booking'),
      content: SizedBox(
        width: 520,
        child: catalog == null
            ? (_error != null ? Text(_error!) : const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())))
            : catalog.isEmpty
                ? const Text('Add a property with at least one room before taking bookings.')
                : Form(
                    key: _form,
                    child: SingleChildScrollView(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        DropdownButtonFormField<int>(
                          key: const Key('booking-room'),
                          initialValue: _roomId,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Room'),
                          items: [
                            for (final p in catalog)
                              for (final r in p.rooms)
                                DropdownMenuItem(value: r.id, child: Text('${p.title} · ${r.name}', overflow: TextOverflow.ellipsis)),
                          ],
                          onChanged: (v) {
                            setState(() => _roomId = v);
                            _refreshQuote();
                          },
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          key: const Key('booking-dates'),
                          onPressed: _pickDates,
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                              '${prettyDate(ymd(_in), year: true)} → ${prettyDate(ymd(_out), year: true)} · ${_out.difference(_in).inDays} night(s)'),
                        ),
                        const SizedBox(height: 4),
                        Wrap(spacing: 12, children: [
                          _counter('Adults', _adults, 1, (v) {
                            setState(() => _adults = v);
                            _refreshQuote();
                          }),
                          _counter('Children', _children, 0, (v) {
                            setState(() => _children = v);
                            _refreshQuote();
                          }),
                        ]),
                        const SizedBox(height: 8),
                        TextFormField(
                          key: const Key('guest-name'),
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Guest name'),
                          validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the guest name' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: TextFormField(
                              key: const Key('guest-phone'),
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(labelText: 'Phone'),
                              validator: (v) =>
                                  (v ?? '').trim().isEmpty && _email.text.trim().isEmpty ? 'Phone or email needed' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(labelText: 'Email (optional)'),
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _source,
                          decoration: const InputDecoration(labelText: 'Booked via'),
                          items: [for (final e in bookingSources.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                          onChanged: (v) => setState(() => _source = v ?? 'phone'),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _hold,
                          onChanged: (v) => setState(() => _hold = v),
                          title: const Text('Hold for 15 minutes'),
                          subtitle: const Text('Keeps the dates while the guest pays; releases automatically.'),
                        ),
                        if (!_hold)
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                key: const Key('advance'),
                                controller: _advance,
                                keyboardType: TextInputType.number,
                                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                                decoration: const InputDecoration(labelText: 'Advance received (₹)'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _method,
                                decoration: const InputDecoration(labelText: 'Paid by'),
                                items: [for (final e in paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                                onChanged: (v) => setState(() => _method = v ?? 'cash'),
                              ),
                            ),
                          ]),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _total,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: InputDecoration(
                              labelText: 'Total override (₹, optional)',
                              helperText: q != null && available ? 'Calculated total: ${money(q['total'] as num)}' : null),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
                        const SizedBox(height: 14),
                        if (q != null) _QuoteBox(q),
                        if (_error != null) ...[
                          const SizedBox(height: 10),
                          Text(_error!, style: AppFonts.sans(color: AppTheme.danger)),
                        ],
                      ]),
                    ),
                  ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        SizedBox(
          width: 170,
          child: ElevatedButton(
            key: const Key('save-booking'),
            onPressed: _saving || catalog == null || catalog.isEmpty || !available ? null : _save,
            child: Text(_saving ? 'Saving…' : _hold ? 'Hold dates' : 'Create booking'),
          ),
        ),
      ],
    );
  }
}

class _QuoteBox extends StatelessWidget {
  const _QuoteBox(this.q);

  final Map<String, dynamic> q;

  @override
  Widget build(BuildContext context) {
    if (q['available'] != true) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppTheme.dangerSoft, borderRadius: BorderRadius.circular(10)),
        child: Text((q['detail'] as String?) ?? 'Not available for these dates',
            style: AppFonts.sans(color: AppTheme.danger, fontWeight: FontWeight.w500)),
      );
    }
    final extra = (q['extra_guest_charge'] as num?) ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.sage, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _line('${q['nights']} night(s)', money(q['stay'] as num)),
        if (extra > 0) _line('${q['extra_guests']} extra guest(s)', money(extra)),
        const Divider(),
        _line('Total', money(q['total'] as num), bold: true),
      ]),
    );
  }

  Widget _line(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(a, style: AppFonts.sans(fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
          Text(b, style: AppFonts.sans(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
        ]),
      );
}

/// Booking detail: guest, stay, money, actions, payments and timeline.
/// Returns true when the booking changed.
Future<bool?> showBookingDetail(BuildContext context,
        {required BookingsApi api, required int bookingId, required Membership membership}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _BookingDetail(api: api, id: bookingId, membership: membership),
    );

class _BookingDetail extends StatefulWidget {
  const _BookingDetail({required this.api, required this.id, required this.membership});

  final BookingsApi api;
  final int id;
  final Membership membership;

  @override
  State<_BookingDetail> createState() => _BookingDetailState();
}

class _BookingDetailState extends State<_BookingDetail> {
  Booking? _b;
  String? _error;
  bool _busy = false;
  bool _changed = false;

  bool get _canWrite => widget.membership.can('bookings.write');
  bool get _canCancel => widget.membership.can('bookings.cancel');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final b = await widget.api.get(widget.id);
      if (mounted) setState(() => _b = b);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _run(Future<Booking> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      final b = await call();
      if (!mounted) return;
      setState(() {
        _b = b;
        _changed = true;
      });
      showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reason = await _ask('Cancel booking', 'Reason (guest sees nothing — this is for your records)', minLength: 3);
    if (reason == null) return;
    await _run(() => widget.api.action(widget.id, 'cancel', {'reason': reason}), 'Booking cancelled — dates released');
  }

  Future<void> _payment({bool refund = false}) async {
    final b = _b!;
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _PaymentDialog(refund: refund, suggested: refund ? b.paid : b.balance),
    );
    if (r == null) return;
    await _run(() => widget.api.addPayment(widget.id, {...r, if (refund) 'kind': 'refund'}),
        refund ? 'Refund recorded' : 'Payment recorded');
  }

  Future<void> _edit() async {
    final b = _b!;
    final r = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => _EditDialog(b: b));
    if (r == null || r.isEmpty) return;
    await _run(() => widget.api.update(widget.id, r), 'Booking updated');
  }

  Future<String?> _ask(String title, String label, {int minLength = 0}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: TextField(
              key: const Key('reason-field'), controller: c, autofocus: true, maxLines: 2, decoration: InputDecoration(labelText: label)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          TextButton(
            key: const Key('reason-confirm'),
            onPressed: () {
              if (c.text.trim().length < minLength) return;
              Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final b = _b;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
        title: Row(children: [
          Expanded(child: Text(b == null ? 'Booking' : '${b.guestName} · ${b.code}')),
          if (b != null) StatusPill(b.status),
          IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(_changed), icon: const Icon(Icons.close)),
        ]),
        content: SizedBox(
          width: 620,
          child: b == null
              ? (_error != null ? Text(_error!) : const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())))
              : SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (b.status == 'held' && b.holdExpiresAt != null)
                      _Banner('Dates on hold until ${b.holdExpiresAt!.substring(11, 16)} UTC. Record a payment or confirm to keep them.'),
                    _section('Stay', [
                      _kv('Property', b.propertyTitle),
                      _kv('Room', b.roomName),
                      _kv('Dates', '${prettyDate(b.checkIn, year: true)} → ${prettyDate(b.checkOut, year: true)} · ${b.nights} night(s)'),
                      _kv('Guests', '${b.adults} adult(s)${b.children > 0 ? ', ${b.children} child(ren)' : ''}'),
                      _kv('Booked via', b.sourceLabel.isEmpty ? (bookingSources[b.source] ?? b.source) : b.sourceLabel),
                      _kv('Booked on', b.bookedAt.length >= 10 ? prettyDate(b.bookedAt.substring(0, 10), year: true) : ''),
                    ]),
                    _section('Guest', [
                      _kv('Name', b.guestName),
                      if (b.guestPhone.isNotEmpty) _kv('Phone', b.guestPhone),
                      if (b.guestEmail.isNotEmpty) _kv('Email', b.guestEmail),
                      if (b.notes.isNotEmpty) _kv('Notes', b.notes),
                    ]),
                    _section('Payment', [
                      _kv('Total', money(b.total)),
                      _kv('Paid', money(b.paid)),
                      _kv('Balance', money(b.balance)),
                      Padding(padding: const EdgeInsets.only(top: 4), child: Align(alignment: Alignment.centerLeft, child: StatusPill(b.paymentStatus, label: _payLabel(b.paymentStatus)))),
                      for (final p in b.payments)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            '${p.kind == 'refund' ? 'Refund' : 'Payment'} ${money(p.amount)} · ${paymentMethods[p.method] ?? p.method}'
                            '${p.at.length >= 10 ? ' · ${prettyDate(p.at.substring(0, 10))}' : ''}${p.by.isEmpty ? '' : ' · ${p.by}'}',
                            style: AppFonts.sans(fontSize: 13.5, color: AppTheme.muted),
                          ),
                        ),
                    ]),
                    if (b.cancelReason != null) _section('Cancellation', [Text(b.cancelReason!)]),
                    _section('Activity', [
                      for (final e in b.events.reversed)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Text(
                            '${e.at.length >= 16 ? '${prettyDate(e.at.substring(0, 10))} ${e.at.substring(11, 16)}' : e.at} · '
                            '${e.action.replaceAll('_', ' ')}${e.detail.isEmpty ? '' : ' — ${e.detail}'}${e.by.isEmpty ? '' : ' · ${e.by}'}',
                            style: AppFonts.sans(fontSize: 13.5, color: AppTheme.muted),
                          ),
                        ),
                    ]),
                  ]),
                ),
        ),
        actionsAlignment: MainAxisAlignment.start,
        actions: b == null || !_canWrite
            ? null
            : [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (['held', 'pending_payment', 'inquiry'].contains(b.status))
                    _btn('Confirm', () => _run(() => widget.api.action(b.id, 'confirm'), 'Booking confirmed')),
                  if (b.status == 'confirmed' || b.status == 'pending_payment')
                    _btn('Check in', () => _run(() => widget.api.action(b.id, 'check-in'), 'Guest checked in')),
                  if (b.status == 'checked_in')
                    _btn('Check out', () => _run(() => widget.api.action(b.id, 'check-out'), 'Guest checked out')),
                  if (b.balance > 0 && b.isOpen) _btn('Record payment', _payment, key: const Key('record-payment')),
                  if (b.paid > 0) _btn('Refund', () => _payment(refund: true)),
                  if (b.isOpen) _btn('Edit', _edit),
                  if (b.status == 'confirmed' || b.status == 'pending_payment')
                    _btn('No-show', () => _run(() => widget.api.action(b.id, 'no-show'), 'Marked as no-show')),
                  if (_canCancel && b.isOpen) _btn('Cancel booking', _cancel, danger: true, key: const Key('cancel-booking')),
                ]),
              ],
      ),
    );
  }

  static String _payLabel(String s) => switch (s) { 'paid' => 'Paid', 'partial' => 'Part paid', _ => 'Payment pending' };

  Widget _btn(String label, VoidCallback onTap, {bool danger = false, Key? key}) => OutlinedButton(
        key: key,
        onPressed: _busy ? null : onTap,
        style: danger ? OutlinedButton.styleFrom(foregroundColor: AppTheme.danger) : null,
        child: Text(label),
      );

  Widget _section(String title, List<Widget> children) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: AppFonts.sans(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(k, style: AppFonts.sans(color: AppTheme.muted, fontSize: 14))),
          Expanded(child: Text(v, style: AppFonts.sans(fontSize: 14))),
        ]),
      );
}

class _Banner extends StatelessWidget {
  const _Banner(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppTheme.warningSoft, borderRadius: BorderRadius.circular(10)),
        child: Text(text, style: AppFonts.sans(color: AppTheme.warningInk, fontSize: 13.5)),
      );
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.refund, required this.suggested});

  final bool refund;
  final double suggested;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  late final _amount = TextEditingController(text: widget.suggested > 0 ? widget.suggested.toStringAsFixed(0) : '');
  final _ref = TextEditingController();
  String _method = 'cash';

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.refund ? 'Record refund' : 'Record payment'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              key: const Key('payment-amount'),
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Amount (₹)'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [for (final e in paymentMethods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _method = v ?? 'cash'),
            ),
            const SizedBox(height: 12),
            TextField(controller: _ref, decoration: const InputDecoration(labelText: 'Reference (UPI / txn id, optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          TextButton(
            key: const Key('payment-save'),
            onPressed: () {
              final a = double.tryParse(_amount.text.trim()) ?? 0;
              if (a <= 0) return;
              Navigator.pop(context, {'amount': a, 'method': _method, 'reference': _ref.text.trim()});
            },
            child: const Text('Save'),
          ),
        ],
      );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({required this.b});

  final Booking b;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final _name = TextEditingController(text: widget.b.guestName);
  late final _phone = TextEditingController(text: widget.b.guestPhone);
  late final _email = TextEditingController(text: widget.b.guestEmail);
  late final _notes = TextEditingController(text: widget.b.notes);
  late DateTime _in = parseYmd(widget.b.checkIn);
  late DateTime _out = parseYmd(widget.b.checkOut);
  late int _adults = widget.b.adults;
  late int _children = widget.b.children;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit booking'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final r = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 2),
                    initialDateRange: DateTimeRange(start: _in, end: _out),
                  );
                  if (r != null && r.end.isAfter(r.start)) {
                    setState(() {
                      _in = r.start;
                      _out = r.end;
                    });
                  }
                },
                icon: const Icon(Icons.date_range_outlined),
                label: Text('${prettyDate(ymd(_in), year: true)} → ${prettyDate(ymd(_out), year: true)}'),
              ),
              const SizedBox(height: 8),
              Text('Changing dates re-checks availability and re-prices the stay.',
                  style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    child: DropdownButtonFormField<int>(
                        initialValue: _adults,
                        decoration: const InputDecoration(labelText: 'Adults'),
                        items: [for (var i = 1; i <= 20; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                        onChanged: (v) => setState(() => _adults = v ?? 1))),
                const SizedBox(width: 12),
                Expanded(
                    child: DropdownButtonFormField<int>(
                        initialValue: _children,
                        decoration: const InputDecoration(labelText: 'Children'),
                        items: [for (var i = 0; i <= 10; i++) DropdownMenuItem(value: i, child: Text('$i'))],
                        onChanged: (v) => setState(() => _children = v ?? 0))),
              ]),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Guest name')),
              const SizedBox(height: 12),
              TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone')),
              const SizedBox(height: 12),
              TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 12),
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Back')),
          TextButton(
            onPressed: () {
              final b = widget.b;
              final out = <String, dynamic>{};
              final guest = {'name': _name.text.trim(), 'phone': _phone.text.trim(), 'email': _email.text.trim()};
              if (guest['name'] != b.guestName || guest['phone'] != b.guestPhone || guest['email'] != b.guestEmail) out['guest'] = guest;
              if (_notes.text.trim() != b.notes) out['notes'] = _notes.text.trim();
              if (ymd(_in) != b.checkIn || ymd(_out) != b.checkOut) {
                out['check_in'] = ymd(_in);
                out['check_out'] = ymd(_out);
              }
              if (_adults != b.adults || _children != b.children) {
                out['adults'] = _adults;
                out['children'] = _children;
              }
              Navigator.pop(context, out);
            },
            child: const Text('Save'),
          ),
        ],
      );
}
