import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart';
import '../bookings/bookings_api.dart';

const double _dayW = 80;
const double _labelW = 230;
const double _headH = 58;
const double _laneH = 24;
const double _cellH = 50;

const _blockReasons = ['Maintenance', 'Owner stay', 'Offline booking', 'Renovation', 'Other'];

/// Host Control Center → Calendar: multi-property timeline of every room
/// (15 days at a time) with prices, availability, blocks and booking bars.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key, required this.api, required this.membership});

  final BookingsApi api;
  final Membership membership;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _Selection {
  _Selection(this.room, this.property, this.start, this.end);

  final CalendarRoom room;
  final CalendarProperty property;
  final int start; // day index, inclusive
  final int end; // day index, inclusive
}

class _CalendarScreenState extends State<CalendarScreen> {
  final _search = TextEditingController();
  final _hScroll = ScrollController();
  late DateTime _from;
  CalendarData? _data;
  String? _error;
  bool _loading = false;
  _Selection? _sel;
  final Set<int> _collapsed = {};

  bool get _canEdit => widget.membership.can('calendar.write');
  bool get _canBook => widget.membership.can('bookings.write');

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _from = DateTime(now.year, now.month, now.day);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _hScroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool keepSelection = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      if (!keepSelection) _sel = null;
    });
    try {
      final d = await widget.api.calendar(from: ymd(_from), search: _search.text.trim());
      if (!mounted) return;
      setState(() {
        _data = d;
        // Re-bind the selection to the fresh room data.
        final s = _sel;
        if (s != null) {
          _sel = null;
          for (final p in d.properties) {
            for (final r in p.rooms) {
              if (r.id == s.room.id) _sel = _Selection(r, p, s.start, s.end);
            }
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _shift(int days) {
    _from = _from.add(Duration(days: days));
    _load();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (d == null) return;
    _from = d;
    _load();
  }

  void _tapCell(CalendarProperty p, CalendarRoom r, int i) {
    final s = _sel;
    setState(() {
      if (s != null && s.room.id == r.id && s.start == s.end && i != s.start) {
        _sel = _Selection(r, p, i < s.start ? i : s.start, i < s.start ? s.start : i);
      } else if (s != null && s.room.id == r.id && s.start == i && s.end == i) {
        _sel = null;
      } else {
        _sel = _Selection(r, p, i, i);
      }
    });
  }

  Future<void> _openBooking(int id) async {
    final changed = await showBookingDetail(context, api: widget.api, bookingId: id, membership: widget.membership);
    if (changed == true) _load(keepSelection: true);
  }

  Future<void> _createBooking({int? roomId, String? checkIn, String? checkOut}) async {
    final b = await showCreateBookingDialog(context, api: widget.api, roomId: roomId, checkIn: checkIn, checkOut: checkOut);
    if (b == null || !mounted) return;
    showSnack(context, 'Booking ${b.code} created for ${b.guestName}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1100;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): () => _shift(-15),
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): () => _shift(15),
        const SingleActivator(LogicalKeyboardKey.escape): () => setState(() => _sel = null),
      },
      child: Focus(
        autofocus: true,
        child: Padding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 12, 18, wide ? 32 : 12, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _toolbar(wide),
            const SizedBox(height: 10),
            _legend(),
            const SizedBox(height: 10),
            Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: _body()),
                if (_sel != null && wide) ...[
                  const SizedBox(width: 14),
                  SizedBox(width: 340, child: _SelectionPanel(key: ValueKey('${_sel!.room.id}-${_sel!.start}-${_sel!.end}'), state: this)),
                ],
              ]),
            ),
            if (_sel != null && !wide) SizedBox(height: 320, child: _SelectionPanel(key: ValueKey('${_sel!.room.id}-${_sel!.start}-${_sel!.end}'), state: this)),
          ]),
        ),
      ),
    );
  }

  Widget _toolbar(bool wide) {
    final d = _data;
    final range = d == null ? '' : '${prettyDate(d.from)} – ${prettyDate(d.to, year: true)}';
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      SizedBox(
        width: wide ? 300 : double.infinity,
        child: TextField(
          key: const Key('calendar-search'),
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _load(),
          decoration: const InputDecoration(
            hintText: 'Search property, ID, city',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
      ),
      OutlinedButton.icon(
          key: const Key('prev-15'), onPressed: () => _shift(-15), icon: const Icon(Icons.chevron_left), label: const Text('Previous 15 days')),
      OutlinedButton.icon(onPressed: _pickStart, icon: const Icon(Icons.event_outlined), label: Text(range.isEmpty ? 'Pick date' : range)),
      OutlinedButton.icon(
          key: const Key('next-15'), onPressed: () => _shift(15), icon: const Icon(Icons.chevron_right), label: const Text('Next 15 days')),
      TextButton(
          onPressed: () {
            final n = DateTime.now();
            _from = DateTime(n.year, n.month, n.day);
            _load();
          },
          child: const Text('Today')),
      IconButton(tooltip: 'Refresh', onPressed: _loading ? null : () => _load(keepSelection: true), icon: const Icon(Icons.refresh)),
      if (_canBook)
        SizedBox(
          width: 210,
          child: ElevatedButton.icon(
            key: const Key('calendar-create-booking'),
            onPressed: () => _createBooking(),
            icon: const Icon(Icons.add),
            label: const Text('Create booking'),
          ),
        ),
    ]);
  }

  Widget _legend() {
    Widget dot(Color c, String t, {Color? border}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4), border: border == null ? null : Border.all(color: border))),
          const SizedBox(width: 6),
          Text(t, style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
        ]);
    return Wrap(spacing: 16, runSpacing: 6, children: [
      dot(Colors.white, 'Available', border: AppTheme.border),
      dot(AppTheme.sand, 'Sold out'),
      dot(const Color(0xFFE9E6E1), 'Blocked'),
      dot(AppTheme.forest, 'Confirmed'),
      dot(AppTheme.clay, 'Pending payment / hold'),
      dot(const Color(0xFF2F5C8A), 'Checked in'),
      Text('Tap a date to select it, tap another date in the same row for a range. Alt + ←/→ moves 15 days.',
          style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
    ]);
  }

  Widget _body() {
    final d = _data;
    if (d == null) {
      return Center(
        child: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, style: AppFonts.sans(color: AppTheme.danger)),
                TextButton(onPressed: _load, child: const Text('Try again')),
              ])
            : const CircularProgressIndicator(),
      );
    }
    if (d.properties.isEmpty) {
      return Center(
        child: Text(
          _search.text.isEmpty ? 'No rooms yet. Add rooms to a property to see them here.' : 'No properties match your search.',
          style: AppFonts.sans(color: AppTheme.muted),
        ),
      );
    }
    final today = ymd(DateTime.now());
    final rows = <({CalendarProperty p, CalendarRoom? r})>[];
    for (final p in d.properties) {
      rows.add((p: p, r: null));
      if (!_collapsed.contains(p.id)) {
        for (final r in p.rooms) {
          rows.add((p: p, r: r));
        }
      }
    }
    double rowH(({CalendarProperty p, CalendarRoom? r}) row) =>
        row.r == null ? 40 : _cellH + _laneH * _lanes(row.r!, d.days).$2.clamp(1, 99) + 6;

    return Container(
      decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        SingleChildScrollView(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Fixed room labels.
            SizedBox(
              width: _labelW,
              child: Column(children: [
                Container(
                  height: _headH,
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border), right: BorderSide(color: AppTheme.border))),
                  child: Text('${d.totalProperties} propert${d.totalProperties == 1 ? 'y' : 'ies'}',
                      style: AppFonts.sans(fontWeight: FontWeight.w600)),
                ),
                for (final row in rows) _label(row.p, row.r, rowH(row)),
              ]),
            ),
            // Scrollable days.
            Expanded(
              child: Scrollbar(
                controller: _hScroll,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _hScroll,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: d.days.length * _dayW,
                    child: Column(children: [
                      Row(children: [for (final day in d.days) _dayHead(day, day == today)]),
                      for (final row in rows)
                        row.r == null
                            ? Container(
                                height: 40,
                                decoration: const BoxDecoration(
                                    color: AppTheme.paper, border: Border(bottom: BorderSide(color: AppTheme.border))))
                            : _roomRow(row.p, row.r!, d.days, rowH(row), today),
                    ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
        if (_loading) const Positioned(top: 0, left: 0, right: 0, child: LinearProgressIndicator(minHeight: 2)),
      ]),
    );
  }

  Widget _label(CalendarProperty p, CalendarRoom? r, double h) {
    if (r == null) {
      final collapsed = _collapsed.contains(p.id);
      return InkWell(
        onTap: () => setState(() => collapsed ? _collapsed.remove(p.id) : _collapsed.add(p.id)),
        child: Container(
          height: h,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: const BoxDecoration(
              color: AppTheme.paper, border: Border(bottom: BorderSide(color: AppTheme.border), right: BorderSide(color: AppTheme.border))),
          child: Row(children: [
            Icon(collapsed ? Icons.chevron_right : Icons.expand_more, size: 18),
            const SizedBox(width: 4),
            Expanded(
              child: Text(p.title.isEmpty ? 'Untitled property' : p.title,
                  overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
            Text(p.serialId.isEmpty ? '' : p.serialId.split('-').last, style: AppFonts.sans(fontSize: 11.5, color: AppTheme.muted)),
          ]),
        ),
      );
    }
    return Container(
      height: h,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.border), right: BorderSide(color: AppTheme.border))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(r.name, overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontWeight: FontWeight.w600, fontSize: 14)),
        const SizedBox(height: 2),
        Text('${r.units} unit${r.units == 1 ? '' : 's'} · up to ${r.maxGuests} guests · ${r.occupancy}% booked',
            overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
      ]),
    );
  }

  Widget _dayHead(String day, bool isToday) {
    final dt = parseYmd(day);
    final weekend = dt.weekday >= 6;
    return Container(
      width: _dayW,
      height: _headH,
      decoration: BoxDecoration(
        color: isToday ? AppTheme.sage : (weekend ? const Color(0xFFFBFAF6) : Colors.white),
        border: const Border(bottom: BorderSide(color: AppTheme.border), right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(weekdays[dt.weekday - 1], style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
        Text(prettyDate(day),
            style: AppFonts.sans(fontSize: 13.5, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500, color: AppTheme.ink)),
      ]),
    );
  }

  /// Assigns each booking bar to a lane so overlapping stays don't cover each other.
  (List<int>, int) _lanes(CalendarRoom r, List<String> days) {
    final ends = <String>[];
    final lanes = <int>[];
    final sorted = [...r.bookings]..sort((a, b) => a.checkIn.compareTo(b.checkIn));
    final laneOf = <int, int>{};
    for (final b in sorted) {
      var lane = ends.indexWhere((e) => e.compareTo(b.checkIn) <= 0);
      if (lane == -1) {
        ends.add(b.checkOut);
        lane = ends.length - 1;
      } else {
        ends[lane] = b.checkOut;
      }
      laneOf[b.id] = lane;
    }
    for (final b in r.bookings) {
      lanes.add(laneOf[b.id]!);
    }
    return (lanes, ends.length);
  }

  Widget _roomRow(CalendarProperty p, CalendarRoom r, List<String> days, double h, String today) {
    final sel = _sel;
    final (lanes, _) = _lanes(r, days);
    final first = days.first;
    final afterLast = ymd(parseYmd(days.last).add(const Duration(days: 1)));
    return SizedBox(
      height: h,
      child: Stack(children: [
        Row(children: [
          for (var i = 0; i < r.cells.length; i++)
            _cell(p, r, i, r.cells[i], selected: sel != null && sel.room.id == r.id && i >= sel.start && i <= sel.end, past: r.cells[i].date.compareTo(today) < 0, h: h),
        ]),
        for (var k = 0; k < r.bookings.length; k++)
          if (r.bookings[k].checkOut.compareTo(first) > 0 && r.bookings[k].checkIn.compareTo(afterLast) < 0)
            _bar(r.bookings[k], lanes[k], first, days.length),
      ]),
    );
  }

  Widget _cell(CalendarProperty p, CalendarRoom r, int i, CalendarCell c, {required bool selected, required bool past, required double h}) {
    final soldOut = !c.blocked && c.available <= 0;
    final bg = selected
        ? const Color(0xFFDCE6D3)
        : c.blocked
            ? const Color(0xFFE9E6E1)
            : soldOut
                ? AppTheme.sand
                : Colors.white;
    return Tooltip(
      message: c.blocked
          ? 'Blocked${c.blockReason == null || c.blockReason!.isEmpty ? '' : ' · ${c.blockReason}'}${c.blockNotes == null || c.blockNotes!.isEmpty ? '' : '\n${c.blockNotes}'}'
          : '${c.available} of ${c.units} available · ${money(c.price)}${c.customPrice ? ' (custom)' : ''}',
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        key: Key('cell-${r.id}-${c.date}'),
        onTap: () => _tapCell(p, r, i),
        child: Container(
          width: _dayW,
          height: h,
          padding: const EdgeInsets.only(top: 6),
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              bottom: const BorderSide(color: AppTheme.border),
              right: const BorderSide(color: AppTheme.border),
              top: selected ? const BorderSide(color: AppTheme.forest, width: 1.5) : BorderSide.none,
            ),
          ),
          child: Opacity(
            opacity: past ? 0.55 : 1,
            child: Column(children: [
              Text(money(c.price),
                  style: AppFonts.sans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.customPrice ? AppTheme.clay : AppTheme.ink,
                      decoration: c.blocked ? TextDecoration.lineThrough : null)),
              Text(c.blocked ? 'Blocked' : soldOut ? 'Sold out' : '${c.available} left',
                  style: AppFonts.sans(fontSize: 11.5, color: c.blocked ? AppTheme.danger : AppTheme.muted)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _bar(BookingBar b, int lane, String first, int dayCount) {
    final start = parseYmd(b.checkIn).difference(parseYmd(first)).inDays;
    final end = parseYmd(b.checkOut).difference(parseYmd(first)).inDays;
    // Bars run from mid check-in day to mid check-out day (like the calendar reference).
    final left = (start * _dayW + _dayW / 2).clamp(0.0, dayCount * _dayW);
    final right = (end * _dayW + _dayW / 2).clamp(0.0, dayCount * _dayW);
    final color = switch (b.status) {
      'checked_in' => const Color(0xFF2F5C8A),
      'pending_payment' || 'held' || 'inquiry' => AppTheme.clay,
      'checked_out' => AppTheme.muted,
      _ => AppTheme.forest,
    };
    final label = '${b.status == 'held' ? 'On hold · ' : b.status == 'pending_payment' ? 'Booking request · ' : ''}'
        '${b.guestName} · ${b.guests}';
    return Positioned(
      left: left + 2,
      width: (right - left - 4).clamp(16.0, double.infinity),
      top: _cellH + lane * _laneH,
      height: _laneH - 4,
      child: Tooltip(
        message: '${b.guestName} · ${b.code}\n${prettyDate(b.checkIn)} → ${prettyDate(b.checkOut)} · ${bookingSources[b.source] ?? b.source}'
            '${b.balance > 0 ? '\nBalance ${money(b.balance)}' : ''}',
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: Key('bar-${b.id}'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => _openBooking(b.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                if (b.balance > 0) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.currency_rupee, size: 12, color: Colors.white)),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sans(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Side panel for a selected date range: availability (block / unblock with a
/// reason), pricing (fixed or ±%), and Create booking.
class _SelectionPanel extends StatefulWidget {
  const _SelectionPanel({super.key, required this.state});

  final _CalendarScreenState state;

  @override
  State<_SelectionPanel> createState() => _SelectionPanelState();
}

class _SelectionPanelState extends State<_SelectionPanel> {
  final _price = TextEditingController();
  final _notes = TextEditingController();
  String _reason = _blockReasons.first;
  bool _percent = false;
  bool _busy = false;
  final Set<int> _days = {}; // 0=Sun..6=Sat, empty = every day

  _CalendarScreenState get s => widget.state;
  _Selection get sel => s._sel!;
  List<CalendarCell> get cells => sel.room.cells.sublist(sel.start, sel.end + 1);
  String get from => cells.first.date;
  String get to => cells.last.date;

  @override
  void initState() {
    super.initState();
    final blocked = cells.where((c) => c.blocked).toList();
    if (blocked.isNotEmpty) {
      final r = blocked.first.blockReason;
      if (r != null && _blockReasons.contains(r)) _reason = r;
      _notes.text = blocked.first.blockNotes ?? '';
    }
  }

  @override
  void dispose() {
    _price.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<int>? get _dow => _days.isEmpty ? null : (_days.toList()..sort());

  Future<void> _do(Future<void> Function() call, String done) async {
    setState(() => _busy = true);
    try {
      await call();
      if (!mounted) return;
      showSnack(context, done);
      await s._load(keepSelection: true);
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allBlocked = cells.every((c) => c.blocked);
    final anyBlocked = cells.any((c) => c.blocked);
    final anyBooked = cells.any((c) => c.booked > 0);
    final n = cells.length;
    final api = s.widget.api;
    final ids = [sel.room.id];
    return Container(
      decoration: BoxDecoration(
          color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text(sel.room.name, style: AppFonts.sans(fontSize: 17, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Clear selection', onPressed: () => s.setState(() => s._sel = null), icon: const Icon(Icons.close)),
        ]),
        Text('${sel.property.title} · ${prettyDate(from)}${n > 1 ? ' – ${prettyDate(to)}' : ''} · $n day${n == 1 ? '' : 's'}',
            style: AppFonts.sans(fontSize: 13.5, color: AppTheme.muted)),
        if (n > 1) ...[
          const SizedBox(height: 10),
          Text('Apply to', style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
          const SizedBox(height: 4),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final (i, d) in const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexed)
              FilterChip(
                label: Text(d),
                visualDensity: VisualDensity.compact,
                selected: _days.contains(i),
                onSelected: (v) => setState(() => v ? _days.add(i) : _days.remove(i)),
              ),
          ]),
          Text(_days.isEmpty ? 'Every day in the range' : 'Only the selected weekdays',
              style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
        ],
        const Divider(height: 28),
        Text('Availability', style: AppFonts.sans(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (anyBooked && !allBlocked)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Some of these dates have bookings. Blocking only stops new bookings.',
                style: AppFonts.sans(fontSize: 12.5, color: AppTheme.warningInk)),
          ),
        DropdownButtonFormField<String>(
          initialValue: _reason,
          decoration: const InputDecoration(labelText: 'Reason', isDense: true),
          items: [for (final r in _blockReasons) DropdownMenuItem(value: r, child: Text(r))],
          onChanged: s._canEdit ? (v) => setState(() => _reason = v ?? _blockReasons.first) : null,
        ),
        const SizedBox(height: 8),
        TextField(
            controller: _notes,
            enabled: s._canEdit,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes for your team', isDense: true)),
        const SizedBox(height: 10),
        if (s._canEdit)
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (!allBlocked)
              OutlinedButton.icon(
                key: const Key('block-dates'),
                onPressed: _busy
                    ? null
                    : () => _do(() => api.block(ids, from, to, reason: _reason, notes: _notes.text.trim(), days: _dow),
                        'Blocked ${prettyDate(from)}${n > 1 ? ' – ${prettyDate(to)}' : ''}'),
                icon: const Icon(Icons.block, size: 18),
                label: const Text('Block'),
              ),
            if (anyBlocked)
              OutlinedButton.icon(
                key: const Key('unblock-dates'),
                onPressed: _busy ? null : () => _do(() => api.unblock(ids, from, to, days: _dow), 'Dates opened for booking'),
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Unblock'),
              ),
            if (anyBlocked)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _do(() => api.updateBlockReason(ids, from, to, reason: _reason, notes: _notes.text.trim()), 'Block reason updated'),
                child: const Text('Save reason'),
              ),
          ]),
        const Divider(height: 28),
        Text('Pricing', style: AppFonts.sans(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('Base ${money(sel.room.basePrice)} / night', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Set price')),
            ButtonSegment(value: true, label: Text('Adjust by %')),
          ],
          selected: {_percent},
          onSelectionChanged: (v) => setState(() => _percent = v.first),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('rate-value'),
          controller: _price,
          enabled: s._canEdit,
          keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]'))],
          decoration: InputDecoration(
            labelText: _percent ? 'Change (%) e.g. 10 or -15' : 'Price per night (₹)',
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        if (s._canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              key: const Key('apply-rate'),
              onPressed: _busy
                  ? null
                  : () {
                      final v = double.tryParse(_price.text.trim());
                      if (v == null) return showSnack(context, 'Enter a number');
                      _do(() async {
                        final updated = await api.setRates(ids, from, to, price: _percent ? null : v, percent: _percent ? v : null, days: _dow);
                        if (updated == 0) throw ApiException('No dates matched the selected weekdays');
                      }, 'Price updated');
                    },
              child: const Text('Apply price'),
            ),
          ),
        if (s._canBook) ...[
          const Divider(height: 28),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              key: const Key('book-selection'),
              onPressed: allBlocked
                  ? null
                  : () => s._createBooking(
                        roomId: sel.room.id,
                        checkIn: from,
                        checkOut: ymd(parseYmd(to).add(const Duration(days: 1))),
                      ),
              icon: const Icon(Icons.add),
              label: Text('Book ${n == 1 ? '1 night' : '$n nights'}'),
            ),
          ),
        ],
      ]),
    );
  }
}
