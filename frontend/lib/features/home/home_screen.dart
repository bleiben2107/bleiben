import 'package:flutter/material.dart';

import 'home_content.dart';
import 'home_more_sections.dart';
import 'home_nav.dart';
import 'home_overlays.dart';
import 'home_sections.dart';
import 'home_widgets.dart';

/// Marketing homepage. Signed-out visitors and signed-in users both land here
/// (as on homyhuts): signing in only swaps "Log in" for the account avatar.
/// Signed in, the account menu opens Account settings or logs out; its other
/// entries are placeholders for now.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onLogin,
    required this.onSignUp,
    this.signedIn = false,
    this.displayName,
    this.onAccountSettings,
    this.onLogout,
  });

  /// Opens the sign-in flow.
  final VoidCallback onLogin;

  /// Opens the sign-up flow (used by every "Start free trial" button).
  final VoidCallback onSignUp;

  final bool signedIn;
  final String? displayName;

  /// Signed in only: opens Account settings.
  final VoidCallback? onAccountSettings;
  final VoidCallback? onLogout;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  final _anchors = {for (final a in HomeAnchor.values) a: GlobalKey()};

  bool _offerDismissed = false;
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final show = _scroll.offset > 900;
      if (show != _showBackToTop) setState(() => _showBackToTop = show);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── Navigation helpers ─────────────────────────────────────────────────────

  void _scrollTo(HomeAnchor anchor) {
    final context = _anchors[anchor]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOutCubic,
    );
  }

  void _toTop() => _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );

  void _notice(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _bookDemo() async {
    final request = await showDemoDialog(context);
    if (request != null && mounted) {
      _notice(
          'Demo requested for ${request.slot} IST. We will be in touch soon.');
    }
  }

  /// Avatar letter for a signed-in host (homyhuts shows the first initial).
  String? get _initial {
    final name = widget.displayName?.trim() ?? '';
    return widget.signedIn && name.isNotEmpty ? name[0].toUpperCase() : null;
  }

  /// Every "Start free trial" / "List your property" button.
  /// Signed in, property setup isn't built yet, so it only says so.
  void _start() => widget.signedIn
      ? _notice('Property listing is coming soon.')
      : widget.onSignUp();

  Future<void> _openAccount() async {
    final action = await showAccountSheet(context,
        signedIn: widget.signedIn, displayName: widget.displayName);
    if (action == null || !mounted) return;
    if (widget.signedIn) {
      // Only these two work for now; the rest of the menu is a placeholder.
      switch (action) {
        case AccountAction.accountSettings:
          widget.onAccountSettings?.call();
        case AccountAction.logout:
          widget.onLogout?.call();
        default:
          break;
      }
      return;
    }
    switch (action) {
      case AccountAction.signIn:
        widget.onLogin();
      case AccountAction.listProperty:
        widget.onSignUp();
      case AccountAction.contact:
        _bookDemo();
      case AccountAction.help:
        _notice('The help centre is coming soon.');
      case AccountAction.about:
        _notice('About us is coming soon.');
      case AccountAction.bookStay:
        _notice('Booking a stay is coming soon.');
      case AccountAction.trips ||
            AccountAction.accountSettings ||
            AccountAction.logout:
        break;
    }
  }

  void _handleLink(HomeLink link) {
    switch (link) {
      case AnchorLink(:final anchor):
        _scrollTo(anchor);
      case DemoLink():
        _bookDemo();
      case SignUpLink():
        _start();
      case PendingLink(:final label):
        _notice('$label is coming soon.');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final offer = kLaunchOffer;
    final showOffer = offer.isLive && !_offerDismissed;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      endDrawer: HomeMobileMenu(
        onLink: _handleLink,
        onSignUp: _start,
        onAccount: _openAccount,
        signedIn: widget.signedIn,
      ),
      floatingActionButton: FloatingActions(
        showBackToTop: _showBackToTop,
        onDemo: _bookDemo,
        onBackToTop: _toTop,
        compact: !HomeLayout.isMedium(context),
      ),
      body: Column(
        children: [
          if (showOffer)
            OfferBar(
              offer: offer,
              onClaim: () => _scrollTo(HomeAnchor.pricing),
              onDismiss: () => setState(() => _offerDismissed = true),
            ),
          SafeArea(
            top: !showOffer,
            bottom: false,
            child: HomeNavBar(
              onLink: _handleLink,
              onLogin: widget.onLogin,
              onSignUp: _start,
              onAccount: _openAccount,
              initial: _initial,
              onMenu: () => _scaffoldKey.currentState?.openEndDrawer(),
              onLogo: _toTop,
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              child: Column(
                children: [
                  HeroSection(
                    onStart: _start,
                    onTalk: _bookDemo,
                    onSeePricing: () => _scrollTo(HomeAnchor.pricing),
                    onAllChannels: () => showChannelsDialog(context),
                  ),
                  FeatureTilesSection(key: _anchors[HomeAnchor.features]),
                  CalendarSection(
                      key: _anchors[HomeAnchor.calendar], onExplore: _bookDemo),
                  const BeforeAfterSection(),
                  FeatureTabsSection(
                    onLearnMore: (label) =>
                        _notice('A detailed $label page is coming soon.'),
                  ),
                  EverythingSection(onStart: _start),
                  const ReachSection(),
                  const PlansSection(),
                  PricingSection(
                    key: _anchors[HomeAnchor.pricing],
                    onStart: _start,
                    onTalk: _bookDemo,
                  ),
                  SupportSection(onTalk: _bookDemo),
                  WhyUsSection(onDemo: _bookDemo),
                  ReviewsSection(key: _anchors[HomeAnchor.reviews]),
                  VideoStoriesSection(
                      onPlay: (title) =>
                          _notice('“$title” — video coming soon.')),
                  FaqSection(key: _anchors[HomeAnchor.faq], onDemo: _bookDemo),
                  FinalCtaSection(onStart: _start, onTalk: _bookDemo),
                  GuidesSection(
                    key: _anchors[HomeAnchor.guides],
                    onOpen: (title) => _notice('“$title” is coming soon.'),
                  ),
                  HomeFooter(onLink: _handleLink),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
