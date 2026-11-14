import 'package:flutter/material.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/download.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart';
import '../bookings/bookings_api.dart';

const _tabs = {
  'all': 'All',
  'upcoming': 'Upcoming',
  'arriving_soon': 'Arriving soon',
  'checking_in': 'Checking in today',
  'checking_out': 'Checking out today',
  'in_house': 'In house',
  'pending_payment': 'Payment pending',
  'completed': 'Completed',
  'cancelled': 'Cancelled',
  'offline': 'Offline',
};

const _paymentFilters = {'all': 'Any payment', 'pending': 'Pending', 'partial': 'Part paid', 'paid': 'Paid'};

const _tripLabels = {'upcoming': 'Upcoming', 'ongoing': 'Ongoing', 'completed': 'Completed', 'cancelled': 'Cancelled'};

/// Host Control Center → Reservations: every booking (direct, manual, OTA)
/// with tabs, search, filters, CSV export and the booking detail actions.
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key, required this.api, required this.membership});

  final BookingsApi api;
  final Membership membership;

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  final _search = TextEditingController();
  String _tab = 'all';
  String _source = 'all';
  String _payment = 'all';
  String _sort = 'check_in';
  DateTimeRange? _checkIn;
  int _page = 1;
  BookingPage? _data;
  String? _error;
  bool _loading = false;

  bool get _canBook => widget.membership.can('bookings.write');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Map<String, String> get _query => {
        'tab': _tab,
        'q': _search.text.trim(),
        'source': _source == 'all' ? '' : _source,
        'payment': _payment == 'all' ? '' : _payment,
        'sort': _sort,
        'check_in_from': _checkIn == null ? '' : ymd(_checkIn!.start),
        'check_in_to': _checkIn == null ? '' : ymd(_checkIn!.end),
      };

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final d = await widget.api.list({..._query, 'page': '$page', 'page_size': '25'});
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _export() async {
    try {
      final csv = await widget.api.exportCsv(_query);
      final ok = downloadText('bleiben-reservations-${ymd(DateTime.now())}.csv', csv);
      if (mounted) showSnack(context, ok ? 'Export downloaded' : 'Export is available in the web app');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _create() async {
    final b = await showCreateBookingDialog(context, api: widget.api);
    if (b == null || !mounted) return;
    showSnack(context, 'Booking ${b.code} created for ${b.guestName}');
    _load();
  }

  Future<void> _open(Booking b) async {
    final changed = await showBookingDetail(context, api: widget.api, bookingId: b.id, membership: widget.membership);
    if (changed == true) _load(page: _page);
  }

  bool get _filtered => _source != 'all' || _payment != 'all' || _checkIn != null || _search.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final d = _data;
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12, vertical: 20),
      children: [
        Row(children: [
          Expanded(child: Text('Reservations', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600))),
          IconButton(tooltip: 'Export CSV', onPressed: _export, icon: const Icon(Icons.download_outlined)),
          if (_canBook)
            SizedBox(
              width: 210,
              child: ElevatedButton.icon(
                key: const Key('reservations-create'),
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Create booking'),
              ),
            ),
        ]),
        const SizedBox(height: 14),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final e in _tabs.entries)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('tab-${e.key}'),
                  label: Text('${e.value}${d == null ? '' : ' (${d.counts[e.key] ?? 0})'}'),
                  selected: _tab == e.key,
                  onSelected: (_) {
                    _tab = e.key;
                    _load();
                  },
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: wide ? 320 : double.infinity,
            child: TextField(
              key: const Key('reservation-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(hintText: 'Search guest, phone, email or booking ID', prefixIcon: Icon(Icons.search), isDense: true),
            ),
          ),
          _dropdown('Booked via', _source, {'all': 'All channels', ...bookingSources}, (v) => _source = v),
          _dropdown('Payment', _payment, _paymentFilters, (v) => _payment = v),
          _dropdown('Sort', _sort, const {'check_in': 'Check-in date', 'booked': 'Newest booked'}, (v) => _sort = v),
          OutlinedButton.icon(
            onPressed: () async {
              final now = DateTime.now();
              final r = await showDateRangePicker(
                context: context,
                firstDate: DateTime(now.year - 2),
                lastDate: DateTime(now.year + 2),
                initialDateRange: _checkIn,
                helpText: 'Check-in between',
              );
              if (r == null) return;
              _checkIn = r;
              _load();
            },
            icon: const Icon(Icons.date_range_outlined, size: 18),
            label: Text(_checkIn == null ? 'Check-in dates' : '${prettyDate(ymd(_checkIn!.start))} – ${prettyDate(ymd(_checkIn!.end))}'),
          ),
          if (_filtered)
            TextButton(
              onPressed: () {
                _search.clear();
                _source = 'all';
                _payment = 'all';
                _checkIn = null;
                _load();
              },
              child: const Text('Clear filters'),
            ),
        ]),
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: AppFonts.sans(color: AppTheme.danger)))
        else if (d != null && d.items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Center(
              child: Text(_filtered || _tab != 'all' ? 'No bookings match these filters.' : 'No bookings yet. Create one, or open the calendar to book dates.',
                  style: AppFonts.sans(color: AppTheme.muted)),
            ),
          )
        else if (d != null) ...[
          if (wide) _table(d.items) else for (final b in d.items) _card(b),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Text('${(d.page - 1) * d.pageSize + 1}–${(d.page - 1) * d.pageSize + d.items.length} of ${d.total}',
                style: AppFonts.sans(color: AppTheme.muted)),
            IconButton(tooltip: 'Previous page', onPressed: d.page > 1 ? () => _load(page: d.page - 1) : null, icon: const Icon(Icons.chevron_left)),
            IconButton(
                tooltip: 'Next page',
                onPressed: d.page * d.pageSize < d.total ? () => _load(page: d.page + 1) : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
        ],
      ],
    );
  }

  Widget _dropdown(String label, String value, Map<String, String> items, void Function(String) set) => SizedBox(
        width: 180,
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v == null) return;
            set(v);
            _load();
          },
        ),
      );

  static String _payLabel(String s) => switch (s) { 'paid' => 'Paid', 'partial' => 'Part paid', _ => 'Pending' };

  Widget _table(List<Booking> items) {
    TextStyle head = AppFonts.sans(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.muted);
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          showCheckboxColumn: false,
          columnSpacing: 22,
          horizontalMargin: 16,
          headingTextStyle: head,
          columns: const [
            DataColumn(label: Text('Booking ID')),
            DataColumn(label: Text('Trip')),
            DataColumn(label: Text('Check-in')),
            DataColumn(label: Text('Property / room')),
            DataColumn(label: Text('Guest')),
            DataColumn(label: Text('Booked via')),
            DataColumn(label: Text('Payment')),
            DataColumn(label: Text('Amount'), numeric: true),
            DataColumn(label: Text('Guests'), numeric: true),
            DataColumn(label: Text('Status')),
          ],
          rows: [
            for (final b in items)
              DataRow(
                key: ValueKey(b.id),
                onSelectChanged: (_) => _open(b),
                cells: [
                  DataCell(Text(b.code, style: AppFonts.sans(fontWeight: FontWeight.w600))),
                  DataCell(Text(_tripLabels[b.tripStatus] ?? b.tripStatus)),
                  DataCell(Text('${prettyDate(b.checkIn, year: true)}\n${b.nights} night(s)')),
                  DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text('${b.propertyTitle}\n${b.roomName}', overflow: TextOverflow.ellipsis, maxLines: 2))),
                  DataCell(Text('${b.guestName}${b.guestPhone.isEmpty ? '' : '\n${b.guestPhone}'}')),
                  DataCell(Text(b.sourceLabel.isEmpty ? (bookingSources[b.source] ?? b.source) : b.sourceLabel)),
                  DataCell(StatusPill(b.paymentStatus, label: _payLabel(b.paymentStatus))),
                  DataCell(Text('${money(b.total)}${b.balance > 0 ? '\nDue ${money(b.balance)}' : ''}', textAlign: TextAlign.right)),
                  DataCell(Text('${b.guests}')),
                  DataCell(StatusPill(b.status)),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _card(Booking b) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          onTap: () => _open(b),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(b.guestName, style: AppFonts.sans(fontWeight: FontWeight.w700, fontSize: 16))),
                StatusPill(b.status),
              ]),
              const SizedBox(height: 4),
              Text('${b.code} · ${b.propertyTitle} · ${b.roomName}', style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
              Text('${prettyDate(b.checkIn)} → ${prettyDate(b.checkOut)} · ${b.guests} guest(s) · ${bookingSources[b.source] ?? b.source}',
                  style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
              const SizedBox(height: 6),
              Row(children: [
                Text(money(b.total), style: AppFonts.sans(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                StatusPill(b.paymentStatus, label: _payLabel(b.paymentStatus)),
                if (b.balance > 0) ...[
                  const SizedBox(width: 8),
                  Text('Due ${money(b.balance)}', style: AppFonts.sans(fontSize: 13, color: AppTheme.warningInk)),
                ],
              ]),
            ]),
          ),
        ),
      );
}
