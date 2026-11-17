import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../account/account_screen.dart';
import '../auth/auth_controller.dart';
import '../bookings/bookings_api.dart';
import '../calendar/calendar_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../expenses/expenses_screen.dart';
import '../billing/billing_screen.dart';
import '../channels/channels_screen.dart';
import '../inbox/inbox_screen.dart';
import '../notifications/notifications_screen.dart';
import '../settings/settings_screen.dart';
import '../support/support_screen.dart';
import '../auth/auth_models.dart';
import '../reservations/reservations_screen.dart';
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
  const HostSection(this.key, this.label, this.icon, {this.permission, this.built = false, this.summary = const [], this.inNav = true});

  /// Shown in the top nav (Settings, Billing and Help open from the right-hand icons).
  final bool inNav;

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
  HostSection('dashboard', 'Dashboard', Icons.space_dashboard_outlined, permission: 'dashboard.read', built: true, summary: [
    'Bookings today, upcoming, by status and by source',
    "Today's check-ins and check-outs",
    'Available, booked and blocked units',
    'Advance collected and balances pending',
  ]),
  HostSection('calendar', 'Calendar', Icons.calendar_month_outlined, permission: 'calendar.read', built: true, summary: [
    'Timeline of every room and unit',
    'Block and unblock dates with a reason',
    '15-minute holds and overlap prevention',
  ]),
  HostSection('properties', 'Properties', Icons.holiday_village_outlined,
      permission: 'properties.read', built: true),
  HostSection('reservations', 'Reservations', Icons.event_available_outlined,
      permission: 'bookings.read', built: true, summary: [
    'Direct, manual and imported bookings in one list',
    'Create, edit, cancel, check in and check out',
    'Record payments, advance and balance',
  ]),
  HostSection('expenses', 'Expenses', Icons.account_balance_wallet_outlined, permission: 'expenses.read', built: true),
  HostSection('inbox', 'Inbox', Icons.inbox_outlined, permission: 'notifications.read', built: true),
  HostSection('channels', 'Channel Manager', Icons.sync_alt_rounded, permission: 'channels.read', built: true),
  HostSection('settings', 'Settings', Icons.settings_outlined, permission: 'org.read', built: true, inNav: false),
  HostSection('billing', 'Subscription & Billing', Icons.workspace_premium_outlined, permission: 'org.read', built: true, inNav: false),
  HostSection('support', 'Help', Icons.help_outline_rounded, built: true, inNav: false),
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

  /// Opens Add expense when Expenses is shown from the dashboard quick action.
  bool _addExpenseOnOpen = false;
  int _expenseOpens = 0;
  int _unread = 0;
  Timer? _unreadTimer;

  Map<String, dynamic>? _plan;

  /// Inbox badge = unread notifications + unread guest conversations.
  Future<void> _refreshUnread() async {
    final m = auth.activeMembership;
    if (m == null) return;
    var n = 0;
    for (final path in ['/api/notifications/unread-count', if (m.can('messages.read')) '/api/messages/unread-count']) {
      try {
        n += (((await widget.api.get(path)) as Map)['count'] as num).toInt();
      } catch (_) {
        // Badge is best-effort (e.g. guest messages not in the plan).
      }
    }
    if (mounted && n != _unread) setState(() => _unread = n);
  }

  Future<void> _refreshPlan() async {
    try {
      final r = await widget.api.get('/api/billing');
      if (mounted) setState(() => _plan = (r as Map).cast());
    } catch (_) {
      // Shown when available.
    }
  }
  late final PropertiesController _properties = PropertiesController(api: widget.api);
  late final BookingsApi _bookings = BookingsApi(widget.api);

  AuthController get auth => widget.auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.memberships.isEmpty) auth.ensureOrganization();
      _refreshUnread();
      _refreshPlan();
    });
    _unreadTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshUnread());
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
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

  bool _consumeAddExpense() {
    final v = _addExpenseOnOpen;
    _addExpenseOnOpen = false;
    return v;
  }

  Widget _buildSection(String key) {
    final m = auth.activeMembership!;
    // Keyed by org so switching organisation reloads the section.
    return switch (key) {
      'dashboard' => DashboardScreen(
          key: ValueKey('dashboard-${m.orgId}'),
          api: _bookings,
          membership: m,
          hostName: auth.displayName,
          onCreateProperty: () => openWizard(),
          onOpenSection: (k) => setState(() => _section = k),
          onAddExpense: () => setState(() {
            _section = 'expenses';
            _addExpenseOnOpen = true;
            _expenseOpens++;
          }),
        ),
      'inbox' => _InboxHub(
          key: ValueKey('inbox-${m.orgId}'),
          api: widget.api,
          bookings: _bookings,
          membership: m,
          inboxInPlan: (_plan?['features'] as List?)?.contains('inbox') ?? true,
          onUnreadChanged: _refreshUnread,
        ),
      'channels' => ChannelsScreen(key: ValueKey('channels-${m.orgId}'), api: widget.api, bookings: _bookings, membership: m),
      'settings' => SettingsScreen(key: ValueKey('settings-${m.orgId}'), api: widget.api, auth: auth, membership: m),
      'billing' => BillingScreen(key: ValueKey('billing-${m.orgId}'), api: widget.api, membership: m, onChanged: _refreshPlan),
      'support' => const SupportScreen(),
      'expenses' => ExpensesScreen(
          key: ValueKey('expenses-${m.orgId}-$_expenseOpens'),
          api: widget.api,
          membership: m,
          openAddOnStart: _consumeAddExpense(),
        ),
      'calendar' => CalendarScreen(key: ValueKey('calendar-${m.orgId}'), api: _bookings, membership: m),
      'reservations' => ReservationsScreen(key: ValueKey('reservations-${m.orgId}'), api: _bookings, membership: m),
      _ => PropertiesScreen(
          key: const ValueKey('properties'),
          controller: _properties,
          membership: m,
          onCreate: () => openWizard(),
          onEditListing: (raw) => openWizard(draft: raw),
        ),
    };
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
                unread: _unread,
                plan: _plan,
                initial: name.isEmpty ? null : name[0].toUpperCase(),
                onSelect: (key) => setState(() => _section = key),
                onLogo: () => Navigator.of(context).maybePop(),
                onMenu: _openMenu,
              ),
              if (_plan != null && ['grace', 'expired'].contains(_plan!['status']))
                _PlanBanner(plan: _plan!, onOpen: () => setState(() => _section = 'billing')),
              Expanded(
                child: auth.activeMembership == null
                    ? const Center(child: CircularProgressIndicator())
                    : !_allowed(section)
                        ? const _NoAccess()
                        : section.built
                            ? _buildSection(section.key)
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
    this.unread = 0,
    this.plan,
    required this.initial,
    required this.onSelect,
    required this.onLogo,
    required this.onMenu,
  });

  final String selected;
  final int unread;
  final Map<String, dynamic>? plan;
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
                    for (final s in hostSections.where((s) => s.inNav))
                      _NavItem(
                        section: s,
                        selected: s.key == selected,
                        badge: s.key == 'inbox' ? unread : 0,
                        showLabel: wide,
                        onTap: () => onSelect(s.key),
                      ),
                  ],
                ),
              ),
            ),
            // Full chip only on very wide screens so the nav never scrolls; an icon otherwise.
            if (plan != null && MediaQuery.sizeOf(context).width >= 1500)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ActionChip(
                  key: const Key('plan-chip'),
                  avatar: const Icon(Icons.workspace_premium_outlined, size: 16),
                  label: Text(_planLabel(plan!)),
                  onPressed: () => onSelect('billing'),
                ),
              )
            else if (plan != null)
              IconButton(
                key: const Key('plan-chip'),
                tooltip: _planLabel(plan!),
                color: ['grace', 'expired'].contains(plan!['status']) ? AppTheme.danger : selected == 'billing' ? AppTheme.forest : null,
                onPressed: () => onSelect('billing'),
                icon: const Icon(Icons.workspace_premium_outlined),
              ),
            IconButton(
              tooltip: 'Help',
              color: selected == 'support' ? AppTheme.forest : null,
              onPressed: () => onSelect('support'),
              icon: const Icon(Icons.help_outline_rounded),
            ),
            IconButton(
              key: const Key('open-settings'),
              tooltip: 'Settings',
              color: selected == 'settings' ? AppTheme.forest : null,
              onPressed: () => onSelect('settings'),
              icon: const Icon(Icons.settings_outlined),
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
  const _NavItem({required this.section, required this.selected, required this.showLabel, required this.onTap, this.badge = 0});

  final int badge;

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
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              backgroundColor: AppTheme.clay,
              child: Icon(section.icon, size: 20, color: color),
            ),
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

String _planLabel(Map<String, dynamic> p) {
  final ends = p['status_ends'] == null ? null : DateTime.parse(p['status_ends'] as String).difference(DateTime.now()).inDays + 1;
  return switch (p['status']) {
    'trialing' => 'Trial · ${ends ?? 0} day${ends == 1 ? '' : 's'} left',
    'grace' => 'Read-only · renew',
    'expired' => 'Expired · renew',
    _ => '${p['plan_name']}',
  };
}

class _PlanBanner extends StatelessWidget {
  const _PlanBanner({required this.plan, required this.onOpen});

  final Map<String, dynamic> plan;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final expired = plan['status'] == 'expired';
    return Container(
      key: const Key('plan-banner'),
      width: double.infinity,
      color: expired ? AppTheme.dangerSoft : AppTheme.warningSoft,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(children: [
        Icon(Icons.lock_clock_outlined, color: expired ? AppTheme.danger : AppTheme.warningInk),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            expired
                ? 'Your subscription has expired. Everything is read-only and your booking page is closed to new bookings.'
                : 'Your ${plan['reason'] == 'trial_ended' ? 'free trial has ended' : 'plan needs renewing'}. You can view everything, but changes are paused.',
            style: AppFonts.sans(fontWeight: FontWeight.w500, color: expired ? AppTheme.danger : AppTheme.warningInk),
          ),
        ),
        TextButton(onPressed: onOpen, child: const Text('Choose a plan')),
      ]),
    );
  }
}

/// Inbox: R1 notifications plus (when the plan includes it) guest conversations.
class _InboxHub extends StatelessWidget {
  const _InboxHub({super.key, required this.api, required this.bookings, required this.membership, required this.inboxInPlan, required this.onUnreadChanged});

  final ApiClient api;
  final BookingsApi bookings;
  final Membership membership;
  final bool inboxInPlan;
  final VoidCallback onUnreadChanged;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final messages = membership.can('messages.read');
    return DefaultTabController(
      length: messages ? 2 : 1,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(wide ? 32 : 12, 14, wide ? 32 : 12, 0),
          child: TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            const Tab(text: 'Notifications'),
            if (messages) const Tab(text: 'Guest messages'),
          ]),
        ),
        Expanded(
          child: TabBarView(children: [
            Padding(
              padding: EdgeInsets.fromLTRB(wide ? 32 : 12, 14, wide ? 32 : 12, 0),
              child: NotificationsScreen(api: api, bookings: bookings, membership: membership, onChanged: onUnreadChanged),
            ),
            if (messages)
              inboxInPlan
                  ? InboxScreen(api: api, bookings: bookings, membership: membership, onUnreadChanged: onUnreadChanged)
                  : Center(child: Text('Guest messages are part of the Growth plan.', style: AppFonts.sans(color: AppTheme.muted))),
          ]),
        ),
      ]),
    );
  }
}
