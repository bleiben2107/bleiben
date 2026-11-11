import 'package:flutter/material.dart';

/// Section anchors the nav, menus and footer can scroll to.
enum HomeAnchor { features, calendar, pricing, reviews, faq, guides }

/// Where a menu or footer link should take the visitor.
sealed class HomeLink {
  const HomeLink();
}

class AnchorLink extends HomeLink {
  const AnchorLink(this.anchor);
  final HomeAnchor anchor;
}

class DemoLink extends HomeLink {
  const DemoLink();
}

class SignUpLink extends HomeLink {
  const SignUpLink();
}

/// A page we have not built yet; shows a "coming soon" note.
class PendingLink extends HomeLink {
  const PendingLink(this.label);
  final String label;
}

// ── Launch offer ─────────────────────────────────────────────────────────────

/// Promotional offer shown in the top bar and under the hero.
/// Every offer surface hides itself once [endsAt] has passed; set it to a
/// past date to switch the offer off early.
class LaunchOffer {
  const LaunchOffer({
    required this.headline,
    required this.detail,
    required this.endsAt,
    required this.annualDiscount,
  });

  final String headline;
  final String detail;
  final DateTime endsAt;

  /// Annual-plan discount while the offer runs (0.2 = 20%).
  final double annualDiscount;

  bool get isLive => DateTime.now().isBefore(endsAt);
}

// TODO(launch): placeholder offer; confirm terms and end date with the business.
final LaunchOffer kLaunchOffer = LaunchOffer(
  headline: 'Founding-host offer',
  detail: 'up to 30% off annual plans · new hosts only',
  endsAt: DateTime(2026, 12, 31, 23, 59),
  annualDiscount: 0.3,
);

/// Standard annual discount when no offer is live.
const double kStandardAnnualDiscount = 0.2;

double get currentAnnualDiscount {
  final offer = kLaunchOffer;
  return offer.isLive ? offer.annualDiscount : kStandardAnnualDiscount;
}

// ── Navigation menus ─────────────────────────────────────────────────────────

class MenuEntry {
  const MenuEntry(this.icon, this.title, this.subtitle, this.link,
      {this.badge});

  final IconData icon;
  final String title;
  final String subtitle;
  final HomeLink link;
  final String? badge;
}

class MenuColumn {
  const MenuColumn(this.heading, this.entries);

  final String heading;
  final List<MenuEntry> entries;
}

const List<MenuColumn> kProductMenu = [
  MenuColumn('Get more bookings', [
    MenuEntry(
        Icons.hub_outlined,
        'Channel manager',
        'Sync Airbnb, Booking.com, Vrbo and more',
        AnchorLink(HomeAnchor.features)),
    MenuEntry(
        Icons.calendar_month_outlined,
        'Unified calendar',
        'Every property and booking in one view',
        AnchorLink(HomeAnchor.calendar)),
    MenuEntry(Icons.web_outlined, 'Booking website',
        'Your own site with online payments', AnchorLink(HomeAnchor.features)),
    MenuEntry(
        Icons.dashboard_customize_outlined,
        'Smart listings',
        'Sell rooms or the whole home, in sync',
        AnchorLink(HomeAnchor.features)),
  ]),
  MenuColumn('Run operations', [
    MenuEntry(Icons.phone_in_talk_outlined, 'Offline bookings',
        'Walk-in, phone and WhatsApp guests', AnchorLink(HomeAnchor.features)),
    MenuEntry(Icons.forum_outlined, 'Unified inbox',
        'Guest messages from every channel', AnchorLink(HomeAnchor.features)),
    MenuEntry(Icons.groups_2_outlined, 'Co-hosts & team',
        'Give staff the right access', AnchorLink(HomeAnchor.features)),
  ]),
  MenuColumn('Grow revenue', [
    MenuEntry(
        Icons.trending_up_rounded,
        'Bulk pricing',
        'Change rates across properties at once',
        AnchorLink(HomeAnchor.features)),
    MenuEntry(Icons.receipt_long_outlined, 'Expenses & profit',
        'True profit per property', AnchorLink(HomeAnchor.features)),
    MenuEntry(Icons.insights_outlined, 'Analytics',
        'Revenue, occupancy and trends', AnchorLink(HomeAnchor.features),
        badge: 'Soon'),
  ]),
];

const List<MenuEntry> kSolutionsMenu = [
  MenuEntry(Icons.rocket_launch_outlined, 'New to hosting',
      'Start your first homestay the right way', SignUpLink()),
  MenuEntry(Icons.person_outline_rounded, 'Independent hosts',
      '1–5 properties, run like a pro', AnchorLink(HomeAnchor.pricing)),
  MenuEntry(Icons.apartment_rounded, 'Property managers',
      '6–200 properties, built to scale', AnchorLink(HomeAnchor.pricing)),
  MenuEntry(Icons.business_center_outlined, 'Enterprise',
      'Large portfolios, custom setup and support', DemoLink()),
];

const MenuEntry kResourcesFeatured = MenuEntry(
  Icons.menu_book_outlined,
  'Host handbook',
  'Guides, templates and checklists to host smarter and grow faster.',
  AnchorLink(HomeAnchor.guides),
);

const List<MenuEntry> kResourcesMenu = [
  MenuEntry(Icons.help_outline_rounded, 'Help centre',
      'Step-by-step answers for every feature', PendingLink('The help centre')),
  MenuEntry(Icons.quiz_outlined, 'FAQ', 'Quick answers before you start',
      AnchorLink(HomeAnchor.faq)),
  MenuEntry(Icons.play_circle_outline_rounded, 'App tutorials',
      'Short videos for the Bleiben app', PendingLink('App tutorials')),
];

// ── Channels ─────────────────────────────────────────────────────────────────

// TODO(launch): align with the integrations that are actually live.
const List<String> kSupportedChannels = [
  'Airbnb',
  'Booking.com',
  'Vrbo',
  'Agoda',
  'Expedia',
  'MakeMyTrip',
  'Goibibo',
  'Trip.com',
  'Hotels.com',
  'Cleartrip',
  'EaseMyTrip',
  'Yatra',
  'Hostelworld',
  'Google Vacation Rentals',
  'Tripadvisor',
  'Despegar',
  'Traveloka',
  'Bleiben direct site',
];

// ── FAQ ──────────────────────────────────────────────────────────────────────

const List<(String, String)> kFaqs = [
  (
    'Which booking channels does Bleiben work with?',
    'Airbnb, Booking.com, Vrbo, Agoda, Expedia, MakeMyTrip, Goibibo and more, plus your own '
        'Bleiben booking website. Your onboarding specialist confirms the exact list for your region.'
  ),
  (
    'Can I manage direct and walk-in bookings too?',
    'Yes. Phone, WhatsApp, walk-in and repeat-guest bookings sit on the same calendar as your OTA '
        'bookings, and every channel is closed for those nights automatically.'
  ),
  (
    'How does Bleiben prevent double bookings?',
    'When a booking arrives on any channel, Bleiben blocks the same nights everywhere else within '
        'seconds, so the same room can never be sold twice.'
  ),
  (
    'What are smart listings?',
    'List one property as individual rooms, room combinations or the whole home. A booking on any '
        'version updates all the others, and you can switch to whole-home only for peak season.'
  ),
  (
    'Can I have my own booking website?',
    'Yes. You get a fast, mobile-friendly site under your brand with online payments and no '
        'platform commission. It stays in sync with your other channels.'
  ),
  (
    'Is Bleiben suitable for property managers?',
    'Yes. Bulk pricing, team roles, portfolio reports and smart listings are built for managers '
        'running dozens or hundreds of homes.'
  ),
  (
    'Can I track expenses and see real profit?',
    'Log rent, salaries, utilities, repairs and commission per property, and see profit — not just '
        'revenue — for each home and each month.'
  ),
  (
    'Is there a long-term contract?',
    'No. Monthly plans can be cancelled anytime. If you cancel an annual plan we refund the unused '
        'months.'
  ),
  (
    'Do I need to be on Airbnb or Booking.com to use Bleiben?',
    'No. Many hosts start with direct and offline bookings only and connect channels later.'
  ),
  (
    'How quickly can I get started?',
    'Most hosts are live the same day. We help import your listings, rates and upcoming bookings '
        'during a guided onboarding call.'
  ),
  (
    'How do I sync my Airbnb and Booking.com calendars?',
    'Connect each account once from Settings → Channels. From then on availability, prices and '
        'bookings flow both ways automatically.'
  ),
  (
    'Can my team use Bleiben without my login?',
    'Yes. Invite co-hosts, caretakers and managers with their own accounts, limited to the '
        'properties and actions you choose.'
  ),
];

// ── Guides ───────────────────────────────────────────────────────────────────

const List<(String, String, IconData)> kGuides = [
  (
    'Pricing',
    'How to price your homestay for long weekends and festivals',
    Icons.trending_up_rounded
  ),
  (
    'Channels',
    'Airbnb or Booking.com? Choosing channels for a small homestay',
    Icons.hub_outlined
  ),
  (
    'Direct bookings',
    'Turning repeat guests into commission-free direct bookings',
    Icons.storefront_outlined
  ),
  (
    'Operations',
    'A simple check-in checklist your caretaker will actually follow',
    Icons.checklist_rounded
  ),
  (
    'Compliance',
    'Registration and GST basics for homestay hosts in India',
    Icons.gavel_rounded
  ),
  (
    'Guest experience',
    'Five small touches that earn five-star reviews',
    Icons.star_outline_rounded
  ),
];

// ── Footer ───────────────────────────────────────────────────────────────────

const List<(String, List<(String, HomeLink)>)> kFooterColumns = [
  (
    'Company',
    [
      ('About us', PendingLink('About us')),
      ('Contact us', DemoLink()),
      ('Careers', PendingLink('Careers')),
      ('Terms of use', PendingLink('Terms of use')),
      ('Privacy policy', PendingLink('Privacy policy')),
      ('Cookie policy', PendingLink('Cookie policy')),
    ]
  ),
  (
    'For hosts',
    [
      ('List your property', SignUpLink()),
      ('Pricing', AnchorLink(HomeAnchor.pricing)),
      ('Unified calendar', AnchorLink(HomeAnchor.calendar)),
      ('Book a demo', DemoLink()),
    ]
  ),
  (
    'Help & resources',
    [
      ('Help centre', PendingLink('The help centre')),
      ('Host handbook', AnchorLink(HomeAnchor.guides)),
      ('FAQ', AnchorLink(HomeAnchor.faq)),
      ('App tutorials', PendingLink('App tutorials')),
    ]
  ),
];

const List<String> kPopularDestinations = [
  'Goa',
  'Kerala',
  'Manali',
  'Rishikesh',
  'Udaipur',
  'Lonavala',
  'Coorg',
  'Munnar',
  'Jaipur',
];

const List<(IconData, String)> kSocialLinks = [
  (Icons.camera_alt_outlined, 'Instagram'),
  (Icons.facebook_rounded, 'Facebook'),
  (Icons.alternate_email_rounded, 'X'),
  (Icons.smart_display_outlined, 'YouTube'),
  (Icons.work_outline_rounded, 'LinkedIn'),
];

// ── Account menu ─────────────────────────────────────────────────────────────

/// What an account-menu item does when tapped.
enum AccountAction {
  signIn,
  bookStay,
  listProperty,
  about,
  trips,
  accountSettings,
  contact,
  help,
  logout,
}

class AccountMenuItem {
  const AccountMenuItem(this.action, this.label, this.icon);

  final AccountAction action;
  final String label;
  final IconData icon;
}

/// Grouped account-menu items for the current session. The first group is
/// emphasised in the sheet. Items that need a session only appear when
/// [signedIn] is true; "Sign up / Sign in" only appears when it is false.
List<List<AccountMenuItem>> accountMenuGroups({required bool signedIn}) {
  final groups = <List<AccountMenuItem>>[
    [
      if (!signedIn)
        const AccountMenuItem(
            AccountAction.signIn, 'Sign up / Sign in', Icons.login_rounded),
    ],
    [
      const AccountMenuItem(AccountAction.bookStay, 'Book your stay',
          Icons.travel_explore_rounded),
      const AccountMenuItem(AccountAction.listProperty, 'List your property',
          Icons.add_home_outlined),
      const AccountMenuItem(
          AccountAction.about, 'About us', Icons.info_outline_rounded),
      if (signedIn)
        const AccountMenuItem(
            AccountAction.trips, 'Trips', Icons.luggage_outlined),
      if (signedIn)
        const AccountMenuItem(AccountAction.accountSettings, 'Account settings',
            Icons.manage_accounts_outlined),
      const AccountMenuItem(
          AccountAction.contact, 'Contact us', Icons.mail_outline_rounded),
      const AccountMenuItem(
          AccountAction.help, 'Help centre', Icons.help_outline_rounded),
    ],
    [
      if (signedIn)
        const AccountMenuItem(
            AccountAction.logout, 'Log out', Icons.logout_rounded),
    ],
  ];
  return [
    for (final g in groups)
      if (g.isNotEmpty) g
  ];
}
