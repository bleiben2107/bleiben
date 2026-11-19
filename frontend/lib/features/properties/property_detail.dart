part of 'properties_screen.dart';

// ── Property details ─────────────────────────────────────────────────────────

/// Property detail (homyhuts layout): Property info · Calendar & Pricing ·
/// Update listing · Activity · Co-hosts, with an Actions panel.
class PropertyDetailScreen extends StatefulWidget {
  const PropertyDetailScreen({
    super.key,
    required this.controller,
    required this.propertyId,
    required this.membership,
    required this.onEditListing,
    this.onOpenSection,
    this.initialTab = 0,
  });

  final PropertiesController controller;
  final int propertyId;
  final Membership membership;
  final Future<void> Function(Map<String, dynamic> raw) onEditListing;

  /// Opens another Host Control Center section (calendar, channels, reservations).
  final ValueChanged<String>? onOpenSection;
  final int initialTab;

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
    _snack(context, error ?? (p.isLive ? 'Property deactivated — booking page taken offline' : 'Published. Your booking page is live.'));
    _reload();
  }

  Future<void> _editListing() async {
    await widget.onEditListing(_p!.raw);
    if (mounted) _reload();
  }

  void _openSection(String key) {
    final open = widget.onOpenSection;
    if (open == null) return;
    Navigator.of(context).pop();
    open(key);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return DefaultTabController(
      length: 5,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: AppTheme.paper,
        appBar: AppBar(
          backgroundColor: AppTheme.paper,
          titleSpacing: 0,
          title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('All properties', style: AppFonts.sans(fontSize: 12.5, color: HomeColors.muted)),
            Text(p?.displayTitle ?? 'Property', overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w600)),
          ]),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Property info', iconMargin: EdgeInsets.zero),
              Tab(icon: Icon(Icons.calendar_month_outlined, size: 18), text: 'Calendar & Pricing', iconMargin: EdgeInsets.zero),
              Tab(icon: Icon(Icons.edit_outlined, size: 18), text: 'Update listing', iconMargin: EdgeInsets.zero),
              Tab(icon: Icon(Icons.history_rounded, size: 18), text: 'Activity', iconMargin: EdgeInsets.zero),
              Tab(icon: Icon(Icons.group_outlined, size: 18), text: 'Co-hosts', iconMargin: EdgeInsets.zero),
            ],
          ),
        ),
        body: _error != null
            ? Center(child: Text(_error!))
            : p == null
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(children: [
                    _InfoTab(state: this, property: p),
                    _CalendarPricingTab(state: this, property: p),
                    _ListingTab(state: this, property: p),
                    _ActivityTab(controller: c, propertyId: p.id),
                    _CoHostsTab(api: c.api, membership: widget.membership, property: p),
                  ]),
      ),
    );
  }
}

String _mediaUrl(String url) => url.startsWith('/') ? '${ApiConfig.baseUrl}$url' : url;

Widget _panel({required Widget child, EdgeInsets padding = const EdgeInsets.all(18), Key? key}) => Container(
      key: key,
      padding: padding,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: HomeColors.line)),
      child: child,
    );

// ── Property info ──

class _InfoTab extends StatelessWidget {
  const _InfoTab({required this.state, required this.property});

  final _PropertyDetailScreenState state;
  final PropertySummary property;

  @override
  Widget build(BuildContext context) {
    final p = property;
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final header = _panel(
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 120,
            height: 90,
            child: p.coverPhoto == null || p.coverPhoto!.isEmpty
                ? Container(color: HomeColors.mist, child: const Icon(Icons.home_work_outlined, color: AppTheme.forest, size: 34))
                : Image.network(_mediaUrl(p.coverPhoto!), fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(color: HomeColors.mist, child: const Icon(Icons.image_not_supported_outlined))),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 10, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('#${p.serialId}', style: AppFonts.sans(color: HomeColors.muted, fontWeight: FontWeight.w600)),
              StatusPill(status: p.status),
              if (p.isLive)
                Text(p.instantBooking ? 'Instant booking on' : 'Booking requests', style: AppFonts.sans(fontSize: 12.5, color: HomeColors.muted)),
            ]),
            const SizedBox(height: 6),
            Text(p.displayTitle, style: AppFonts.sans(fontSize: 19, fontWeight: FontWeight.w600)),
            if (p.location.isNotEmpty) Text(p.location, style: AppFonts.sans(color: HomeColors.muted)),
            const SizedBox(height: 4),
            Text('${p.roomCount} room type${p.roomCount == 1 ? '' : 's'} · ${p.unitCount} unit${p.unitCount == 1 ? '' : 's'}',
                style: AppFonts.sans(fontSize: 13, color: HomeColors.muted)),
          ]),
        ),
      ]),
    );
    final main = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: 14),
      _BookingLinkCard(property: p, onViewBookings: state.widget.onOpenSection == null ? null : () => state._openSection('reservations')),
    ]);
    final actions = _ActionsPanel(state: state, property: p);
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: main), const SizedBox(width: 16), SizedBox(width: 300, child: actions)])
        else ...[main, const SizedBox(height: 14), actions],
      ],
    );
  }
}

/// Public booking link + QR code. Bookings made on it land in Reservations,
/// Calendar and the Dashboard as "Bleiben Direct".
class _BookingLinkCard extends StatelessWidget {
  const _BookingLinkCard({required this.property, this.onViewBookings});

  final PropertySummary property;
  final VoidCallback? onViewBookings;

  Future<void> _downloadQr(BuildContext context, String url) async {
    final data = await QrPainter(data: url, version: QrVersions.auto, gapless: true, eyeStyle: const QrEyeStyle(color: Colors.black), dataModuleStyle: const QrDataModuleStyle(color: Colors.black))
        .toImageData(720, format: ImageByteFormat.png);
    if (data == null || !context.mounted) return;
    // White background so the QR prints and scans everywhere.
    final ok = downloadBytes('${property.serialId.isEmpty ? 'booking' : property.serialId}-qr.png', data.buffer.asUint8List(), mime: 'image/png');
    if (context.mounted) _snack(context, ok ? 'QR code downloaded' : 'Download is available in the web app');
  }

  @override
  Widget build(BuildContext context) {
    final p = property;
    final url = p.bookingUrl;
    if (!p.isLive || url == null) {
      return _panel(
        key: const Key('booking-link-card'),
        child: Row(children: [
          const Icon(Icons.qr_code_2_rounded, color: AppTheme.warningInk, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Not live yet. Add your rooms and publish to get your public booking link and QR code.',
                style: AppFonts.sans(color: AppTheme.warningInk)),
          ),
        ]),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 700;
    final qr = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: HomeColors.line), borderRadius: BorderRadius.circular(10)),
      child: QrImageView(key: const Key('booking-qr'), data: url, size: 150, backgroundColor: Colors.white, gapless: true),
    );
    final details = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Public booking link', style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('Share the link or let guests scan the QR code. Every booking made here shows up in your Calendar, Reservations and Dashboard as Bleiben Direct, and its dates close straight away.',
          style: AppFonts.sans(fontSize: 13, color: HomeColors.muted)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: AppTheme.successSoft, borderRadius: BorderRadius.circular(10)),
        child: Row(children: [
          const Icon(Icons.public_rounded, color: AppTheme.forest, size: 18),
          const SizedBox(width: 8),
          Expanded(child: SelectableText(url, key: const Key('booking-url'), style: AppFonts.sans(fontWeight: FontWeight.w600))),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(
          key: const Key('copy-booking-link'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: url));
            _snack(context, 'Booking link copied');
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('Copy link'),
        ),
        OutlinedButton.icon(
          key: const Key('download-qr'),
          onPressed: () => _downloadQr(context, url),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Download QR'),
        ),
        if (onViewBookings != null)
          TextButton.icon(onPressed: onViewBookings, icon: const Icon(Icons.event_available_outlined, size: 18), label: const Text('View bookings')),
      ]),
    ]);
    return _panel(
      key: const Key('booking-link-card'),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [qr, const SizedBox(width: 18), Expanded(child: details)])
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Center(child: qr), const SizedBox(height: 14), details]),
    );
  }
}

class _ActionsPanel extends StatefulWidget {
  const _ActionsPanel({required this.state, required this.property});

  final _PropertyDetailScreenState state;
  final PropertySummary property;

  @override
  State<_ActionsPanel> createState() => _ActionsPanelState();
}

class _ActionsPanelState extends State<_ActionsPanel> {
  bool _working = false;

  _PropertyDetailScreenState get s => widget.state;
  PropertySummary get p => widget.property;

  Future<void> _clone() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clone this property?'),
        content: const Text('Creates a new draft with the same details, photos, rooms and prices. Bookings are not copied.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(key: const Key('confirm-clone'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Clone')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _working = true);
    try {
      final copy = await s.c.clone(p.id);
      unawaited(s.c.load());
      if (!mounted) return;
      _snack(context, '"${copy.displayTitle}" created as a draft');
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => PropertyDetailScreen(
          controller: s.c,
          propertyId: copy.id,
          membership: s.widget.membership,
          onEditListing: s.widget.onEditListing,
          onOpenSection: s.widget.onOpenSection,
        ),
      ));
    } on ApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _offlineBooking() async {
    if (p.rooms.isEmpty) return _snack(context, 'Add a room first (Calendar & Pricing tab).');
    final b = await showCreateBookingDialog(context, api: BookingsApi(s.c.api), roomId: p.rooms.first.id);
    if (b != null && mounted) _snack(context, 'Booking ${b.code} created for ${b.guestName}');
  }

  Future<void> _instant(bool on) async {
    setState(() => _working = true);
    final error = await s.c.setInstantBooking(p.id, on);
    if (!mounted) return;
    setState(() => _working = false);
    _snack(context, error ?? (on ? 'Instant booking turned on' : 'Instant booking off — your link now takes booking requests'));
    s._reload();
  }

  Future<void> _delete() async {
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('Delete "${p.displayTitle}"?'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('The property leaves your list and its booking page goes offline. Past bookings and expenses keep their records.'),
              const SizedBox(height: 12),
              const Text('Type DELETE to confirm.'),
              const SizedBox(height: 6),
              TextField(key: const Key('delete-confirm'), controller: confirm, autofocus: true, onChanged: (_) => setD(() {})),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(
              key: const Key('confirm-delete-property'),
              onPressed: confirm.text.trim().toUpperCase() == 'DELETE' ? () => Navigator.pop(ctx, true) : null,
              style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              child: const Text('Delete property'),
            ),
          ],
        ),
      ),
    );
    confirm.dispose();
    if (ok != true || !mounted) return;
    setState(() => _working = true);
    final error = await s.c.delete(p.id);
    if (!mounted) return;
    setState(() => _working = false);
    if (error != null) return _snack(context, error);
    _snack(context, '"${p.displayTitle}" deleted');
    Navigator.of(context).pop();
  }

  Widget _group(String title, String help, Widget action) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(title, style: AppFonts.sans(fontWeight: FontWeight.w600, fontSize: 13.5)),
            const SizedBox(width: 4),
            Tooltip(message: help, child: const Icon(Icons.help_outline_rounded, size: 15, color: HomeColors.muted)),
          ]),
          const SizedBox(height: 6),
          action,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final canBook = s.widget.membership.can('bookings.write');
    const small = ButtonStyle(visualDensity: VisualDensity.compact);
    return _panel(
      key: const Key('property-actions'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Actions', style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700)),
        if (s._canWrite)
          _group('Clone property', 'Start a new listing from this one',
              Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(key: const Key('clone-property'), style: small, onPressed: _working ? null : _clone, icon: const Icon(Icons.copy_all_outlined, size: 16), label: const Text('Clone')))),
        if (canBook)
          _group('Bookings', 'Add a phone, WhatsApp or walk-in booking',
              Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(key: const Key('offline-booking'), style: small, onPressed: _offlineBooking, icon: const Icon(Icons.add_box_outlined, size: 16), label: const Text('Offline booking')))),
        if (s._canWrite)
          _group(
            'Instant booking',
            'On: guests pay and the booking is confirmed straight away (needs online payments in Settings). Off: guests send a booking request you confirm.',
            Row(children: [
              Switch(key: const Key('instant-booking'), value: p.instantBooking, onChanged: _working ? null : _instant),
              const SizedBox(width: 6),
              Text(p.instantBooking ? 'On' : 'Off', style: AppFonts.sans(color: HomeColors.muted)),
            ]),
          ),
        if (s._canPublish)
          _group(
            'Property status',
            p.isLive ? 'Deactivate takes your booking page offline. Bookings already made stay.' : 'Publish to open your booking page and get your link.',
            Align(
              alignment: Alignment.centerLeft,
              child: p.isLive
                  ? OutlinedButton.icon(
                      key: const Key('deactivate-property'),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: AppTheme.danger), visualDensity: VisualDensity.compact),
                      onPressed: s._busy ? null : s._togglePublish,
                      icon: const Icon(Icons.power_settings_new_rounded, size: 16),
                      label: const Text('Deactivate'),
                    )
                  : ElevatedButton.icon(
                      key: const Key('publish-property'),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(0, 38), visualDensity: VisualDensity.compact),
                      onPressed: s._busy ? null : s._togglePublish,
                      icon: const Icon(Icons.rocket_launch_outlined, size: 16),
                      label: const Text('Publish'),
                    ),
            ),
          ),
        if (s.widget.membership.can('properties.delete'))
          _group(
            'Delete property',
            'Removes the listing for good and takes its booking page offline. Past bookings keep their records.',
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('delete-property'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger, visualDensity: VisualDensity.compact),
                onPressed: _working ? null : _delete,
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: const Text('Delete'),
              ),
            ),
          ),
      ]),
    );
  }
}

// ── Calendar & Pricing ──

class _CalendarPricingTab extends StatelessWidget {
  const _CalendarPricingTab({required this.state, required this.property});

  final _PropertyDetailScreenState state;
  final PropertySummary property;

  @override
  Widget build(BuildContext context) {
    final open = state.widget.onOpenSection != null;
    final m = state.widget.membership;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            if (m.can('calendar.read'))
              OutlinedButton.icon(
                  onPressed: () => state._openSection('calendar'),
                  icon: const Icon(Icons.calendar_month_outlined, size: 18),
                  label: const Text('Open calendar (prices, blocks)')),
            if (m.can('channels.read'))
              OutlinedButton.icon(
                  key: const Key('open-channels'),
                  onPressed: () => state._openSection('channels'),
                  icon: const Icon(Icons.sync_alt_rounded, size: 18),
                  label: const Text('Sync Airbnb / Booking.com calendars')),
          ]),
        ),
      Expanded(child: _RoomsTab(controller: state.c, property: property, canWrite: state._canWrite, onChanged: state._reload)),
    ]);
  }
}

// ── Update listing ──

class _ListingTab extends StatelessWidget {
  const _ListingTab({required this.state, required this.property});

  final _PropertyDetailScreenState state;
  final PropertySummary property;

  @override
  Widget build(BuildContext context) {
    final p = property;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 170, child: Text(label, style: AppFonts.sans(color: HomeColors.muted))),
            Expanded(child: Text(value.isEmpty ? '—' : value, style: AppFonts.sans(fontSize: 15))),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        _panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text('Listing details', style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700))),
              if (state._canWrite)
                ElevatedButton.icon(
                  key: const Key('edit-listing'),
                  onPressed: state._editListing,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 42)),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: Text(p.isLive ? 'Update listing' : 'Continue setup'),
                ),
            ]),
            const SizedBox(height: 8),
            row('Title', p.title),
            row('Property type', p.propertyType),
            row('Location', p.location),
            row('Guests', p.guests == 0 ? '' : '${p.guests}'),
            row('Base price / night', p.basePrice > 0 ? _money(p.basePrice) : ''),
            row('Extra guest charge', p.extraGuestCharge > 0 ? _money(p.extraGuestCharge) : ''),
            row('Advance at booking', p.advancePercent > 0 ? '${p.advancePercent.toStringAsFixed(0)}%' : ''),
            row('Rooms & units', '${p.roomCount} room type${p.roomCount == 1 ? '' : 's'}, ${p.unitCount} unit${p.unitCount == 1 ? '' : 's'}'),
          ]),
        ),
      ],
    );
  }
}

// ── Co-hosts ──

/// What each role can reach, per module (from the server's role matrix).
const _accessModules = <(String, String, String)>[
  // label, read permission, write permission
  ('Dashboard', 'dashboard.read', 'dashboard.read'),
  ('Calendar & Pricing', 'calendar.read', 'calendar.write'),
  ('Reservations', 'bookings.read', 'bookings.write'),
  ('Properties', 'properties.read', 'properties.write'),
  ('Expenses', 'expenses.read', 'expenses.write'),
  ('Guest messages', 'messages.read', 'messages.write'),
  ('Team & settings', 'team.read', 'team.manage'),
];

const _rolePerms = <OrgRole, Set<String>>{
  OrgRole.manager: {
    'dashboard.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.write', 'properties.read', 'properties.write',
    'expenses.read', 'expenses.write', 'messages.read', 'messages.write', 'team.read', 'team.manage',
  },
  OrgRole.staff: {
    'dashboard.read', 'calendar.read', 'calendar.write', 'bookings.read', 'bookings.write', 'properties.read', 'properties.write',
    'expenses.read', 'expenses.write', 'messages.read', 'messages.write', 'team.read',
  },
  OrgRole.readOnly: {'dashboard.read', 'calendar.read', 'bookings.read', 'properties.read', 'expenses.read', 'messages.read', 'team.read'},
};

String _roleName(OrgRole r) => r == OrgRole.staff ? 'Staff (executive)' : r.label;

class _CoHostsTab extends StatefulWidget {
  const _CoHostsTab({required this.api, required this.membership, required this.property});

  final ApiClient api;
  final Membership membership;
  final PropertySummary property;

  @override
  State<_CoHostsTab> createState() => _CoHostsTabState();
}

class _CoHostsTabState extends State<_CoHostsTab> {
  List<TeamMember>? _members;
  String? _error;

  bool get _canManage => widget.membership.can('team.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.get('/api/orgs/${widget.membership.orgId}/members') as List;
      if (mounted) setState(() => _members = [for (final m in list) TeamMember.fromJson((m as Map).cast<String, dynamic>())]);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _add() async {
    final invited = await showSideSheet<bool>(
      context,
      (_) => _AddCoHostSheet(api: widget.api, membership: widget.membership, property: widget.property),
      width: 600,
    );
    if (invited == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final members = _members;
    return ListView(
      padding: const EdgeInsets.all(22),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Co-hosts', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
              Text('People who help you run your stays. Their role (from Account settings → Team) decides what they can see and change.',
                  style: AppFonts.sans(color: HomeColors.muted, fontSize: 13)),
            ]),
          ),
          if (_canManage)
            ElevatedButton.icon(
              key: const Key('add-cohost'),
              onPressed: _add,
              style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
              label: const Text('Add co-host'),
            ),
        ]),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: AppFonts.sans(color: AppTheme.danger))
        else if (members == null)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()))
        else
          _panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final (i, m) in members.indexed) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: CircleAvatar(backgroundColor: AppTheme.sage, child: Text(m.displayName.characters.first.toUpperCase())),
                  title: Text(m.displayName),
                  subtitle: Text([m.email ?? '', if (m.status == 'invited') 'Invite sent'].where((x) => x.isNotEmpty).join(' · ')),
                  trailing: Chip(label: Text(_roleName(m.role))),
                ),
              ],
              if (members.length <= 1)
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Text('No co-hosts yet. Add a manager or an executive to share the work.', style: AppFonts.sans(color: HomeColors.muted)),
                ),
            ]),
          ),
      ],
    );
  }
}

class _AddCoHostSheet extends StatefulWidget {
  const _AddCoHostSheet({required this.api, required this.membership, required this.property});

  final ApiClient api;
  final Membership membership;
  final PropertySummary property;

  @override
  State<_AddCoHostSheet> createState() => _AddCoHostSheetState();
}

class _AddCoHostSheetState extends State<_AddCoHostSheet> {
  final _email = TextEditingController();
  OrgRole _role = OrgRole.staff;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) return setState(() => _error = 'Enter a valid email address');
    setState(() => (_sending = true, _error = null));
    try {
      await widget.api.post('/api/orgs/${widget.membership.orgId}/invites', {'email': email, 'role': _role.apiValue});
      if (!mounted) return;
      _snack(context, 'Invitation sent to $email');
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = _rolePerms[_role]!;
    Widget level(String text, bool on, Color color) => Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: on ? color : Colors.white,
            border: Border.all(color: on ? color : HomeColors.line),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text, style: AppFonts.sans(fontSize: 12, color: on ? Colors.white : HomeColors.muted, fontWeight: on ? FontWeight.w600 : null)),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
        child: Row(children: [
          IconButton(tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close)),
          Text('Add co-host', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
        ]),
      ),
      const Divider(height: 1),
      Expanded(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          TextField(
            key: const Key('cohost-email'),
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email', hintText: 'name@example.com', helperText: 'An invitation will be sent to this email address.'),
          ),
          const SizedBox(height: 18),
          Text('Role', style: AppFonts.sans(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final r in [OrgRole.manager, OrgRole.staff, OrgRole.readOnly])
              ChoiceChip(key: Key('cohost-role-${r.apiValue}'), label: Text(_roleName(r)), selected: _role == r, onSelected: (_) => setState(() => _role = r)),
          ]),
          const SizedBox(height: 6),
          Text(_role.description, style: AppFonts.sans(fontSize: 13, color: HomeColors.muted)),
          const SizedBox(height: 18),
          Text('Access', style: AppFonts.sans(fontWeight: FontWeight.w700)),
          Text('What a ${_roleName(_role)} can do. It applies to every property in ${widget.membership.orgName}.',
              style: AppFonts.sans(fontSize: 12.5, color: HomeColors.muted)),
          const SizedBox(height: 8),
          _panel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(children: [
              for (final (i, (label, read, write)) in _accessModules.indexed) ...[
                if (i > 0) const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(children: [
                    Expanded(child: Text(label, style: AppFonts.sans(fontWeight: FontWeight.w600, fontSize: 13.5))),
                    level('No access', !perms.contains(read), AppTheme.danger),
                    level('Read only', perms.contains(read) && !perms.contains(write), AppTheme.clay),
                    level('Full access', perms.contains(write), AppTheme.forest),
                  ]),
                ),
              ],
            ]),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: AppFonts.sans(color: AppTheme.danger))),
        ]),
      ),
      const Divider(height: 1),
      Padding(
        padding: const EdgeInsets.all(14),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            key: const Key('send-cohost-invite'),
            onPressed: _sending ? null : _send,
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.mail_outline, size: 18),
            label: const Text('Send invite'),
          ),
        ]),
      ),
    ]);
  }
}
