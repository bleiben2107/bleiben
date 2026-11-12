import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../account/account_screen.dart';
import '../auth/auth_controller.dart';
import '../home/home_content.dart';
import '../home/home_nav.dart';
import '../home/home_overlays.dart';
import '../home/home_sections.dart' show BleibenWordmark;
import '../home/home_widgets.dart';
import '../properties/properties_controller.dart';
import '../properties/properties_screen.dart';
import '../stays/add_property_wizard_screen.dart';
import '../stays/stay.dart';
import '../stays/stays_controller.dart';

/// One entry in the Host Control Center nav (MVP plan §1 navigation).
class HostSection {
  const HostSection(this.key, this.label, this.icon, {this.permission, this.built = false, this.summary = const []});

  final String key;
  final String label;
  final IconData icon;

  /// Needed to open the section; null = any member.
  final String? permission;

  /// Implemented yet? Others show what's coming in R1.
  final bool built;
  final List<String> summary;
}

const hostSections = [
  HostSection('dashboard', 'Dashboard', Icons.space_dashboard_outlined, summary: [
    'Bookings today, upcoming, by status and by source',
    "Today's check-ins and check-outs",
    'Available, booked and blocked units',
    'Advance collected and balances pending',
  ]),
  HostSection('calendar', 'Calendar', Icons.calendar_month_outlined, summary: [
    'Timeline of every room and unit',
    'Block and unblock dates with a reason',
    '15-minute holds and overlap prevention',
  ]),
  HostSection('properties', 'Properties', Icons.holiday_village_outlined,
      permission: 'properties.read', built: true),
  HostSection('reservations', 'Reservations', Icons.event_available_outlined, summary: [
    'Direct, manual and imported bookings in one list',
    'Create, edit, cancel, check in and check out',
    'Record payments, advance and balance',
  ]),
  HostSection('channels', 'Channel Manager', Icons.sync_alt_rounded, summary: [
    'Connect Airbnb and Booking.com with iCal links',
    'Export a calendar link for each room',
    'Sync history, errors and conflicts',
  ]),
  HostSection('notifications', 'Notifications', Icons.notifications_none_rounded, summary: [
    'Booking, payment and cancellation alerts',
    'Email with SMS fallback, delivery status',
  ]),
];

/// The logged-in host workspace (host.homeyhuts.com equivalent): top nav,
/// one section at a time, account menu on the right.
class HostControlCenterScreen extends StatefulWidget {
  const HostControlCenterScreen({
    super.key,
    required this.auth,
    required this.api,
    this.initialSection = 'properties',
  });

  final AuthController auth;
  final ApiClient api;
  final String initialSection;

  @override
  State<HostControlCenterScreen> createState() => _HostControlCenterScreenState();
}

class _HostControlCenterScreenState extends State<HostControlCenterScreen> {
  late String _section = widget.initialSection;
  late final PropertiesController _properties = PropertiesController(api: widget.api);

  AuthController get auth => widget.auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.memberships.isEmpty) auth.ensureOrganization();
    });
  }

  @override
  void dispose() {
    _properties.dispose();
    super.dispose();
  }

  bool _allowed(HostSection s) =>
      s.permission == null || (auth.activeMembership?.can(s.permission!) ?? false);

  /// Opens the listing wizard (new draft, or [draft] to continue/edit).
  Future<void> openWizard({Map<String, dynamic>? draft}) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AddPropertyWizardScreen(
        api: widget.api,
        stays: StaysController(api: widget.api),
        initialDraft: draft == null ? null : Stay.fromJson(draft),
      ),
    ));
    if (mounted) _properties.load();
  }

  Future<void> _openMenu() async {
    final action = await showAccountSheet(context, signedIn: true, displayName: auth.displayName);
    if (!mounted || action == null) return;
    switch (action) {
      case AccountAction.accountSettings:
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => AccountSettingsScreen(auth: auth, api: widget.api),
        ));
      case AccountAction.createListing || AccountAction.listProperty:
        openWizard();
      case AccountAction.logout:
        await auth.logout();
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final section = hostSections.firstWhere((s) => s.key == _section);
        final name = auth.displayName.trim();
        return Scaffold(
          backgroundColor: AppTheme.paper,
          body: Column(
            children: [
              _HostTopBar(
                selected: _section,
                initial: name.isEmpty ? null : name[0].toUpperCase(),
                onSelect: (key) => setState(() => _section = key),
                onLogo: () => Navigator.of(context).maybePop(),
                onMenu: _openMenu,
              ),
              Expanded(
                child: auth.activeMembership == null
                    ? const Center(child: CircularProgressIndicator())
                    : !_allowed(section)
                        ? const _NoAccess()
                        : section.built
                            ? PropertiesScreen(
                                key: const ValueKey('properties'),
                                controller: _properties,
                                membership: auth.activeMembership!,
                                onCreate: () => openWizard(),
                                onEditListing: (raw) => openWizard(draft: raw),
                              )
                            : _ComingNext(section: section),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HostTopBar extends StatelessWidget {
  const _HostTopBar({
    required this.selected,
    required this.initial,
    required this.onSelect,
    required this.onLogo,
    required this.onMenu,
  });

  final String selected;
  final String? initial;
  final ValueChanged<String> onSelect;
  final VoidCallback onLogo;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return SafeArea(
      bottom: false,
      child: Container(
        height: 68,
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: HomeColors.line))),
        child: Row(
          children: [
            InkWell(
              onTap: onLogo,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(padding: EdgeInsets.symmetric(vertical: 6), child: BleibenWordmark()),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final s in hostSections)
                      _NavItem(
                        section: s,
                        selected: s.key == selected,
                        showLabel: wide,
                        onTap: () => onSelect(s.key),
                      ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Help',
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Need help? Write to team@bleiben.co.in')),
              ),
              icon: const Icon(Icons.help_outline_rounded),
            ),
            const SizedBox(width: 6),
            AccountMenuButton(onPressed: onMenu, initial: initial),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.section, required this.selected, required this.showLabel, required this.onTap});

  final HostSection section;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.forest : HomeColors.muted;
    return Tooltip(
      message: section.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? AppTheme.forest : Colors.transparent, width: 2)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(section.icon, size: 20, color: color),
            if (showLabel) ...[
              const SizedBox(width: 8),
              Text(section.label,
                  style: AppFonts.sans(
                      fontSize: 15, color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _ComingNext extends StatelessWidget {
  const _ComingNext({required this.section});

  final HostSection section;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(section.icon, size: 40, color: AppTheme.forest),
            const SizedBox(height: 12),
            Text(section.label, style: AppFonts.sans(fontSize: 22, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Coming next in this release', style: AppFonts.sans(color: HomeColors.muted)),
            const SizedBox(height: 18),
            for (final line in section.summary)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 18, color: AppTheme.forest),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line, style: AppFonts.sans(fontSize: 15))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

class _NoAccess extends StatelessWidget {
  const _NoAccess();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text("Your role doesn't include this section. Ask an owner or manager for access.",
          textAlign: TextAlign.center, style: AppFonts.sans(color: HomeColors.muted)),
    );
  }
}
