import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'home_sections.dart';
import 'home_widgets.dart';

/// Public marketing homepage shown to signed-out visitors.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.onLogin, required this.onSignUp});

  /// Opens the sign-in flow.
  final VoidCallback onLogin;

  /// Opens the sign-up flow (used by every "Start free trial" button).
  final VoidCallback onSignUp;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  final _sectionKeys = {
    'Features': GlobalKey(),
    'Calendar': GlobalKey(),
    'Pricing': GlobalKey(),
    'Reviews': GlobalKey(),
  };

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollTo(String section) {
    final context = _sectionKeys[section]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  void _onFooterLink(String label) {
    const map = {
      'Calendar': 'Calendar',
      'Channel manager': 'Features',
      'Booking website': 'Features',
      'Pricing': 'Pricing',
    };
    final target = map[label];
    if (target != null) {
      _scrollTo(target);
    } else {
      _comingSoon(label);
    }
  }

  void _comingSoon(String what) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('$what is coming soon.')));
  }

  void _talkToTeam() => _comingSoon('Booking a demo');

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      endDrawer: wide
          ? null
          : _MobileMenu(
              sections: _sectionKeys.keys.toList(),
              onSection: (s) {
                Navigator.pop(context);
                _scrollTo(s);
              },
              onLogin: () {
                Navigator.pop(context);
                widget.onLogin();
              },
              onSignUp: () {
                Navigator.pop(context);
                widget.onSignUp();
              },
            ),
      body: Column(
        children: [
          _NavBar(
            wide: wide,
            sections: _sectionKeys.keys.toList(),
            onSection: _scrollTo,
            onLogin: widget.onLogin,
            onSignUp: widget.onSignUp,
            onMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
            onLogo: () => _scroll.animateTo(
              0,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeInOutCubic,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                children: [
                  HeroSection(onStart: widget.onSignUp, onTalk: _talkToTeam),
                  FeatureTilesSection(key: _sectionKeys['Features']),
                  CalendarSection(key: _sectionKeys['Calendar']),
                  const BeforeAfterSection(),
                  const FeatureTabsSection(),
                  const ReachSection(),
                  const PlansSection(),
                  PricingSection(
                    key: _sectionKeys['Pricing'],
                    onStart: widget.onSignUp,
                    onTalk: _talkToTeam,
                  ),
                  SupportSection(onTalk: _talkToTeam),
                  ReviewsSection(key: _sectionKeys['Reviews']),
                  FinalCtaSection(
                      onStart: widget.onSignUp, onTalk: _talkToTeam),
                  HomeFooter(onNavigate: _onFooterLink),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.wide,
    required this.sections,
    required this.onSection,
    required this.onLogin,
    required this.onSignUp,
    required this.onMenu,
    required this.onLogo,
  });

  final bool wide;
  final List<String> sections;
  final ValueChanged<String> onSection;
  final VoidCallback onLogin;
  final VoidCallback onSignUp;
  final VoidCallback onMenu;
  final VoidCallback onLogo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.97),
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 72,
          padding: EdgeInsets.symmetric(horizontal: HomeLayout.gutter(context)),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: HomeColors.line)),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: HomeLayout.maxWidth),
              child: Row(
                children: [
                  InkWell(
                    onTap: onLogo,
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: BleibenWordmark(),
                    ),
                  ),
                  const Spacer(),
                  if (wide) ...[
                    for (final s in sections)
                      Flexible(
                        child: TextButton(
                          onPressed: () => onSection(s),
                          style: TextButton.styleFrom(
                            foregroundColor: AppTheme.ink,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            textStyle: GoogleFonts.outfit(
                                fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                          child: Text(s, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: PillButton(
                          label: 'Log in',
                          filled: false,
                          dense: true,
                          onPressed: onLogin),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: PillButton(
                          label: 'Start free trial',
                          dense: true,
                          onPressed: onSignUp),
                    ),
                  ] else ...[
                    Flexible(
                      child: PillButton(
                          label: 'Log in',
                          filled: false,
                          dense: true,
                          onPressed: onLogin),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Menu',
                      onPressed: onMenu,
                      icon: const Icon(Icons.menu_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMenu extends StatelessWidget {
  const _MobileMenu({
    required this.sections,
    required this.onSection,
    required this.onLogin,
    required this.onSignUp,
  });

  final List<String> sections;
  final ValueChanged<String> onSection;
  final VoidCallback onLogin;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
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
              const SizedBox(height: 16),
              for (final s in sections)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s,
                      style: GoogleFonts.outfit(
                          fontSize: 17, fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onSection(s),
                ),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline_rounded),
                title: Text('Log in or create account',
                    style: GoogleFonts.outfit(fontSize: 15)),
                onTap: onLogin,
              ),
              const Spacer(),
              PillButton(label: 'Start free trial', onPressed: onSignUp),
            ],
          ),
        ),
      ),
    );
  }
}
