import 'package:flutter/material.dart';

import '../theme/app_fonts.dart';
import '../theme/app_theme.dart';

/// One date picker for the whole product (calendar, dashboard, reservations,
/// expenses, bookings, the guest booking page): a compact dialog about half
/// the screen wide, two months side by side, check-in / check-out boxes and a
/// night count — sized to its content, so no empty space above or below.
Future<DateTimeRange?> pickDateRange(
  BuildContext context, {
  DateTimeRange? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String help = 'Select dates',
  String startLabel = 'From',
  String endLabel = 'To',
  String save = 'Apply',

  /// Stays need at least one night (check-out after check-in).
  bool requireNights = false,
}) =>
    showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black38,
      builder: (_) => _PickerDialog(
        range: true,
        initialStart: initial?.start,
        initialEnd: initial?.end,
        firstDate: firstDate,
        lastDate: lastDate,
        help: help,
        startLabel: startLabel,
        endLabel: endLabel,
        save: save,
        requireNights: requireNights,
      ),
    ).then((v) => v);

/// Single date, same look as [pickDateRange].
Future<DateTime?> pickDate(
  BuildContext context, {
  DateTime? initial,
  required DateTime firstDate,
  required DateTime lastDate,
  String help = 'Select a date',
  String save = 'Apply',
}) async {
  final r = await showDialog<DateTimeRange>(
    context: context,
    barrierColor: Colors.black38,
    builder: (_) => _PickerDialog(
      range: false,
      initialStart: initial,
      firstDate: firstDate,
      lastDate: lastDate,
      help: help,
      startLabel: 'Date',
      endLabel: '',
      save: save,
    ),
  );
  return r?.start;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const _short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _weekdays = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

String _fmt(DateTime d) => '${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}, ${d.day} ${_short[d.month - 1]} ${d.year}';

class _PickerDialog extends StatefulWidget {
  const _PickerDialog({
    required this.range,
    this.initialStart,
    this.initialEnd,
    required this.firstDate,
    required this.lastDate,
    required this.help,
    required this.startLabel,
    required this.endLabel,
    required this.save,
    this.requireNights = false,
  });

  final bool range;
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final DateTime firstDate;
  final DateTime lastDate;
  final String help;
  final String startLabel;
  final String endLabel;
  final String save;
  final bool requireNights;

  @override
  State<_PickerDialog> createState() => _PickerDialogState();
}

class _PickerDialogState extends State<_PickerDialog> {
  late final DateTime _first = _day(widget.firstDate);
  late final DateTime _last = _day(widget.lastDate);
  DateTime? _start;
  DateTime? _end;
  DateTime? _hover;
  late DateTime _month; // first visible month

  @override
  void initState() {
    super.initState();
    DateTime? clamp(DateTime? d) => d == null ? null : (_day(d).isBefore(_first) ? _first : _day(d).isAfter(_last) ? _last : _day(d));
    _start = clamp(widget.initialStart);
    _end = widget.range ? clamp(widget.initialEnd) : null;
    if (_start != null && _end != null && _end!.isBefore(_start!)) _end = null;
    final anchor = _start ?? (DateTime.now().isBefore(_first) ? _first : DateTime.now().isAfter(_last) ? _last : DateTime.now());
    _month = DateTime(anchor.year, anchor.month);
  }

  bool _enabled(DateTime d) => !d.isBefore(_first) && !d.isAfter(_last);

  void _tap(DateTime d) {
    setState(() {
      if (!widget.range) {
        _start = d;
        return;
      }
      if (_start == null || _end != null) {
        _start = d;
        _end = null;
      } else if (d.isBefore(_start!)) {
        _start = d;
      } else if (d == _start && widget.requireNights) {
        // Same day can't be check-out; keep waiting for a later date.
      } else {
        _end = d;
      }
    });
  }

  bool get _complete => widget.range ? _start != null && _end != null && (!widget.requireNights || _end!.isAfter(_start!)) : _start != null;

  int get _nights => _start == null || _end == null ? 0 : _end!.difference(_start!).inDays;

  DateTime _addMonths(DateTime m, int n) => DateTime(m.year, m.month + n);

  bool get _canPrev => !_addMonths(_month, -1).isBefore(DateTime(_first.year, _first.month));

  bool _canNext(int shown) => !_addMonths(_month, shown).isAfter(DateTime(_last.year, _last.month));

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final width = (screen.width * 0.5).clamp(340.0, 760.0);
    final two = widget.range && width >= 640;
    final shown = two ? 2 : 1;
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: two ? width : width.clamp(340.0, 420.0), maxHeight: screen.height - 32),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < shown; i++) ...[
                  if (i > 0) const SizedBox(width: 24),
                  Expanded(child: _monthView(_addMonths(_month, i), first: i == 0, last: i == shown - 1, shown: shown)),
                ],
              ]),
            ),
            const Divider(height: 1),
            _footer(),
          ]),
        ),
      ),
    );
  }

  Widget _header() {
    Widget box(String label, DateTime? d, bool active) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: active ? AppTheme.sage.withValues(alpha: .45) : AppTheme.paper,
              border: Border.all(color: active ? AppTheme.forest : AppTheme.border, width: active ? 1.4 : 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label.toUpperCase(), style: AppFonts.sans(fontSize: 10.5, letterSpacing: .6, fontWeight: FontWeight.w700, color: AppTheme.muted)),
              const SizedBox(height: 2),
              Text(d == null ? 'Select date' : _fmt(d),
                  style: AppFonts.sans(fontSize: 14.5, fontWeight: FontWeight.w600, color: d == null ? AppTheme.hint : AppTheme.ink)),
            ]),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 8, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(widget.help, style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700))),
          IconButton(tooltip: 'Close', visualDensity: VisualDensity.compact, onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 20)),
        ]),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(children: [
            box(widget.startLabel, _start, widget.range ? (_start == null || _end != null) : true),
            if (widget.range) ...[
              const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward_rounded, size: 18, color: AppTheme.muted)),
              box(widget.endLabel, _end, _start != null && _end == null),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _monthView(DateTime month, {required bool first, required bool last, required int shown}) {
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final lead = DateTime(month.year, month.month).weekday - 1; // Monday first
    final today = _day(DateTime.now());
    final years = [for (var y = _first.year; y <= _last.year; y++) y];
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 40,
        child: Row(children: [
          if (first)
            IconButton(
              tooltip: 'Previous month',
              visualDensity: VisualDensity.compact,
              onPressed: _canPrev ? () => setState(() => _month = _addMonths(_month, -1)) : null,
              icon: const Icon(Icons.chevron_left_rounded),
            )
          else
            const SizedBox(width: 40),
          Expanded(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(_monthNames[month.month - 1], style: AppFonts.sans(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(width: 4),
              if (first && years.length > 1)
                PopupMenuButton<int>(
                  tooltip: 'Choose year',
                  initialValue: month.year,
                  onSelected: (y) => setState(() {
                    var m = DateTime(y, _month.month);
                    if (m.isBefore(DateTime(_first.year, _first.month))) m = DateTime(_first.year, _first.month);
                    if (m.isAfter(DateTime(_last.year, _last.month))) m = DateTime(_last.year, _last.month);
                    _month = m;
                  }),
                  itemBuilder: (_) => [for (final y in years.reversed) PopupMenuItem(value: y, height: 36, child: Text('$y'))],
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${month.year}', style: AppFonts.sans(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Icon(Icons.arrow_drop_down_rounded, size: 20),
                  ]),
                )
              else
                Text('${month.year}', style: AppFonts.sans(fontSize: 15, fontWeight: FontWeight.w700)),
            ]),
          ),
          if (last)
            IconButton(
              tooltip: 'Next month',
              visualDensity: VisualDensity.compact,
              onPressed: _canNext(shown) ? () => setState(() => _month = _addMonths(_month, 1)) : null,
              icon: const Icon(Icons.chevron_right_rounded),
            )
          else
            const SizedBox(width: 40),
        ]),
      ),
      const SizedBox(height: 4),
      Row(children: [
        for (final w in _weekdays)
          Expanded(child: Center(child: Text(w, style: AppFonts.sans(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.muted)))),
      ]),
      const SizedBox(height: 4),
      for (var row = 0; row < 6; row++)
        if (row * 7 - lead < days)
          Row(children: [
            for (var col = 0; col < 7; col++) Expanded(child: _cell(month, row * 7 + col - lead + 1, days, today)),
          ]),
    ]);
  }

  Widget _cell(DateTime month, int n, int days, DateTime today) {
    if (n < 1 || n > days) return const SizedBox(height: 40);
    final d = DateTime(month.year, month.month, n);
    final enabled = _enabled(d);
    final isStart = _start == d;
    final end = _end ?? (widget.range && _start != null && _hover != null && _hover!.isAfter(_start!) ? _hover : null);
    final isEnd = end == d && widget.range;
    final inRange = widget.range && _start != null && end != null && d.isAfter(_start!) && d.isBefore(end);
    final edge = isStart || isEnd;
    final band = widget.range && _start != null && end != null && (inRange || (isStart && end != _start) || (isEnd && end != _start));
    return MouseRegion(
      onEnter: (_) {
        if (widget.range && _start != null && _end == null) setState(() => _hover = d);
      },
      child: SizedBox(
        height: 40,
        child: Stack(alignment: Alignment.center, children: [
          if (band)
            Positioned.fill(
              top: 4,
              bottom: 4,
              left: isStart ? 20 : 0,
              right: isEnd ? 20 : 0,
              child: Container(color: AppTheme.sage.withValues(alpha: _end == null ? .4 : .75)),
            ),
          InkResponse(
            onTap: enabled ? () => _tap(d) : null,
            radius: 20,
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: edge ? AppTheme.forest : null,
                shape: BoxShape.circle,
                border: !edge && d == today ? Border.all(color: AppTheme.forest) : null,
              ),
              child: Text('$n',
                  style: AppFonts.sans(
                    fontSize: 13.5,
                    fontWeight: edge || d == today ? FontWeight.w700 : FontWeight.w500,
                    color: edge ? Colors.white : enabled ? AppTheme.ink : AppTheme.hint.withValues(alpha: .6),
                    decoration: enabled ? null : TextDecoration.lineThrough,
                  )),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _footer() {
    final summary = !widget.range
        ? (_start == null ? 'Pick a date' : _fmt(_start!))
        : _start == null
            ? 'Pick the first date'
            : _end == null
                ? 'Now pick the last date'
                : widget.requireNights
                    ? '$_nights night${_nights == 1 ? '' : 's'}'
                    : '${_nights + 1} day${_nights == 0 ? '' : 's'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(children: [
        TextButton(
          onPressed: _start == null ? null : () => setState(() => (_start = null, _end = null, _hover = null)),
          child: const Text('Clear'),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(summary, key: const Key('picker-summary'), style: AppFonts.sans(fontSize: 13.5, color: AppTheme.muted, fontWeight: FontWeight.w600))),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        const SizedBox(width: 8),
        ElevatedButton(
          key: const Key('picker-apply'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(96, 42)),
          onPressed: _complete ? () => Navigator.pop(context, DateTimeRange(start: _start!, end: widget.range ? _end! : _start!)) : null,
          child: Text(widget.save),
        ),
      ]),
    );
  }
}
