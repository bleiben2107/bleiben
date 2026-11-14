import 'package:flutter/material.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart';
import '../bookings/bookings_api.dart';

const _periods = {
  'last_7': 'Last 7 days',
  'last_30': 'Last 30 days',
  'last_60': 'Last 60 days',
  'next_7': 'Next 7 days',
  'next_30': 'Next 30 days',
  'next_60': 'Next 60 days',
  'custom': 'Custom range',
};

const _countBy = {'check_in': 'Check-in date', 'check_out': 'Check-out date', 'booked': 'Booking date'};

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _compact(num v) {
  final a = v.abs();
  final s = v < 0 ? '-' : '';
  if (a >= 10000000) return '$s₹${(a / 10000000).toStringAsFixed(1)}Cr';
  if (a >= 100000) return '$s₹${(a / 100000).toStringAsFixed(1)}L';
  if (a >= 1000) return '$s₹${(a / 1000).toStringAsFixed(1)}k';
  return money(v);
}

/// Host Control Center → Dashboard (REA 08 §1, tutorial-validated layout):
/// quick actions, filter row, six KPI cards against the previous period,
/// a right-hand Today column, sources, where money goes, properties ranking,
/// revenue & expenses by month and a 13-week occupancy outlook.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.api,
    required this.membership,
    required this.hostName,
    required this.onOpenSection,
    required this.onAddExpense,
  });

  final BookingsApi api;
  final Membership membership;
  final String hostName;
  final ValueChanged<String> onOpenSection;
  final VoidCallback onAddExpense;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String _period = 'last_30';
  String _count = 'check_in';
  DateTimeRange? _custom;
  String _city = '';
  String _property = '';
  int? _year;
  Map<String, dynamic>? _d;
  String? _error;
  bool _loading = false;
  String _sourcesBy = 'revenue';
  String _rankBy = 'revenue';
  bool _allProps = false;
  bool _allCats = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final q = {
      'period': _period,
      'count_by': _count,
      if (_period == 'custom' && _custom != null) 'from': ymd(_custom!.start),
      if (_period == 'custom' && _custom != null) 'to': ymd(_custom!.end),
      if (_city.isNotEmpty) 'city': _city,
      if (_property.isNotEmpty) 'property_id': _property,
      if (_year != null) 'year': '$_year',
    };
    try {
      final r = await widget.api.api.get('/api/dashboard?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}');
      if (mounted) setState(() => _d = (r as Map).cast());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addBooking() async {
    final b = await showCreateBookingDialog(context, api: widget.api);
    if (b == null || !mounted) return;
    showSnack(context, 'Booking ${b.code} created for ${b.guestName}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1150;
    final d = _d;
    if (d == null) {
      return Center(
        child: _error == null
            ? const CircularProgressIndicator()
            : ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("We couldn't load your figures.", style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text('$_error\nNothing is wrong with your data.', textAlign: TextAlign.center, style: AppFonts.sans(color: AppTheme.muted)),
                  TextButton(onPressed: _load, child: const Text('Try again')),
                ]),
              ),
      );
    }
    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _kpis(d, width),
      const SizedBox(height: 18),
      _twoUp(wide || width >= 900, _sources(d), _money(d)),
      const SizedBox(height: 18),
      _properties(d),
      const SizedBox(height: 18),
      _monthly(d),
      const SizedBox(height: 18),
      _outlook(d),
    ]);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12, vertical: 20),
        children: [
          _header(d),
          for (final a in (d['alerts'] as List).cast<Map>()) _alert(a),
          const SizedBox(height: 12),
          _quickActions(),
          const SizedBox(height: 14),
          _filters(d),
          if (_loading) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator(minHeight: 2)),
          const SizedBox(height: 16),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: main),
              const SizedBox(width: 18),
              SizedBox(width: 300, child: _today(d)),
            ])
          else ...[
            _today(d),
            const SizedBox(height: 18),
            main,
          ],
        ],
      ),
    );
  }

  Widget _header(Map<String, dynamic> d) {
    final h = DateTime.now().hour;
    final greet = h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : 'Good evening';
    final first = widget.hostName.trim().split(' ').first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$greet${first.isEmpty ? '' : ', $first'}', style: AppFonts.sans(fontSize: 26, fontWeight: FontWeight.w600)),
      Text('${widget.membership.orgName} · ${prettyDate(d['today'] as String, year: true)}', style: AppFonts.sans(color: AppTheme.muted)),
      const SizedBox(height: 10),
    ]);
  }

  Widget _alert(Map a) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: AppTheme.warningSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.info_outline, size: 18, color: AppTheme.warningInk),
          const SizedBox(width: 10),
          Expanded(child: Text(a['text'] as String, style: AppFonts.sans(color: AppTheme.warningInk, fontWeight: FontWeight.w500))),
          TextButton(onPressed: () => widget.onOpenSection('reservations'), child: const Text('Review')),
        ]),
      );

  Widget _quickActions() {
    final m = widget.membership;
    Widget tile(String title, String sub, IconData icon, VoidCallback? onTap, Key key) => SizedBox(
          width: 240,
          child: Card(
            child: InkWell(
              key: key,
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppTheme.radiusCard),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: AppTheme.sage, child: Icon(icon, size: 18, color: AppTheme.forest)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: AppFonts.sans(fontWeight: FontWeight.w600)),
                      Text(sub, style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Wrap(spacing: 10, runSpacing: 10, children: [
      if (m.can('bookings.write')) tile('Add direct booking', 'Offline or phone booking', Icons.add_box_outlined, _addBooking, const Key('qa-booking')),
      if (m.can('expenses.write')) tile('Add expenses', 'Record a new cost', Icons.receipt_long_outlined, widget.onAddExpense, const Key('qa-expense')),
      tile('Properties', 'Manage listings and rates', Icons.holiday_village_outlined, () => widget.onOpenSection('properties'), const Key('qa-properties')),
      if (m.can('expenses.read'))
        tile('Manage expenses', 'Full history and reports', Icons.account_balance_wallet_outlined, () => widget.onOpenSection('expenses'), const Key('qa-expenses')),
    ]);
  }

  Widget _filters(Map<String, dynamic> d) {
    final r = d['range'] as Map;
    final cmp = r['compare'] as Map;
    final f = d['filters'] as Map;
    final cities = (f['cities'] as List).cast<String>();
    final props = (f['properties'] as List).cast<Map>();
    Widget drop(String label, String value, Map<String, String> items, ValueChanged<String> on, {double w = 180}) => SizedBox(
          width: w,
          child: DropdownButtonFormField<String>(
            key: ValueKey('$label-$value'),
            initialValue: items.containsKey(value) ? value : items.keys.first,
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true),
            items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
            onChanged: (v) => v == null ? null : on(v),
          ),
        );
    return Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('Showing', style: AppFonts.sans(color: AppTheme.muted)),
      drop('Count bookings by', _count, _countBy, (v) {
        _count = v;
        _load();
      }),
      drop('Period', _period, _periods, (v) async {
        if (v == 'custom') {
          final now = DateTime.now();
          final picked = await showDateRangePicker(
              context: context, firstDate: DateTime(now.year - 3), lastDate: DateTime(now.year + 2), initialDateRange: _custom);
          if (picked == null) return setState(() {});
          _custom = picked;
        }
        _period = v;
        _load();
      }, w: 160),
      Text('${prettyDate(r['from'] as String)} – ${prettyDate(r['to'] as String, year: true)}',
          style: AppFonts.sans(fontWeight: FontWeight.w600)),
      Text('vs ${prettyDate(cmp['from'] as String)} – ${prettyDate(cmp['to'] as String)}', style: AppFonts.sans(color: AppTheme.muted, fontSize: 13)),
      drop('Location', _city, {'': 'All locations', for (final c in cities) c: c}, (v) {
        _city = v;
        _load();
      }, w: 160),
      drop('Property', _property, {'': 'All properties (${props.length})', for (final p in props) '${p['id']}': p['title'] as String}, (v) {
        _property = v;
        _load();
      }, w: 200),
      if (_city.isNotEmpty || _property.isNotEmpty || _period != 'last_30' || _count != 'check_in')
        TextButton(
          onPressed: () {
            _city = '';
            _property = '';
            _period = 'last_30';
            _count = 'check_in';
            _load();
          },
          child: const Text('Clear all'),
        ),
      OutlinedButton.icon(
          key: const Key('refresh-figures'), onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 18), label: const Text('Refresh figures')),
    ]);
  }

  Widget _card({required String title, required Widget child, Widget? trailing, String? help, Key? key}) => Container(
        key: key,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700))),
            if (trailing != null) trailing,
          ]),
          if (help != null) Text(help, style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
          const SizedBox(height: 10),
          child,
        ]),
      );

  Widget _change(num? v, {bool pts = false, bool inverse = false}) {
    if (v == null) return Text('new', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted));
    final up = v > 0;
    final good = inverse ? !up : up;
    final color = v == 0 ? AppTheme.muted : good ? AppTheme.success : AppTheme.danger;
    return Text('${up ? '↑' : v < 0 ? '↓' : ''}${v.abs()}${pts ? ' pts' : '%'}',
        style: AppFonts.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: color));
  }

  Widget _kpis(Map<String, dynamic> d, double width) {
    final k = (d['kpis'] as Map).cast<String, Map>();
    Widget kpi(String title, String value, String sub, Widget change, String help, Key key) => Container(
          key: key,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: AppFonts.sans(fontSize: 13.5, color: AppTheme.muted))),
              Tooltip(message: help, child: const Icon(Icons.info_outline, size: 15, color: AppTheme.hint)),
            ]),
            const SizedBox(height: 4),
            Text(value, style: AppFonts.sans(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Row(children: [change, const SizedBox(width: 6), Expanded(child: Text(sub, overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)))]),
          ]),
        );
    final rev = k['revenue']!;
    final exp = k['expenses']!;
    final noi = k['noi']!;
    final occ = k['occupancy']!;
    final cards = [
      kpi('Net revenue', money(rev['value'] as num), 'Stay ${_compact(rev['stay'] as num)} · Extras ${_compact(rev['extras'] as num)}', _change(rev['change'] as num?),
          'Sum of the payout recorded against every booking in the period', const Key('kpi-revenue')),
      kpi('Expenses', money(exp['value'] as num), exp['pct_of_revenue'] == null ? 'No revenue yet' : '${exp['pct_of_revenue']}% of revenue',
          _change(exp['change'] as num?, inverse: true), 'Everything recorded as a cost against these properties, across all categories', const Key('kpi-expenses')),
      kpi('Net operating income', money(noi['value'] as num), noi['margin'] == null ? '—' : '${noi['margin']}% margin', _change(noi['change'] as num?),
          'Net revenue − expenses', const Key('kpi-noi')),
      kpi('Occupancy', '${occ['value']}%', '${occ['booked_nights']} of ${occ['available_nights']} nights', _change(occ['change_pts'] as num?, pts: true),
          'Share of available time actually booked. A deliberately blocked night still counts as available time', const Key('kpi-occupancy')),
      kpi('Net ADR', money(k['adr']!['value'] as num), 'per booked night', _change(k['adr']!['change'] as num?), 'Net revenue per booked night',
          const Key('kpi-adr')),
      kpi('Net RevPAR', money(k['revpar']!['value'] as num), 'per available night', _change(k['revpar']!['change'] as num?),
          'Net revenue per available night, booked or not', const Key('kpi-revpar')),
    ];
    final cols = width >= 1400 ? 3 : width >= 700 ? 3 : 2;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - (cols - 1) * 12) / cols;
      return Wrap(spacing: 12, runSpacing: 12, children: [for (final card in cards) SizedBox(width: w, child: card)]);
    });
  }

  Widget _today(Map<String, dynamic> d) {
    final t = (d['today_panel'] as Map).cast<String, Map>();
    const rows = {
      'check_ins': "Today's check-ins",
      'check_outs': "Today's check-outs",
      'ongoing': 'Ongoing stays',
      'arriving_soon': 'Arriving in next 2 days',
    };
    return _card(
      key: const Key('today-panel'),
      title: 'Today',
      trailing: Text(prettyDate(d['today'] as String), style: AppFonts.sans(color: AppTheme.muted)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final e in rows.entries) ...[
          Row(children: [
            Expanded(child: Text(e.value, style: AppFonts.sans(fontWeight: FontWeight.w600))),
            Text('${t[e.key]!['count']}', style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700)),
          ]),
          if ((t[e.key]!['items'] as List).isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('No bookings here right now.', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
            )
          else
            for (final b in (t[e.key]!['items'] as List).cast<Map>())
              InkWell(
                onTap: () async {
                  final changed =
                      await showBookingDetail(context, api: widget.api, bookingId: (b['id'] as num).toInt(), membership: widget.membership);
                  if (changed == true) _load();
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Expanded(
                      child: Text('${b['guest_name']} · ${b['source_label']}',
                          overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontSize: 13.5)),
                    ),
                    if (b['status'] == 'cancelled') const StatusPill('cancelled'),
                  ]),
                ),
              ),
          const Divider(height: 18),
        ],
        TextButton(onPressed: () => widget.onOpenSection('reservations'), child: const Text('View all bookings')),
      ]),
    );
  }

  Widget _twoUp(bool side, Widget a, Widget b) =>
      side ? IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Expanded(child: a), const SizedBox(width: 18), Expanded(child: b)])) : Column(children: [a, const SizedBox(height: 18), b]);

  static const _palette = [AppTheme.forest, AppTheme.clay, AppTheme.moss, Color(0xFF2F5C8A), Color(0xFFB59A57), Color(0xFF7D6B91), AppTheme.hint];

  Widget _shareBar(List<double> shares) => ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 12,
          child: Row(children: [
            for (final (i, s) in shares.indexed)
              if (s > 0) Expanded(flex: (s * 10).round().clamp(1, 1000), child: Container(color: _palette[i % _palette.length])),
            if (shares.every((s) => s <= 0)) Expanded(child: Container(color: AppTheme.sage)),
          ]),
        ),
      );

  Widget _sources(Map<String, dynamic> d) {
    final s = (d['sources'] as List).cast<Map>();
    final byRev = _sourcesBy == 'revenue';
    TextStyle h = AppFonts.sans(fontSize: 12.5, color: AppTheme.muted, fontWeight: FontWeight.w600);
    return _card(
      key: const Key('sources'),
      title: 'Where bookings come from',
      help: 'Blocked nights are left out: a block is not a booking source.',
      trailing: SegmentedButton<String>(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [ButtonSegment(value: 'revenue', label: Text('Revenue')), ButtonSegment(value: 'bookings', label: Text('Bookings'))],
        selected: {_sourcesBy},
        onSelectionChanged: (v) => setState(() => _sourcesBy = v.first),
      ),
      child: s.isEmpty
          ? Text('No bookings in this range.', style: AppFonts.sans(color: AppTheme.muted))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _shareBar([for (final x in s) ((byRev ? x['share_revenue'] : x['share_nights']) as num).toDouble()]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(flex: 4, child: Text('Source', style: h)),
                Expanded(flex: 3, child: Text('Bookings', style: h, textAlign: TextAlign.right, maxLines: 1, softWrap: false, overflow: TextOverflow.visible)),
                Expanded(flex: 2, child: Text('Nights', style: h, textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('Share', style: h, textAlign: TextAlign.right)),
                Expanded(flex: 3, child: Text('Net ADR', style: h, textAlign: TextAlign.right)),
                Expanded(flex: 3, child: Text('Revenue', style: h, textAlign: TextAlign.right)),
              ]),
              for (final (i, x) in s.indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        flex: 4,
                        child: Row(children: [
                          Container(width: 10, height: 10, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Flexible(child: Text(x['label'] as String, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                      Expanded(flex: 3, child: Text('${x['bookings']}', textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text('${x['nights']}', textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text('${byRev ? x['share_revenue'] : x['share_nights']}%', textAlign: TextAlign.right)),
                      Expanded(flex: 3, child: Text(_compact(x['adr'] as num), textAlign: TextAlign.right)),
                      Expanded(flex: 3, child: Text(_compact(x['revenue'] as num), textAlign: TextAlign.right)),
                    ]),
                    if ((x['saved_commission'] as num) > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Text('${money(x['saved_commission'] as num)} saved in commission',
                            style: AppFonts.sans(fontSize: 12, color: AppTheme.success)),
                      ),
                  ]),
                ),
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => widget.onOpenSection('reservations'), child: const Text('View bookings'))),
            ]),
    );
  }

  Widget _money(Map<String, dynamic> d) {
    final m = (d['money'] as List).cast<Map>();
    final shown = _allCats || m.length <= 6 ? m : m.take(5).toList();
    final rest = _allCats || m.length <= 6 ? const <Map>[] : m.skip(5).toList();
    final restAmount = rest.fold<num>(0, (s, x) => s + (x['amount'] as num));
    final restShare = rest.fold<num>(0, (s, x) => s + (x['share'] as num));
    Widget row(int i, String name, num share, num amount) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: _palette[i % _palette.length], shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Expanded(flex: 5, child: Text(name, overflow: TextOverflow.ellipsis)),
            Expanded(flex: 2, child: Text('${share.toStringAsFixed(share % 1 == 0 ? 0 : 1)}%', textAlign: TextAlign.right)),
            Expanded(flex: 3, child: Text(money(amount), textAlign: TextAlign.right)),
          ]),
        );
    return _card(
      key: const Key('money'),
      title: 'Where money goes',
      help: 'By expense date',
      child: m.isEmpty
          ? Text('No expenses recorded in this range.', style: AppFonts.sans(color: AppTheme.muted))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _shareBar([for (final x in shown) (x['share'] as num).toDouble(), if (rest.isNotEmpty) restShare.toDouble()]),
              const SizedBox(height: 10),
              for (final (i, x) in shown.indexed) row(i, x['category'] as String, x['share'] as num, x['amount'] as num),
              if (rest.isNotEmpty) row(shown.length, 'Other ${rest.length} categories', restShare, restAmount),
              if (m.length > 6)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () => setState(() => _allCats = !_allCats), child: Text(_allCats ? 'Show less' : 'View all categories')),
                ),
            ]),
    );
  }

  Widget _properties(Map<String, dynamic> d) {
    final list = [...(d['properties'] as List).cast<Map>()];
    final byRev = _rankBy == 'revenue';
    list.sort((a, b) => ((byRev ? b['revenue'] : b['expenses']) as num).compareTo((byRev ? a['revenue'] : a['expenses']) as num));
    final shown = _allProps ? list : list.take(5).toList();
    TextStyle h = AppFonts.sans(fontSize: 12.5, color: AppTheme.muted, fontWeight: FontWeight.w600);
    return _card(
      key: const Key('properties-rank'),
      title: 'Properties',
      trailing: SegmentedButton<String>(
        style: const ButtonStyle(visualDensity: VisualDensity.compact),
        segments: const [ButtonSegment(value: 'revenue', label: Text('Revenue')), ButtonSegment(value: 'expenses', label: Text('Expenses'))],
        selected: {_rankBy},
        onSelectionChanged: (v) => setState(() => _rankBy = v.first),
      ),
      child: list.isEmpty
          ? Text('Add rooms to a property to see it ranked here.', style: AppFonts.sans(color: AppTheme.muted))
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(flex: 5, child: Text('Property', style: h)),
                Expanded(flex: 3, child: Text(byRev ? 'Revenue' : 'Expenses', style: h, textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text(byRev ? '% full' : '% of revenue', style: h, textAlign: TextAlign.right)),
                Expanded(flex: 3, child: Text(byRev ? 'Net ADR' : 'Revenue', style: h, textAlign: TextAlign.right)),
              ]),
              for (final p in shown)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Expanded(
                      flex: 5,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p['title'] as String, overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontWeight: FontWeight.w600)),
                        if ((p['city'] as String).isNotEmpty) Text(p['city'] as String, style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
                      ]),
                    ),
                    Expanded(flex: 3, child: Text(money((byRev ? p['revenue'] : p['expenses']) as num), textAlign: TextAlign.right)),
                    Expanded(
                        flex: 2,
                        child: Text(byRev ? '${p['occupancy']}%' : p['expense_pct'] == null ? '—' : '${p['expense_pct']}%', textAlign: TextAlign.right)),
                    Expanded(flex: 3, child: Text(money((byRev ? p['adr'] : p['revenue']) as num), textAlign: TextAlign.right)),
                  ]),
                ),
              if (list.length > 5)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(onPressed: () => setState(() => _allProps = !_allProps), child: Text(_allProps ? 'Show less' : 'See all ${list.length}')),
                ),
            ]),
    );
  }

  Widget _monthly(Map<String, dynamic> d) {
    final m = d['monthly'] as Map;
    final months = (m['months'] as List).cast<Map>();
    final years = (m['years'] as List).map((e) => (e as num).toInt()).toList();
    final maxV = months.fold<num>(1, (s, x) => [s, x['revenue'] as num, x['expenses'] as num].reduce((a, b) => a > b ? a : b));
    const chartH = 160.0;
    return _card(
      key: const Key('monthly'),
      title: 'Revenue and expenses',
      help: 'Hover any month to read exact figures',
      trailing: Wrap(spacing: 4, children: [
        for (final y in years.take(3))
          ChoiceChip(
            label: Text('$y'),
            selected: (m['year'] as num).toInt() == y,
            onSelected: (_) {
              _year = y;
              _load();
            },
          ),
      ]),
      child: Column(children: [
        SizedBox(
          height: chartH + 22,
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (final (i, x) in months.indexed)
              Expanded(
                child: Tooltip(
                  message: '${_months[i]} ${m['year']}\nRevenue ${money(x['revenue'] as num)}\nExpenses ${money(x['expenses'] as num)}\n'
                      'Net operating income ${money(x['noi'] as num)}${x['margin'] == null ? '' : ' (${x['margin']}%)'}',
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Container(width: 10, height: chartH * ((x['revenue'] as num) / maxV) + 1, color: AppTheme.forest),
                      const SizedBox(width: 2),
                      Container(width: 10, height: chartH * ((x['expenses'] as num) / maxV) + 1, color: AppTheme.clay),
                    ]),
                    const SizedBox(height: 4),
                    Text(_months[i], style: AppFonts.sans(fontSize: 11.5, color: AppTheme.muted)),
                  ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          _legendDot(AppTheme.forest, 'Revenue'),
          const SizedBox(width: 16),
          _legendDot(AppTheme.clay, 'Expenses'),
        ]),
      ]),
    );
  }

  Widget _legendDot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text(t, style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
      ]);

  Widget _outlook(Map<String, dynamic> d) {
    final weeks = (d['outlook'] as List).cast<Map>();
    Color bandColor(String b) => switch (b) {
          'high' => AppTheme.forest,
          'mid' => AppTheme.moss,
          'low' => AppTheme.sage,
          _ => const Color(0xFFE9E6E1),
        };
    return _card(
      key: const Key('outlook'),
      title: 'Occupancy outlook',
      help: 'Next 13 weeks. Hover any week to read exact dates and nights.',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          for (final w in weeks)
            Expanded(
              child: Tooltip(
                message: '${prettyDate(w['from'] as String)} – ${prettyDate(w['to'] as String)}\n'
                    '${w['band'] == 'not_offered' ? 'Not offered' : 'Booked ${w['pct']}% · ${w['booked_nights']} / ${w['offered_nights']} nights'}',
                child: Container(
                  height: 44,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: bandColor(w['band'] as String), borderRadius: BorderRadius.circular(6)),
                  child: Text(w['band'] == 'not_offered' ? '–' : '${(w['pct'] as num).round()}%',
                      style: AppFonts.sans(
                          fontSize: 11.5, fontWeight: FontWeight.w600, color: w['band'] == 'high' || w['band'] == 'mid' ? Colors.white : AppTheme.inkSoft)),
                ),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _legendDot(AppTheme.forest, '50% and above'),
          _legendDot(AppTheme.moss, '25–49%'),
          _legendDot(AppTheme.sage, 'Under 25%'),
          _legendDot(const Color(0xFFE9E6E1), 'Not offered'),
        ]),
      ]),
    );
  }
}
