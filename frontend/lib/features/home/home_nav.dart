import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'home_content.dart';
import 'home_sections.dart' show BleibenWordmark;
import 'home_widgets.dart';

TextStyle _navText() => GoogleFonts.outfit(
    fontSize: 15, fontWeight: FontWeight.w500, color: AppTheme.ink);

/// Sticky top navigation with Product / Solutions / Resources menus.
class HomeNavBar extends StatefulWidget {
  const HomeNavBar({
    super.key,
    required this.onLink,
    required this.onLogin,
    required this.onSignUp,
    required this.onAccount,
    required this.onMenu,
    required this.onLogo,
  });

  final ValueChanged<HomeLink> onLink;
  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  /// Opens the account sheet (sign in, book a stay, help…).
  final VoidCallback onAccount;
  final VoidCallback onMenu;
  final VoidCallback onLogo;

  @override
  State<HomeNavBar> createState() => _HomeNavBarState();
}

class _HomeNavBarState extends State<HomeNavBar> {
  final _product = MenuController();
  final _solutions = MenuController();
  final _resources = MenuController();

  void _go(MenuController menu, HomeLink link) {
    menu.close();
    widget.onLink(link);
  }

  Widget _dropdown(String label, MenuController controller, Widget panel) {
    return MenuAnchor(
      controller: controller,
      alignmentOffset: const Offset(0, 8),
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Colors.white),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.white),
        elevation: const WidgetStatePropertyAll(12),
        shadowColor:
            WidgetStatePropertyAll(AppTheme.ink.withValues(alpha: 0.25)),
        padding: const WidgetStatePropertyAll(EdgeInsets.zero),
        shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
      ),
      menuChildren: [panel],
      builder: (context, menu, _) => TextButton(
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.ink,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: _navText()),
            Icon(
                menu.isOpen
                    ? Icons.expand_less_rounded
                    : Icons.expand_more_rounded,
                size: 18),
          ],
        ),
      ),
    );
  }

  Widget _productPanel() {
    return SizedBox(
      width: 940,
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final column in kProductMenu)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _MenuHeading(column.heading),
                          for (final e in column.entries)
                            _MenuTile(e, onTap: () => _go(_product, e.link)),
                        ],
                      ),
                    ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 230,
                    child: _PromoCard(
                      eyebrow: 'See it live',
                      title: 'Every channel, every booking, one app.',
                      body:
                          'A short walkthrough with our team, tailored to your properties.',
                      action: 'Book a demo →',
                      onTap: () => _go(_product, const DemoLink()),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 28, color: HomeColors.line),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Works with Airbnb, Booking.com, Vrbo, Agoda, MakeMyTrip and more.',
                    style: GoogleFonts.outfit(
                        fontSize: 13, color: HomeColors.muted),
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      _go(_product, const AnchorLink(HomeAnchor.features)),
                  child: Text('See all features →',
                      style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600, color: AppTheme.forest)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _solutionsPanel() {
    return SizedBox(
      width: 360,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in kSolutionsMenu)
              _MenuTile(e, onTap: () => _go(_solutions, e.link)),
          ],
        ),
      ),
    );
  }

  Widget _resourcesPanel() {
    return SizedBox(
      width: 560,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 240,
                child: _PromoCard(
                  eyebrow: 'Featured',
                  title: kResourcesFeatured.title,
                  body: kResourcesFeatured.subtitle,
                  action: 'Explore the handbook →',
                  onTap: () => _go(_resources, kResourcesFeatured.link),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in kResourcesMenu)
                      _MenuTile(e, onTap: () => _go(_resources, e.link)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      child: Container(
        height: 72,
        padding: EdgeInsets.symmetric(horizontal: HomeLayout.gutter(context)),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: HomeColors.line))),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: HomeLayout.maxWidth),
            child: Row(
              children: [
                InkWell(
                  onTap: widget.onLogo,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: BleibenWordmark(),
                  ),
                ),
                const Spacer(),
                if (wide) ...[
                  _dropdown('Product', _product, _productPanel()),
                  _dropdown('Solutions', _solutions, _solutionsPanel()),
                  _dropdown('Resources', _resources, _resourcesPanel()),
                  for (final (label, anchor) in const [
                    ('Pricing', HomeAnchor.pricing),
                    ('Reviews', HomeAnchor.reviews),
                  ])
                    Flexible(
                      child: TextButton(
                        onPressed: () => widget.onLink(AnchorLink(anchor)),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.ink,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                        ),
                        child: Text(label,
                            style: _navText(), overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  const SizedBox(width: 16),
                  Flexible(
                    child: PillButton(
                        label: 'Start free trial',
                        dense: true,
                        onPressed: widget.onSignUp),
                  ),
                  const SizedBox(width: 10),
                  AccountMenuButton(onPressed: widget.onAccount),
                ] else ...[
                  Flexible(
                    child: PillButton(
                        label: 'Log in',
                        filled: false,
                        dense: true,
                        onPressed: widget.onLogin),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Menu',
                    onPressed: widget.onMenu,
                    icon: const Icon(Icons.menu_rounded),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: Text(
        text.toUpperCase(),
        style: GoogleFonts.outfit(
          fontSize: 11.5,
          letterSpacing: 1.3,
          fontWeight: FontWeight.w600,
          color: HomeColors.muted,
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile(this.entry, {required this.onTap});

  final MenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconBadge(entry.icon, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.title,
                          style: GoogleFonts.outfit(
                              fontSize: 14.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (entry.badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppTheme.clay.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            entry.badge!,
                            style: GoogleFonts.outfit(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.clay),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    entry.subtitle,
                    style: GoogleFonts.outfit(
                        fontSize: 12.5, color: HomeColors.muted, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.action,
    required this.onTap,
  });

  final String eyebrow;
  final String title;
  final String body;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: HomeColors.night,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: GoogleFonts.outfit(
                  fontSize: 11,
                  letterSpacing: 1.3,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFF2B28E),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title,
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.25),
              ),
              const SizedBox(height: 8),
              Text(body,
                  style: GoogleFonts.outfit(
                      fontSize: 13, color: Colors.white70, height: 1.4)),
              const SizedBox(height: 16),
              Text(action,
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Phone navigation drawer with the same menus as expandable groups.
class HomeMobileMenu extends StatelessWidget {
  const HomeMobileMenu({
    super.key,
    required this.onLink,
    required this.onSignUp,
    required this.onAccount,
  });

  final ValueChanged<HomeLink> onLink;
  final VoidCallback onSignUp;

  /// Opens the account sheet.
  final VoidCallback onAccount;

  @override
  Widget build(BuildContext context) {
    void go(HomeLink link) {
      Navigator.pop(context);
      onLink(link);
    }

    Widget group(String title, List<MenuEntry> entries) {
      return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(title,
            style:
                GoogleFonts.outfit(fontSize: 17, fontWeight: FontWeight.w500)),
        children: [
          for (final e in entries) _MenuTile(e, onTap: () => go(e.link))
        ],
      );
    }

    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const BleibenWordmark(),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Close menu',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    group('Product',
                        [for (final c in kProductMenu) ...c.entries]),
                    group('Solutions', kSolutionsMenu),
                    group('Resources', [kResourcesFeatured, ...kResourcesMenu]),
                    for (final (label, anchor) in const [
                      ('Pricing', HomeAnchor.pricing),
                      ('Reviews', HomeAnchor.reviews),
                      ('FAQ', HomeAnchor.faq),
                    ])
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(label,
                            style: GoogleFonts.outfit(
                                fontSize: 17, fontWeight: FontWeight.w500)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => go(AnchorLink(anchor)),
                      ),
                    const Divider(height: 28),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline_rounded),
                      title: Text('Log in or account',
                          style: GoogleFonts.outfit(fontSize: 15)),
                      onTap: () {
                        Navigator.pop(context);
                        onAccount();
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.video_call_outlined),
                      title: Text('Book a demo',
                          style: GoogleFonts.outfit(fontSize: 15)),
                      onTap: () => go(const DemoLink()),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              PillButton(
                label: 'Start free trial',
                onPressed: () {
                  Navigator.pop(context);
                  onSignUp();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Outlined pill with an avatar and a menu icon that opens the account sheet.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Menu and account',
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.ink,
          side: const BorderSide(color: HomeColors.line, width: 1.5),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.fromLTRB(6, 6, 12, 6),
          minimumSize: Size.zero,
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: HomeColors.mist,
              child:
                  Icon(Icons.person_rounded, size: 19, color: HomeColors.muted),
            ),
            SizedBox(width: 8),
            Icon(Icons.menu_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
