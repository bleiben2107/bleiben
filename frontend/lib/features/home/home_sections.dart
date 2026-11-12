import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'home_content.dart';
import 'home_mockups.dart';
import 'home_overlays.dart';
import 'home_widgets.dart';

TextStyle _body(
        {double size = 15.5,
        Color color = HomeColors.muted,
        double height = 1.55}) =>
    AppFonts.sans(fontSize: size, color: color, height: height);

TextStyle _title({double size = 18, Color color = AppTheme.ink}) =>
    AppFonts.sans(
        fontSize: size, fontWeight: FontWeight.w600, color: color, height: 1.3);

// ── 1. Hero ──────────────────────────────────────────────────────────────────

class HeroSection extends StatelessWidget {
  const HeroSection({
    super.key,
    required this.onStart,
    required this.onTalk,
    required this.onSeePricing,
    required this.onAllChannels,
  });

  final VoidCallback onStart;
  final VoidCallback onTalk;
  final VoidCallback onSeePricing;
  final VoidCallback onAllChannels;

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: HomeColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cottage_rounded, size: 16, color: AppTheme.clay),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Built for homestays, villas & holiday homes',
                  style: AppFonts.sans(
                      fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const AccentHeadline(
          lead: 'Run every stay from ',
          accent: 'one calm calendar',
          size: 60,
        ),
        const SizedBox(height: 22),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Text(
            'Bleiben keeps Airbnb, Booking.com, Vrbo and your direct bookings in step — '
            'prices, availability and guests, updated everywhere the moment anything changes.',
            style: _body(size: 18.5),
          ),
        ),
        const SizedBox(height: 26),
        Text('Works with the channels you already use',
            style: _body(size: 13.5)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in kChannels) _ChannelChip(c),
            ActionChip(
              tooltip: 'See all supported channels',
              onPressed: onAllChannels,
              label:
                  Text('+${kSupportedChannels.length - kChannels.length} more'),
              labelStyle: AppFonts.sans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.forest),
              backgroundColor: Colors.white,
              side: const BorderSide(color: HomeColors.line),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ],
        ),
        const SizedBox(height: 34),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            PillButton(
              label: 'Start free trial',
              icon: Icons.arrow_forward_rounded,
              onPressed: onStart,
            ),
            PillButton(
              label: 'Talk to our team',
              icon: Icons.headset_mic_outlined,
              filled: false,
              onPressed: onTalk,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: [
            Text('No card needed · Cancel anytime ·', style: _body(size: 13.5)),
            TextButton(
              onPressed: onSeePricing,
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero),
              child: Text('See pricing',
                  style: AppFonts.sans(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.forest,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ),
        if (kLaunchOffer.isLive) ...[
          const SizedBox(height: 22),
          OfferCard(offer: kLaunchOffer, onSeePricing: onSeePricing),
        ],
      ],
    );

    return SectionShell(
      vertical: 80,
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Colors.white, Color(0xFFFBF6EE), Color(0xFFEFF5F1)],
      ),
      child: wide
          ? Row(
              children: [
                Expanded(flex: 5, child: copy),
                const SizedBox(width: 56),
                const Expanded(flex: 6, child: ChannelSyncBoard()),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                copy,
                const SizedBox(height: 44),
                const ChannelSyncBoard()
              ],
            ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip(this.channel);

  final Channel channel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HomeColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(channel.icon, size: 16, color: channel.color),
          const SizedBox(width: 6),
          Text(channel.name,
              style: AppFonts.sans(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ── 2. Feature tiles ─────────────────────────────────────────────────────────

class FeatureTilesSection extends StatelessWidget {
  const FeatureTilesSection({super.key});

  static const _tiles = [
    (
      Icons.sync_alt_rounded,
      'Channel sync',
      'Prices and availability pushed to every channel in real time.'
    ),
    (
      Icons.phone_in_talk_outlined,
      'Offline bookings',
      'Log walk-in, phone and WhatsApp guests next to OTA ones.'
    ),
    (
      Icons.language_rounded,
      'Your own website',
      'A booking site under your brand, with online payments.'
    ),
    (
      Icons.account_balance_wallet_outlined,
      'Expenses & profit',
      'See what each property really earns after costs.'
    ),
    (
      Icons.forum_outlined,
      'One inbox',
      'Guest messages from every channel in a single thread list.'
    ),
    (
      Icons.groups_2_outlined,
      'Team access',
      'Invite co-hosts and staff with the right permissions.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      vertical: 72,
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Everything in one place',
            lead: 'The tools hosts reach for ',
            accent: 'every single day',
          ),
          const SizedBox(height: 44),
          ResponsiveGrid(
            minItemWidth: 300,
            children: [
              for (final (icon, title, text) in _tiles)
                SurfaceCard(
                  elevated: false,
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconBadge(icon),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: _title(size: 17)),
                            const SizedBox(height: 4),
                            Text(text, style: _body(size: 14.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 3. Unified calendar ──────────────────────────────────────────────────────

class CalendarSection extends StatelessWidget {
  const CalendarSection({super.key, required this.onExplore});

  /// "See the calendar live" — opens the demo booking.
  final VoidCallback onExplore;

  static const _points = [
    (
      Icons.view_timeline_outlined,
      'Every property, one view',
      'Bookings from all channels on a single colour-coded timeline.'
    ),
    (
      Icons.price_change_outlined,
      'Change prices in a click',
      'Edit one night or every weekend across properties at once.'
    ),
    (
      Icons.event_busy_outlined,
      'Block any date',
      'Maintenance, owner stays or walk-ins — closed everywhere in seconds.'
    ),
    (
      Icons.phone_iphone_rounded,
      'Same calendar on your phone',
      'The Bleiben app stays in sync wherever you are.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      background: HomeColors.mist,
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Unified calendar',
            lead: 'Every booking, ',
            accent: 'one live view',
            subtitle:
                'Airbnb, Booking.com, Vrbo, walk-ins and your own website on one timeline — '
                'on the web and in your pocket.',
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: HomeColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.touch_app_outlined,
                    size: 16, color: AppTheme.clay),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Try it: tap any open date to block it',
                      style: _body(size: 13.5, color: AppTheme.ink)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          if (HomeLayout.width(context) >= 1180)
            const Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: CalendarMock()),
                SizedBox(width: 28),
                PhoneCalendarMock(),
              ],
            )
          else ...[
            const CalendarMock(),
            const SizedBox(height: 28),
            const Center(child: PhoneCalendarMock()),
          ],
          const SizedBox(height: 12),
          Text('The same live calendar, on web and mobile.',
              textAlign: TextAlign.center, style: _body(size: 14)),
          const SizedBox(height: 36),
          ResponsiveGrid(
            minItemWidth: 240,
            maxColumns: 4,
            children: [
              for (final (icon, title, text) in _points)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconBadge(icon, color: AppTheme.clay, size: 40),
                    const SizedBox(height: 12),
                    Text(title, style: _title(size: 16.5)),
                    const SizedBox(height: 4),
                    Text(text, style: _body(size: 14.5)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 28),
          TextButton(
            onPressed: onExplore,
            child: Text('See the calendar live in a demo →',
                style: AppFonts.sans(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.forest)),
          ),
        ],
      ),
    );
  }
}

// ── 4. Before / after ────────────────────────────────────────────────────────

class BeforeAfterSection extends StatelessWidget {
  const BeforeAfterSection({super.key});

  static const _pains = [
    'Updating five calendars by hand after every booking',
    'Double bookings and awkward cancellation calls',
    'Paying commission on guests who would have booked direct',
    'Income and expenses spread across spreadsheets',
    'Evenings lost to changing prices one channel at a time',
  ];

  static const _wins = [
    ('1', 'calendar for every channel and property'),
    ('0', 'manual copy-paste between booking sites'),
    ('1 click', 'to change prices across your portfolio'),
    ('₹0', 'commission on bookings from your own site'),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);

    final before = Container(
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: HomeColors.night,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Tag('Without Bleiben', dark: true),
          const SizedBox(height: 18),
          Text('Hosting the hard way',
              style: _title(size: 24, color: Colors.white)),
          const SizedBox(height: 18),
          for (final pain in _pains)
            BulletLine(
              pain,
              icon: Icons.close_rounded,
              iconColor: const Color(0xFFFF8A80),
              textColor: Colors.white70,
            ),
        ],
      ),
    );

    final after = SurfaceCard(
      padding: const EdgeInsets.all(30),
      color: const Color(0xFFFBF6EE),
      borderColor: AppTheme.clay.withValues(alpha: 0.25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Tag('With Bleiben'),
          const SizedBox(height: 18),
          Text('Your business on autopilot', style: _title(size: 24)),
          const SizedBox(height: 6),
          Text('Less admin. More bookings. A calmer week.', style: _body()),
          const SizedBox(height: 18),
          for (final (value, label) in _wins)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      value,
                      style: AppFonts.display(
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.forest,
                      ),
                    ),
                  ),
                  Expanded(
                      child: Text(label,
                          style: _body(size: 14.5, color: AppTheme.ink))),
                ],
              ),
            ),
        ],
      ),
    );

    const arrow = CircleAvatar(
      radius: 24,
      backgroundColor: AppTheme.clay,
      child: Icon(Icons.arrow_forward_rounded, color: Colors.white),
    );

    return SectionShell(
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Why hosts switch',
            lead: 'Spend less time managing. ',
            accent: 'More time hosting.',
            subtitle:
                'Whether you run one homestay or a hundred holiday homes, Bleiben takes the '
                'repetitive work off your plate so you can focus on guests.',
          ),
          const SizedBox(height: 48),
          if (wide)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: before),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20),
                    child: Center(child: arrow),
                  ),
                  Expanded(child: after),
                ],
              ),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                before,
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child:
                      Center(child: RotatedBox(quarterTurns: 1, child: arrow)),
                ),
                after,
              ],
            ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.dark = false});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.08)
            : AppTheme.clay.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label.toUpperCase(),
        style: AppFonts.sans(
          fontSize: 11.5,
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
          color: dark ? Colors.white70 : AppTheme.clay,
        ),
      ),
    );
  }
}

// ── 5. Feature tabs ──────────────────────────────────────────────────────────

class _FeatureTab {
  const _FeatureTab(this.label, this.icon, this.title, this.tags, this.bullets,
      {this.soon = false});

  final String label;
  final IconData icon;
  final String title;
  final List<String> tags;
  final List<String> bullets;
  final bool soon;
}

class FeatureTabsSection extends StatefulWidget {
  const FeatureTabsSection({super.key, required this.onLearnMore});

  /// Called with the tab label when "Learn more" is pressed.
  final ValueChanged<String> onLearnMore;

  @override
  State<FeatureTabsSection> createState() => _FeatureTabsSectionState();
}

class _FeatureTabsSectionState extends State<FeatureTabsSection> {
  static const _tabs = [
    _FeatureTab(
      'Calendar',
      Icons.calendar_month_outlined,
      'One calendar. Every booking. Full control.',
      ['Real-time sync', 'All channels', 'All properties'],
      [
        'See bookings from every connected channel across all your properties.',
        'Manage OTA, direct, walk-in and offline bookings from one screen.',
        'Change availability and prices once — every channel follows.',
        'Automatic sync keeps double bookings off your calendar.',
      ],
    ),
    _FeatureTab(
      'Direct bookings',
      Icons.storefront_outlined,
      'Own your guests. Keep more of every booking.',
      ['No commission', 'Branded invoices', 'Upsells'],
      [
        'Record direct, phone, WhatsApp and walk-in bookings professionally.',
        'Send branded confirmations, payment reminders and invoices.',
        'Track add-ons like meals, transfers and experiences per stay.',
        'Turn happy guests into repeat direct bookings.',
      ],
    ),
    _FeatureTab(
      'Channel manager',
      Icons.hub_outlined,
      'More channels. More travellers. More bookings.',
      ['Indian & global OTAs', 'Real-time sync', 'No double bookings'],
      [
        'Connect Airbnb, Booking.com, Vrbo, Agoda, MakeMyTrip and more.',
        'Reach travellers wherever they search without extra admin.',
        'Prices, availability and bookings stay in sync automatically.',
        'Manage every channel from a single dashboard.',
      ],
    ),
    _FeatureTab(
      'Booking website',
      Icons.web_outlined,
      'Your brand. Your website. Your guests.',
      ['Custom domain', 'Online payments', 'SEO-ready'],
      [
        'Launch a fast, mobile-friendly booking site under your own name.',
        'Accept secure online payments with no platform commission.',
        'Availability syncs with your channels in real time.',
        'Built to be found on search engines from day one.',
      ],
    ),
    _FeatureTab(
      'Smart listings',
      Icons.dashboard_customize_outlined,
      'One property. Many listings. Zero double bookings.',
      ['Room or whole home', 'Linked availability', 'Peak-season mode'],
      [
        'List the same home as single rooms, room combinations or the entire property.',
        'A booking on any version closes the overlapping ones automatically.',
        'Fill more nights in the off season by letting guests book the way they want.',
        'Switch to whole-home only for peak dates with one tap.',
      ],
    ),
    _FeatureTab(
      'Bulk pricing',
      Icons.trending_up_rounded,
      'Single or bulk price changes, without the busywork.',
      ['Bulk updates', 'Percentage rules', 'Seasons'],
      [
        'Raise or lower prices across many properties with one percentage.',
        'Prepare weekends, festivals and long weekends in a few taps.',
        'Changes reach every channel instantly.',
        'Coming soon: demand-based price suggestions.',
      ],
    ),
    _FeatureTab(
      'Expenses',
      Icons.receipt_long_outlined,
      'Know your real profit, not just your revenue.',
      ['Property P&L', 'Expense tracking', 'Reports'],
      [
        'Log rent, salaries, utilities, repairs, commission and supplies.',
        'See profit per property and per month at a glance.',
        'Spot which homes earn the most — and which cost you.',
        'Export clean reports for your accountant.',
      ],
    ),
    _FeatureTab(
      'Analytics',
      Icons.insights_outlined,
      'Turn your booking data into better decisions.',
      ['Occupancy & ADR', 'Channel mix', 'Portfolio trends'],
      [
        'Track revenue, occupancy, average daily rate and direct-booking share.',
        'See which channels and properties perform best.',
        'Compare months and seasons across your whole portfolio.',
        'Coming soon: ask questions about your business in plain language.',
      ],
      soon: true,
    ),
    _FeatureTab(
      'Inbox',
      Icons.mark_chat_unread_outlined,
      'Every guest message. One inbox.',
      ['All channels', 'Saved replies', 'Smart suggestions'],
      [
        'Read and reply to Airbnb, Booking.com and direct guests in one place.',
        'Save answers to the questions guests ask every week.',
        'Never miss a message while you are on the move.',
        'Coming soon: suggested replies drafted for you.',
      ],
      soon: true,
    ),
    _FeatureTab(
      'Team',
      Icons.badge_outlined,
      'Let your team help run the business.',
      ['Co-hosts', 'Manager roles', 'Shared access'],
      [
        'Add co-hosts, caretakers and managers to your account.',
        'Give each person access to just the properties they handle.',
        'No more sharing your personal login.',
        'Work together as your portfolio grows.',
      ],
    ),
  ];

  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final tab = _tabs[_index];
    final wide = HomeLayout.isWide(context);

    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tab.title, style: _title(size: 26)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final t in tab.tags)
              Chip(
                label: Text(t),
                labelStyle:
                    AppFonts.sans(fontSize: 13, color: AppTheme.forest),
                backgroundColor: AppTheme.forest.withValues(alpha: 0.07),
                side: BorderSide.none,
                shape: const StadiumBorder(),
              ),
          ],
        ),
        const SizedBox(height: 16),
        for (final b in tab.bullets)
          BulletLine(b, icon: Icons.arrow_forward_rounded),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => widget.onLearnMore(tab.label),
          style: TextButton.styleFrom(padding: EdgeInsets.zero),
          child: Text('Learn more about ${tab.label.toLowerCase()} →',
              style: AppFonts.sans(
                  fontWeight: FontWeight.w600, color: AppTheme.forest)),
        ),
      ],
    );

    final visual = Container(
      height: 280,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.forest.withValues(alpha: 0.9), AppTheme.moss],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30,
            bottom: -30,
            child: Icon(tab.icon,
                size: 220, color: Colors.white.withValues(alpha: 0.08)),
          ),
          Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(tab.icon, color: Colors.white, size: 34),
                const Spacer(),
                for (final t in tab.tags)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded,
                            size: 16, color: Colors.white),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(t,
                              overflow: TextOverflow.ellipsis,
                              style: AppFonts.sans(
                                  color: Colors.white, fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    return SectionShell(
      background: HomeColors.mist,
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Designed for every host',
            lead: 'From one property ',
            accent: 'to one thousand',
          ),
          const SizedBox(height: 36),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _tabs.length; i++)
                ChoiceChip(
                  selected: i == _index,
                  onSelected: (_) => setState(() => _index = i),
                  showCheckmark: false,
                  avatar: Icon(
                    _tabs[i].icon,
                    size: 17,
                    color: i == _index ? Colors.white : AppTheme.forest,
                  ),
                  label: Text(_tabs[i].soon
                      ? '${_tabs[i].label} · soon'
                      : _tabs[i].label),
                  labelStyle: AppFonts.sans(
                    fontWeight: FontWeight.w600,
                    color: i == _index ? Colors.white : AppTheme.ink,
                  ),
                  selectedColor: AppTheme.forest,
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: HomeColors.line),
                  shape: const StadiumBorder(),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                ),
            ],
          ),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: SurfaceCard(
              key: ValueKey(_index),
              padding: const EdgeInsets.all(30),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 6, child: detail),
                        const SizedBox(width: 40),
                        Expanded(flex: 5, child: visual),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [detail, const SizedBox(height: 24), visual],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 6. Reach ─────────────────────────────────────────────────────────────────

class ReachSection extends StatelessWidget {
  const ReachSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);
    const copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionIntro(
          centered: false,
          eyebrow: 'Reach more guests',
          lead: 'Listed on one site? ',
          accent: 'You are missing travellers.',
          subtitle:
              'Guests search across many booking sites, not just one. Bleiben lets you list '
              'everywhere they look without adding a single extra task to your day.',
        ),
        SizedBox(height: 20),
        BulletLine(
            'Connect your favourite channels, your website and direct bookings.'),
        BulletLine('Availability syncs across all of them automatically.'),
        BulletLine('Fill more nights without more admin.'),
      ],
    );

    Widget bar(String label, String sub, double value, Color color) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: _title(size: 16))),
              Text(
                '${(value * 100).round()}%',
                style: AppFonts.display(
                    fontSize: 26, fontWeight: FontWeight.w600, color: color),
              ),
            ],
          ),
          Text(sub, style: _body(size: 13.5)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 14,
              color: color,
              backgroundColor: HomeColors.mist,
            ),
          ),
        ],
      );
    }

    final card = SurfaceCard(
      padding: const EdgeInsets.all(30),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Occupancy example', style: _body(size: 13.5)),
          const SizedBox(height: 18),
          bar('One booking channel', 'Single listing, single audience', 0.40,
              HomeColors.muted),
          const SizedBox(height: 26),
          bar('Several channels with Bleiben', 'Same home, many more searchers',
              0.65, AppTheme.forest),
          const SizedBox(height: 22),
          Text(
            'Illustrative figures. Actual occupancy depends on location, season and pricing.',
            style: _body(size: 12.5),
          ),
        ],
      ),
    );

    return SectionShell(
      child: wide
          ? Row(
              children: [
                const Expanded(child: copy),
                const SizedBox(width: 56),
                Expanded(child: card),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [copy, const SizedBox(height: 32), card],
            ),
    );
  }
}

// ── 7. Plans by size ─────────────────────────────────────────────────────────

class PlansSection extends StatelessWidget {
  const PlansSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionShell(
      background: HomeColors.mist,
      child: Column(
        children: [
          SectionIntro(
            eyebrow: 'Grows with you',
            lead: 'Start with one home. ',
            accent: 'Scale to a portfolio.',
            subtitle:
                'Everything you need for your first homestay, with more powerful tools ready '
                'the day your business grows.',
          ),
          SizedBox(height: 44),
          ResponsiveGrid(
            minItemWidth: 380,
            maxColumns: 2,
            spacing: 24,
            children: [
              _PlanCard(
                range: '1–5 properties',
                name: 'Independent hosts',
                description:
                    'Run your homestay professionally, build your brand and keep more of what you earn.',
                features: [
                  'Unified calendar & channel sync',
                  'Direct bookings with branded invoices',
                  'Expense tracking & monthly reports',
                ],
                stats: [('₹1.2L', 'Revenue this month'), ('71%', 'Occupancy')],
                activity: [
                  'All channels in sync',
                  '6 direct bookings this week',
                  'Invoice sent to guest',
                ],
              ),
              _PlanCard(
                range: '6+ properties',
                name: 'Property managers',
                highlighted: true,
                description:
                    'Automation and portfolio tools that let your team grow without growing the chaos.',
                features: [
                  'Room-level & whole-home listings from one property',
                  'Bulk pricing across the portfolio',
                  'Portfolio analytics & profit tracking',
                ],
                stats: [('₹7.4L', 'Portfolio revenue'), ('14', 'Properties')],
                activity: [
                  'Bulk price update applied to 14 homes',
                  '3 co-hosts active today',
                  'Alert: one property below target margin',
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.range,
    required this.name,
    required this.description,
    required this.features,
    required this.stats,
    required this.activity,
    this.highlighted = false,
  });

  final String range;
  final String name;
  final String description;
  final List<String> features;
  final List<(String, String)> stats;
  final List<String> activity;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(28),
      borderColor:
          highlighted ? AppTheme.clay.withValues(alpha: 0.5) : HomeColors.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Tag(range),
              if (highlighted)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.forest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '★ OUR SPECIALITY',
                    style: AppFonts.sans(
                      fontSize: 11.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(name, style: _title(size: 24)),
          const SizedBox(height: 8),
          Text(description, style: _body()),
          const SizedBox(height: 14),
          for (final f in features) BulletLine(f),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: HomeColors.mist,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    for (final (value, label) in stats)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              value,
                              style: AppFonts.display(
                                fontSize: 24,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.forest,
                              ),
                            ),
                            Text(label, style: _body(size: 12.5)),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                for (final a in activity)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      children: [
                        Icon(
                          a.startsWith('Alert')
                              ? Icons.warning_amber_rounded
                              : Icons.check_circle_rounded,
                          size: 16,
                          color: a.startsWith('Alert')
                              ? AppTheme.clay
                              : HomeColors.success,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(a,
                                style: _body(size: 13.5, color: AppTheme.ink))),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 8. Pricing calculator ────────────────────────────────────────────────────

class PricingSection extends StatefulWidget {
  const PricingSection(
      {super.key, required this.onStart, required this.onTalk});

  final VoidCallback onStart;
  final VoidCallback onTalk;

  @override
  State<PricingSection> createState() => _PricingSectionState();
}

class _PricingSectionState extends State<PricingSection> {
  // Placeholder list prices in INR per month; replace with real plan pricing.
  static const int _perListingMonthly = 499;
  static const int _websiteMonthly = 299;
  static const _presets = [1, 10, 20, 30, 40, 50];
  static const int _maxListings = 50;

  bool _annual = true;
  int _listings = 1;
  bool _website = false;

  final _money =
      NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  int get _monthlyTotal {
    final base =
        _listings * _perListingMonthly + (_website ? _websiteMonthly : 0);
    return _annual ? (base * (1 - currentAnnualDiscount)).round() : base;
  }

  void _setListings(int value) =>
      setState(() => _listings = value.clamp(1, _maxListings));

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);

    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Billing', style: _title(size: 15)),
        const SizedBox(height: 10),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
                value: true,
                label: Text(
                    'Annual · save ${(currentAnnualDiscount * 100).round()}%')),
            const ButtonSegment(value: false, label: Text('Monthly')),
          ],
          selected: {_annual},
          onSelectionChanged: (s) => setState(() => _annual = s.first),
        ),
        const SizedBox(height: 26),
        Text('How many listings?', style: _title(size: 15)),
        const SizedBox(height: 10),
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Fewer listings',
              onPressed:
                  _listings > 1 ? () => _setListings(_listings - 1) : null,
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 72,
              child: Text(
                _listings == _maxListings ? '$_maxListings+' : '$_listings',
                textAlign: TextAlign.center,
                style: AppFonts.display(
                    fontSize: 30, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton.outlined(
              tooltip: 'More listings',
              onPressed: _listings < _maxListings
                  ? () => _setListings(_listings + 1)
                  : null,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in _presets)
              ChoiceChip(
                label: Text(p == _maxListings ? '$p+' : '$p'),
                selected: _listings == p,
                onSelected: (_) => _setListings(p),
                showCheckmark: false,
                selectedColor: AppTheme.forest,
                labelStyle: AppFonts.sans(
                  fontWeight: FontWeight.w600,
                  color: _listings == p ? Colors.white : AppTheme.ink,
                ),
              ),
          ],
        ),
        Slider(
          value: _listings.toDouble(),
          min: 1,
          max: _maxListings.toDouble(),
          divisions: _maxListings - 1,
          activeColor: AppTheme.forest,
          label: '$_listings',
          onChanged: (v) => _setListings(v.round()),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _website,
          activeTrackColor: AppTheme.forest,
          onChanged: (v) => setState(() => _website = v),
          title: Text('Add a booking website', style: _title(size: 15)),
          subtitle: Text('Take commission-free bookings on your own site.',
              style: _body(size: 13.5)),
        ),
      ],
    );

    final total = _annual ? _monthlyTotal * 12 : _monthlyTotal;
    final summary = Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: HomeColors.night,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You pay', style: _body(color: Colors.white70)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _money.format(total),
                    style: AppFonts.display(
                      fontSize: 46,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10, left: 6),
                child: Text(_annual ? '/year' : '/month',
                    style: _body(color: Colors.white70)),
              ),
            ],
          ),
          Text(
            '$_listings listing${_listings == 1 ? '' : 's'}'
            '${_website ? ' + website' : ''}'
            '${_annual ? ' · ${_money.format(_monthlyTotal)}/month billed yearly' : ''}',
            style: _body(size: 14, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              label: 'Start free trial',
              background: AppTheme.clay,
              onPressed: widget.onStart,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: PillButton(
              label: 'Book a demo',
              filled: false,
              background: Colors.white,
              onPressed: widget.onTalk,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No card needed. Cancel an annual plan anytime and we refund the unused months.',
            style: _body(size: 12.5, color: Colors.white60),
          ),
        ],
      ),
    );

    return SectionShell(
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Transparent pricing',
            lead: 'Simple pricing. ',
            accent: 'No hidden commission.',
            subtitle: 'Pay per listing and scale as you grow.',
          ),
          const SizedBox(height: 40),
          SurfaceCard(
            padding: const EdgeInsets.all(28),
            child: wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: controls),
                      const SizedBox(width: 36),
                      Expanded(flex: 5, child: summary),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [controls, const SizedBox(height: 24), summary],
                  ),
          ),
        ],
      ),
    );
  }
}

// ── 9. Support ───────────────────────────────────────────────────────────────

class SupportSection extends StatelessWidget {
  const SupportSection({super.key, required this.onTalk});

  final VoidCallback onTalk;

  static const _items = [
    (
      'Guided onboarding',
      'A real person helps you connect channels, import listings and set prices in your first week.',
    ),
    (
      'Move from your old tools',
      'We migrate your existing listings, rates and upcoming bookings so nothing gets lost.',
    ),
    (
      'Host handbook',
      'Practical guides, templates and local regulation checklists to help you host with confidence.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);

    final accordion = SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: HomeColors.line),
            ExpansionTile(
              initiallyExpanded: i == 0,
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(_items[i].$1, style: _title(size: 17)),
              children: [Text(_items[i].$2, style: _body())],
            ),
          ],
        ],
      ),
    );

    const stats = ResponsiveGrid(
      minItemWidth: 160,
      maxColumns: 2,
      spacing: 14,
      children: [
        _StatTile(
            Icons.person_pin_outlined, '1-on-1', 'onboarding for every host'),
        _StatTile(
            Icons.support_agent_rounded, '7 days', 'a week human support'),
        _StatTile(Icons.drive_file_move_outline, 'Free', 'listing migration'),
        _StatTile(Icons.school_outlined, 'Live', 'training sessions'),
      ],
    );

    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionIntro(
          centered: false,
          eyebrow: 'The Bleiben promise',
          lead: 'Support you can ',
          accent: 'always count on',
        ),
        const SizedBox(height: 28),
        accordion,
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        stats,
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: PillButton(
            label: 'Book a demo with our team',
            icon: Icons.arrow_forward_rounded,
            onPressed: onTalk,
          ),
        ),
      ],
    );

    return SectionShell(
      background: HomeColors.mist,
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(flex: 6, child: left),
                const SizedBox(width: 48),
                Expanded(flex: 5, child: right),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [left, const SizedBox(height: 28), right],
            ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile(this.icon, this.value, this.label);

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      elevated: false,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon, color: AppTheme.clay, size: 38),
          const SizedBox(height: 14),
          Text(
            value,
            style: AppFonts.display(
                fontSize: 26,
                fontWeight: FontWeight.w600,
                color: AppTheme.forest),
          ),
          Text(label, style: _body(size: 13.5)),
        ],
      ),
    );
  }
}

// ── 10. Reviews ──────────────────────────────────────────────────────────────

class ReviewsSection extends StatefulWidget {
  const ReviewsSection({super.key});

  @override
  State<ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<ReviewsSection> {
  // TODO(launch): placeholder reviews for layout only. Replace with real,
  // attributable customer quotes before this page goes live.
  static const _reviews = [
    (
      'Meera N.',
      'Homestay host · Coorg',
      'I used to update three calendars after every booking. Now I change a price once and go back to my guests.'
    ),
    (
      'Arjun & Sana',
      'Villa owners · Goa',
      'Onboarding took one call. Our listings, rates and future bookings were moved over for us.'
    ),
    (
      'Kavya R.',
      'Property manager · Bengaluru',
      'Bulk pricing before long weekends used to take an evening. It now takes about two minutes.'
    ),
    (
      'Tenzin D.',
      'Guesthouse host · Dharamshala',
      'Walk-ins and phone bookings finally live on the same calendar as Airbnb. No more surprises.'
    ),
    (
      'Rohan P.',
      'Holiday homes · Lonavala',
      'Seeing profit per property, not just revenue, changed which homes we decided to keep.'
    ),
  ];

  static const double _cardStride = 340 + 18;
  final _scroll = ScrollController();
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final page =
          (_scroll.offset / _cardStride).round().clamp(0, _reviews.length - 1);
      if (page != _current) setState(() => _current = page);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(int index) {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      (index * _cardStride).clamp(0.0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
    );
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final target = (_scroll.offset + direction * 360)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            runSpacing: 20,
            children: [
              const SectionIntro(
                centered: false,
                eyebrow: 'Hosts on Bleiben',
                lead: 'Why hosts ',
                accent: 'stay with us',
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.outlined(
                    tooltip: 'Previous reviews',
                    onPressed: () => _page(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Next reviews',
                    onPressed: () => _page(1),
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 250,
            child: ListView.separated(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              itemCount: _reviews.length,
              separatorBuilder: (_, __) => const SizedBox(width: 18),
              itemBuilder: (context, i) {
                final (name, role, quote) = _reviews[i];
                return SizedBox(
                  width: 340,
                  child: SurfaceCard(
                    elevated: false,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: List.generate(
                            5,
                            (_) => const Icon(Icons.star_rounded,
                                size: 18, color: AppTheme.clay),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: Text(
                            '“$quote”',
                            overflow: TextOverflow.fade,
                            style: _body(size: 15, color: AppTheme.ink),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor:
                                  AppTheme.forest.withValues(alpha: 0.1),
                              child: Text(
                                name[0],
                                style: AppFonts.sans(
                                  color: AppTheme.forest,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: _title(size: 14.5)),
                                  Text(role, style: _body(size: 12.5)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < _reviews.length; i++)
                Semantics(
                  button: true,
                  label: 'Review ${i + 1}',
                  child: GestureDetector(
                    onTap: () => _jumpTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: i == _current ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color:
                            i == _current ? AppTheme.forest : HomeColors.line,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── 11. Final CTA ────────────────────────────────────────────────────────────

class FinalCtaSection extends StatelessWidget {
  const FinalCtaSection(
      {super.key, required this.onStart, required this.onTalk});

  final VoidCallback onStart;
  final VoidCallback onTalk;

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      vertical: 40,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: HomeLayout.isMedium(context) ? 56 : 24,
          vertical: HomeLayout.isMedium(context) ? 64 : 40,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.forest, Color(0xFF173A2C)],
          ),
        ),
        child: Column(
          children: [
            const AccentHeadline(
              lead: 'One platform. Every booking. ',
              accent: 'More profit.',
              align: TextAlign.center,
              dark: true,
              accentColor: Color(0xFFF2B28E),
            ),
            const SizedBox(height: 16),
            Text(
              'Set up in an afternoon. Free for 14 days, no card needed.',
              textAlign: TextAlign.center,
              style: _body(size: 17, color: Colors.white70),
            ),
            const SizedBox(height: 30),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                PillButton(
                  label: 'Start free trial',
                  icon: Icons.arrow_forward_rounded,
                  background: Colors.white,
                  foreground: AppTheme.forest,
                  onPressed: onStart,
                ),
                PillButton(
                  label: 'Talk to our team',
                  filled: false,
                  background: Colors.white,
                  onPressed: onTalk,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo mark + wordmark.
class BleibenWordmark extends StatelessWidget {
  const BleibenWordmark({super.key, this.dark = false});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    // Smaller on phones so the nav buttons keep their room.
    final compact = MediaQuery.sizeOf(context).width < 420;
    final size = compact ? 20.0 : 25.0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: compact ? 30 : 36,
          height: compact ? 30 : 36,
          decoration: BoxDecoration(
            color: dark ? Colors.white : AppTheme.forest,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(
            Icons.home_outlined,
            size: compact ? 18 : 21,
            color: dark ? AppTheme.forest : const Color(0xFFFFFEF7),
          ),
        ),
        SizedBox(width: compact ? 8 : 10),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: 'bleiben',
              style: AppFonts.display(
                fontSize: size,
                fontWeight: FontWeight.w700,
                letterSpacing: -size * 0.056,
                color: dark ? Colors.white : AppTheme.ink,
              ),
            ),
            TextSpan(
              text: '.',
              style: AppFonts.display(
                fontSize: size,
                fontWeight: FontWeight.w700,
                color: AppTheme.terra,
              ),
            ),
          ]),
          semanticsLabel: 'Bleiben',
        ),
      ],
    );
  }
}
