import 'package:flutter/material.dart';

import 'home_content.dart';
import 'home_more_sections.dart';
import 'home_nav.dart';
import 'home_overlays.dart';
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

  void _handleLink(HomeLink link) {
    switch (link) {
      case AnchorLink(:final anchor):
        _scrollTo(anchor);
      case DemoLink():
        _bookDemo();
      case SignUpLink():
        widget.onSignUp();
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
        onLogin: widget.onLogin,
        onSignUp: widget.onSignUp,
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
              onSignUp: widget.onSignUp,
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
                    onStart: widget.onSignUp,
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
                  EverythingSection(onStart: widget.onSignUp),
                  const ReachSection(),
                  const PlansSection(),
                  PricingSection(
                    key: _anchors[HomeAnchor.pricing],
                    onStart: widget.onSignUp,
                    onTalk: _bookDemo,
                  ),
                  SupportSection(onTalk: _bookDemo),
                  WhyUsSection(onDemo: _bookDemo),
                  ReviewsSection(key: _anchors[HomeAnchor.reviews]),
                  VideoStoriesSection(
                      onPlay: (title) =>
                          _notice('“$title” — video coming soon.')),
                  FaqSection(key: _anchors[HomeAnchor.faq], onDemo: _bookDemo),
                  FinalCtaSection(onStart: widget.onSignUp, onTalk: _bookDemo),
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
