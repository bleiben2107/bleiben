import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../home/home_widgets.dart';
import 'properties_controller.dart';

const _statusFilters = {
  'all': 'All',
  'draft': 'Draft',
  'activated': 'Published',
  'deactivated': 'Unpublished',
};

String _money(double v) => '₹${v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2)}';

void _snack(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));

/// Host Control Center → Properties → All Properties (MVP plan §3).
class PropertiesScreen extends StatefulWidget {
  const PropertiesScreen({
    super.key,
    required this.controller,
    required this.membership,
    required this.onCreate,
    required this.onEditListing,
  });

  final PropertiesController controller;
  final Membership membership;
  final VoidCallback onCreate;

  /// Reopens the listing wizard on a property (raw API payload).
  final Future<void> Function(Map<String, dynamic> raw) onEditListing;

  @override
  State<PropertiesScreen> createState() => _PropertiesScreenState();
}

class _PropertiesScreenState extends State<PropertiesScreen> {
  final _search = TextEditingController();

  PropertiesController get c => widget.controller;
  bool get _canWrite => widget.membership.can('properties.write');

  @override
  void initState() {
    super.initState();
    c.load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _open(PropertySummary p) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PropertyDetailScreen(
        controller: c,
        propertyId: p.id,
        membership: widget.membership,
        onEditListing: widget.onEditListing,
      ),
    ));
    c.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 760;
        return ListView(
          padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 14, vertical: 22),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: wide ? 340 : double.infinity,
                  child: TextField(
                    key: const Key('property-search'),
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onSubmitted: c.setQuery,
                    decoration: InputDecoration(
                      hintText: 'Search by property name, ID, city',
                      prefixIcon: const Icon(Icons.search_rounded),
                      fillColor: HomeColors.mist,
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _search.clear();
                                c.setQuery('');
                              }),
                    ),
                  ),
                ),
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String>(
                    key: const Key('status-filter'),
                    initialValue: c.status,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Status', fillColor: HomeColors.mist),
                    items: [
                      for (final e in _statusFilters.entries) DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (v) => c.setStatus(v ?? 'all'),
                  ),
                ),
                if (_canWrite)
                  ElevatedButton.icon(
                    onPressed: widget.onCreate,
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 50), padding: const EdgeInsets.symmetric(horizontal: 20)),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Create new listing'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            if (c.loading && c.items.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (c.error != null)
              _Empty(icon: Icons.cloud_off_rounded, text: c.error!, action: TextButton(onPressed: c.load, child: const Text('Try again')))
            else if (c.items.isEmpty)
              _Empty(
                icon: Icons.holiday_village_outlined,
                text: c.query.isEmpty && c.status == 'all'
                    ? 'No properties yet. Create your first listing to start taking bookings.'
                    : 'No properties match these filters.',
              )
            else
              for (final p in c.items) _PropertyRow(property: p, onTap: () => _open(p)),
          ],
        );
      },
    );
  }
}

class _PropertyRow extends StatelessWidget {
  const _PropertyRow({required this.property, required this.onTap});

  final PropertySummary property;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = property;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: HomeColors.line)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(color: HomeColors.mist, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.home_work_outlined, color: AppTheme.forest),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p.displayTitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  [
                    p.serialId,
                    if (p.city.isNotEmpty) p.city,
                    '${p.roomCount} room type${p.roomCount == 1 ? '' : 's'} · ${p.unitCount} unit${p.unitCount == 1 ? '' : 's'}',
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.sans(fontSize: 13, color: HomeColors.muted),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            StatusPill(status: p.status),
            const Icon(Icons.chevron_right_rounded, color: HomeColors.muted),
          ]),
        ),
      ),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'activated' => (AppTheme.successSoft, AppTheme.forest),
      'deactivated' => (AppTheme.sage, AppTheme.muted),
      _ => (AppTheme.warningSoft, AppTheme.warningInk),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppTheme.radiusButton)),
      child: Text(PropertySummary.statusLabel(status),
          style: AppFonts.sans(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(children: [
        Icon(icon, size: 40, color: HomeColors.muted),
        const SizedBox(height: 10),
        Text(text, textAlign: TextAlign.center, style: AppFonts.sans(color: HomeColors.muted, fontSize: 15)),
        if (action != null) action!,
      ]),
    );
  }
}

// ── Property details ─────────────────────────────────────────────────────────

/// Property detail with tabs Overview · Rooms & units · Activity (homyhuts:
/// Property Info · Calendar & Pricing · Update Listing · Activity · Co-Hosts).
class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({
    super.key,
    required this.controller,
    required this.propertyId,
    required this.membership,
    required this.onEditListing,
  });

  final PropertiesController controller;
  final int propertyId;
  final Membership membership;
  final Future<void> Function(Map<String, dynamic> raw) onEditListing;

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  PropertySummary? _p;
  String? _error;
  bool _busy = false;

  PropertiesController get c => widget.controller;
  bool get _canWrite => widget.membership.can('properties.write');
  bool get _canPublish => widget.membership.can('properties.publish');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final p = await c.fetch(widget.propertyId);
      if (mounted) setState(() => (_p = p, _error = null));
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load this property.');
    }
  }

  Future<void> _togglePublish() async {
    final p = _p!;
    setState(() => _busy = true);
    final error = p.isLive ? await c.unpublish(p.id) : await c.publish(p.id);
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(context, error ?? (p.isLive ? 'Booking page taken offline' : 'Published. Your booking page is live.'));
    _reload();
  }

  Future<void> _editListing() async {
    await widget.onEditListing(_p!.raw);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppTheme.paper,
        appBar: AppBar(
          backgroundColor: AppTheme.paper,
          title: Text(p?.displayTitle ?? 'Property', overflow: TextOverflow.ellipsis),
          actions: [
            if (p != null && _canWrite)
              TextButton.icon(
                onPressed: _editListing,
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(p.isLive ? 'Edit listing' : 'Continue setup'),
              ),
            if (p != null && _canPublish)
              Padding(
                padding: const EdgeInsets.only(right: 12, left: 4),
                child: ElevatedButton(
                  onPressed: _busy ? null : _togglePublish,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 42),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    backgroundColor: p.isLive ? HomeColors.muted : AppTheme.forest,
                  ),
                  child: Text(p.isLive ? 'Unpublish' : 'Publish'),
                ),
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [Tab(text: 'Overview'), Tab(text: 'Rooms & units'), Tab(text: 'Activity')],
          ),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : p == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _Overview(property: p),
                    _RoomsTab(controller: c, property: p, canWrite: _canWrite, onChanged: _reload),
                    _ActivityTab(controller: c, propertyId: p.id),
                  ]),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.property});

  final PropertySummary property;

  @override
  Widget build(BuildContext context) {
    final p = property;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 160, child: Text(label, style: AppFonts.sans(color: HomeColors.muted))),
            Expanded(child: Text(value.isEmpty ? '—' : value, style: AppFonts.sans(fontSize: 15))),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(children: [StatusPill(status: p.status), const SizedBox(width: 10), Text(p.serialId, style: AppFonts.sans(color: HomeColors.muted))]),
        const SizedBox(height: 14),
        if (p.isLive && p.bookingUrl != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppTheme.successSoft, borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.public_rounded, color: AppTheme.forest),
              const SizedBox(width: 10),
              Expanded(child: SelectableText(p.bookingUrl!, style: AppFonts.sans(fontWeight: FontWeight.w600))),
              IconButton(
                tooltip: 'Copy booking link',
                icon: const Icon(Icons.copy_rounded),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: p.bookingUrl!));
                  _snack(context, 'Booking link copied');
                },
              ),
            ]),
          )
        else if (!p.isLive)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(color: AppTheme.warningSoft, borderRadius: BorderRadius.circular(12)),
            child: Text(
              'Not live yet. Finish the listing, add your rooms and units, then publish to get a booking link.',
              style: AppFonts.sans(color: AppTheme.warningInk),
            ),
          ),
        row('Property type', p.propertyType),
        row('Location', p.location),
        row('Guests', p.guests == 0 ? '' : '${p.guests}'),
        row('Base price / night', p.basePrice > 0 ? _money(p.basePrice) : ''),
        row('Extra guest charge', p.extraGuestCharge > 0 ? _money(p.extraGuestCharge) : ''),
        row('Advance at booking', p.advancePercent > 0 ? '${p.advancePercent.toStringAsFixed(0)}%' : ''),
        row('Rooms & units', '${p.roomCount} room type${p.roomCount == 1 ? '' : 's'}, ${p.unitCount} unit${p.unitCount == 1 ? '' : 's'}'),
      ],
    );
  }
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab({required this.controller, required this.property, required this.canWrite, required this.onChanged});

  final PropertiesController controller;
  final PropertySummary property;
  final bool canWrite;
  final Future<void> Function() onChanged;

  Future<void> _edit(BuildContext context, {Room? room}) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => RoomDialog(room: room, propertyPrice: property.basePrice),
    );
    if (body == null || !context.mounted) return;
    final error = await controller.saveRoom(property.id, body, roomId: room?.id);
    if (!context.mounted) return;
    _snack(context, error ?? (room == null ? 'Room added' : 'Room updated'));
    await onChanged();
  }

  Future<void> _archive(BuildContext context, Room room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${room.name}?'),
        content: const Text('It stops being bookable. Past bookings keep their details.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(110, 44)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final error = await controller.archiveRoom(property.id, room.id);
    if (!context.mounted) return;
    _snack(context, error ?? 'Room archived');
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final rooms = property.rooms;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              'Each room type is sold as its own inventory. Units = how many identical rooms you have.',
              style: AppFonts.sans(color: HomeColors.muted),
            ),
          ),
          if (canWrite)
            ElevatedButton.icon(
              onPressed: () => _edit(context),
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 16)),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add room'),
            ),
        ]),
        const SizedBox(height: 16),
        if (rooms.isEmpty)
          const _Empty(
            icon: Icons.bed_outlined,
            text: 'No rooms yet. Add each room type, or publish an entire-place listing and it becomes one unit.',
          ),
        for (final r in rooms)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: HomeColors.line)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: const Icon(Icons.bed_outlined, color: AppTheme.forest),
              title: Text(r.name, style: AppFonts.sans(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${r.typeLabel} · ${r.unitCount} unit${r.unitCount == 1 ? '' : 's'} · up to ${r.maxGuests} guests · ${_money(r.effectivePrice)}/night${r.basePrice == null ? ' (property price)' : ''}',
              ),
              trailing: canWrite
                  ? PopupMenuButton<String>(
                      tooltip: 'Manage ${r.name}',
                      onSelected: (v) => v == 'edit' ? _edit(context, room: r) : _archive(context, r),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(value: 'archive', child: Text('Archive')),
                      ],
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

/// Add / edit a room type: name, type, capacity, units, price.
class RoomDialog extends StatefulWidget {
  const RoomDialog({super.key, this.room, required this.propertyPrice});

  final Room? room;
  final double propertyPrice;

  @override
  State<RoomDialog> createState() => _RoomDialogState();
}

class _RoomDialogState extends State<RoomDialog> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.room?.name ?? '');
  late final _adults = TextEditingController(text: '${widget.room?.maxAdults ?? 2}');
  late final _children = TextEditingController(text: '${widget.room?.maxChildren ?? 0}');
  late final _units = TextEditingController(text: '${widget.room?.unitCount ?? 1}');
  late final _price = TextEditingController(text: widget.room?.basePrice?.toStringAsFixed(0) ?? '');
  late final _extra = TextEditingController(text: widget.room?.extraGuestCharge?.toStringAsFixed(0) ?? '');
  late String _type = widget.room?.type ?? 'room';

  @override
  void dispose() {
    for (final c in [_name, _adults, _children, _units, _price, _extra]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _int(String? v, {int min = 0, int max = 500}) {
    final n = int.tryParse((v ?? '').trim());
    return n == null || n < min || n > max ? 'Enter $min–$max' : null;
  }

  String? _optMoney(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return null;
    final n = double.tryParse(t);
    return n == null || n < 0 ? 'Enter an amount' : null;
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.digitsOnly];
    Widget field(String key, TextEditingController c, String label, String? Function(String?) v, {String? helper}) =>
        TextFormField(
          key: Key('room-$key'),
          controller: c,
          validator: v,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          decoration: InputDecoration(labelText: label, helperText: helper, fillColor: HomeColors.mist),
        );
    return AlertDialog(
      title: Text(widget.room == null ? 'Add room' : 'Edit ${widget.room!.name}'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                key: const Key('room-name'),
                controller: _name,
                autofocus: true,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Room name *', hintText: 'e.g. Deluxe Room', fillColor: HomeColors.mist),
                validator: (v) => (v ?? '').trim().isEmpty ? 'Room name is required' : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: _type,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Room type', fillColor: HomeColors.mist),
                items: [for (final e in roomTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => setState(() => _type = v ?? 'room'),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: field('adults', _adults, 'Adults *', (v) => _int(v, min: 1, max: 50))),
                const SizedBox(width: 12),
                Expanded(child: field('children', _children, 'Children', (v) => _int(v, max: 50))),
              ]),
              const SizedBox(height: 12),
              field('units', _units, 'Number of units *', (v) => _int(v, min: 1),
                  helper: 'How many identical rooms of this type'),
              const SizedBox(height: 12),
              field('price', _price, 'Price per night (₹)', _optMoney,
                  helper: widget.propertyPrice > 0
                      ? 'Leave empty to use the property price (${_money(widget.propertyPrice)})'
                      : 'Leave empty to use the property price'),
              const SizedBox(height: 12),
              field('extra', _extra, 'Extra guest charge (₹)', _optMoney, helper: 'Per guest per night, optional'),
            ]),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(110, 44)),
          onPressed: () {
            if (!_form.currentState!.validate()) return;
            Navigator.pop(context, {
              'name': _name.text.trim(),
              'room_type': _type,
              'max_adults': int.parse(_adults.text),
              'max_children': int.parse(_children.text),
              'unit_count': int.parse(_units.text),
              'base_price': _price.text.trim().isEmpty ? null : double.parse(_price.text),
              'extra_guest_charge': _extra.text.trim().isEmpty ? null : double.parse(_extra.text),
            });
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.controller, required this.propertyId});

  final PropertiesController controller;
  final int propertyId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ActivityEntry>>(
      future: controller.activity(propertyId),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) return const _Empty(icon: Icons.history_rounded, text: 'No activity yet.');
        return ListView.separated(
          padding: const EdgeInsets.all(22),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final a = items[i];
            final when = a.at == null
                ? ''
                : '${a.at!.day}/${a.at!.month}/${a.at!.year} ${a.at!.hour.toString().padLeft(2, '0')}:${a.at!.minute.toString().padLeft(2, '0')}';
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history_rounded, color: HomeColors.muted),
              title: Text(a.label),
              subtitle: Text([if (a.userName.isNotEmpty) a.userName, when].join(' · ')),
            );
          },
        );
      },
    );
  }
}
