import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';

import '../../core/theme/app_theme.dart';
import 'home_content.dart';
import 'home_mockups.dart';
import 'home_sections.dart' show BleibenWordmark;
import 'home_widgets.dart';

TextStyle _body({double size = 15.5, Color color = HomeColors.muted}) =>
    AppFonts.sans(fontSize: size, color: color, height: 1.55);

TextStyle _title({double size = 18, Color color = AppTheme.ink}) =>
    AppFonts.sans(
        fontSize: size, fontWeight: FontWeight.w600, color: color, height: 1.3);

// ── Everything you need ──────────────────────────────────────────────────────

class EverythingSection extends StatelessWidget {
  const EverythingSection({super.key, required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final syncVisual = Column(
      children: [
        for (final c in kChannels.take(4))
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                Icon(c.icon, size: 18, color: c.color),
                const SizedBox(width: 10),
                Expanded(child: Text(c.name, style: _title(size: 14))),
                const Icon(Icons.check_circle_rounded,
                    size: 18, color: HomeColors.success),
              ],
            ),
          ),
      ],
    );

    final opsVisual = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (icon, label) in const [
          (Icons.chat_outlined, 'WhatsApp guest'),
          (Icons.receipt_outlined, 'GST invoice'),
          (Icons.badge_outlined, 'Guest ID'),
          (Icons.restaurant_outlined, 'Meal add-on'),
          (Icons.airport_shuttle_outlined, 'Airport pickup'),
        ])
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(999)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: AppTheme.clay),
                const SizedBox(width: 6),
                Text(label,
                    style: AppFonts.sans(
                        fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
      ],
    );

    final profitVisual = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net profit · October', style: _body(size: 13)),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '₹68K',
                style: AppFonts.display(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.forest),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: HomeColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '↑ 18%',
                  style: AppFonts.sans(
                      fontSize: 12.5,
                      color: HomeColors.success,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 48,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final h in const [0.35, 0.5, 0.42, 0.6, 0.55, 0.75, 0.9])
                  Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      height: 48 * h,
                      decoration: BoxDecoration(
                        color:
                            AppTheme.forest.withValues(alpha: 0.25 + h * 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    Widget card(String title, String text, Widget visual) {
      return Container(
        padding: const EdgeInsets.all(26),
        decoration: BoxDecoration(
          color: HomeColors.mist,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: 210, child: Center(child: visual)),
            const SizedBox(height: 22),
            Text(title, style: _title(size: 20)),
            const SizedBox(height: 8),
            Text(text, style: _body(size: 14.5)),
          ],
        ),
      );
    }

    return SectionShell(
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Everything you need',
            lead: 'One platform. Every booking. ',
            accent: 'Every guest.',
          ),
          const SizedBox(height: 18),
          PillButton(
              label: 'Start free trial',
              icon: Icons.arrow_forward_rounded,
              onPressed: onStart),
          const SizedBox(height: 44),
          ResponsiveGrid(
            minItemWidth: 300,
            spacing: 22,
            children: [
              card(
                'Never worry about double bookings',
                'Bookings, availability and prices sync across every connected channel the moment anything changes.',
                syncVisual,
              ),
              card(
                'Run the whole business from one place',
                'Direct bookings, walk-ins, enquiries, invoices, add-ons and daily operations in one simple dashboard.',
                opsVisual,
              ),
              card(
                'Turn more bookings into more profit',
                'Grow direct bookings, price smarter and track every expense to see how each property really performs.',
                profitVisual,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Why Bleiben ──────────────────────────────────────────────────────────────

class WhyUsSection extends StatelessWidget {
  const WhyUsSection({super.key, required this.onDemo});

  final VoidCallback onDemo;

  static const _points = [
    (
      Icons.cottage_outlined,
      'Built with hosts',
      'Shaped by people who run homestays, not just software teams.'
    ),
    (
      Icons.currency_rupee_rounded,
      'Made for India, ready for the world',
      'GST invoices, UPI-friendly payments and Indian OTAs alongside global ones.'
    ),
    (
      Icons.lock_outline_rounded,
      'Your data stays yours',
      'Export bookings, guests and reports whenever you like.'
    ),
    (
      Icons.support_agent_rounded,
      'Humans on call',
      'Real people help you set up, migrate and grow.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);
    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionIntro(
          centered: false,
          eyebrow: 'Why Bleiben',
          lead: 'Built by hosts, ',
          accent: 'for hosts & managers',
          subtitle:
              'We started Bleiben after running holiday homes ourselves. Every feature exists '
              'because a host needed it.',
        ),
        const SizedBox(height: 24),
        PillButton(
            label: 'Book a demo with our team',
            icon: Icons.arrow_forward_rounded,
            onPressed: onDemo),
      ],
    );

    final grid = ResponsiveGrid(
      minItemWidth: 230,
      maxColumns: 2,
      spacing: 16,
      children: [
        for (final (icon, title, text) in _points)
          SurfaceCard(
            elevated: false,
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconBadge(icon),
                const SizedBox(height: 14),
                Text(title, style: _title(size: 16.5)),
                const SizedBox(height: 4),
                Text(text, style: _body(size: 14)),
              ],
            ),
          ),
      ],
    );

    return SectionShell(
      child: wide
          ? Row(
              children: [
                Expanded(flex: 5, child: intro),
                const SizedBox(width: 56),
                Expanded(flex: 6, child: grid),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 32), grid],
            ),
    );
  }
}

// ── Host video stories ───────────────────────────────────────────────────────

class VideoStoriesSection extends StatelessWidget {
  const VideoStoriesSection({super.key, required this.onPlay});

  final ValueChanged<String> onPlay;

  // TODO(launch): replace with real host videos.
  static const _videos = [
    (
      'How channel sync made hosting easier',
      'Villa host · Goa',
      Color(0xFF2F5D4A)
    ),
    (
      'From zero experience to a five-star homestay',
      'First-time host · Coorg',
      Color(0xFF8A5A3C)
    ),
    (
      'Running 12 homes with a team of three',
      'Property manager · Bengaluru',
      Color(0xFF34506B)
    ),
    (
      'Managing every OTA from one phone',
      'Guesthouse host · Manali',
      Color(0xFF5B4A7A)
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      background: HomeColors.mist,
      vertical: 80,
      child: Column(
        children: [
          const SectionIntro(
            eyebrow: 'Host stories',
            lead: 'Hear it from ',
            accent: 'the hosts themselves',
          ),
          const SizedBox(height: 40),
          ResponsiveGrid(
            minItemWidth: 250,
            maxColumns: 4,
            spacing: 18,
            children: [
              for (final (title, who, color) in _videos)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => onPlay(title),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 10,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [color, color.withValues(alpha: 0.7)],
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned(
                                  right: -12,
                                  bottom: -16,
                                  child: Icon(Icons.cottage_rounded,
                                      size: 120,
                                      color:
                                          Colors.white.withValues(alpha: 0.08)),
                                ),
                                Center(
                                  child: Semantics(
                                    button: true,
                                    label: 'Play video: $title',
                                    child: const CircleAvatar(
                                      radius: 26,
                                      backgroundColor: Colors.white,
                                      child: Icon(Icons.play_arrow_rounded,
                                          color: AppTheme.forest, size: 30),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(title, style: _title(size: 15.5)),
                        Text(who, style: _body(size: 13)),
                      ],
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

// ── FAQ ──────────────────────────────────────────────────────────────────────

class FaqSection extends StatefulWidget {
  const FaqSection({super.key, required this.onDemo});

  final VoidCallback onDemo;

  @override
  State<FaqSection> createState() => _FaqSectionState();
}

class _FaqSectionState extends State<FaqSection> {
  static const _initiallyShown = 6;
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final faqs = _showAll ? kFaqs : kFaqs.take(_initiallyShown).toList();
    final wide = HomeLayout.isWide(context);

    final intro = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionIntro(
          centered: false,
          eyebrow: 'FAQ',
          lead: 'Frequently asked ',
          accent: 'questions',
        ),
        const SizedBox(height: 16),
        Text('Can’t find what you need?', style: _body()),
        const SizedBox(height: 12),
        PillButton(
            label: 'Talk to our team', filled: false, onPressed: widget.onDemo),
      ],
    );

    final list = SurfaceCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < faqs.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: HomeColors.line),
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              childrenPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              iconColor: AppTheme.forest,
              title: Text(faqs[i].$1, style: _title(size: 16)),
              children: [Text(faqs[i].$2, style: _body(size: 15))],
            ),
          ],
          if (kFaqs.length > _initiallyShown) ...[
            const Divider(height: 1, color: HomeColors.line),
            TextButton(
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll
                    ? 'Show fewer questions'
                    : 'Show all ${kFaqs.length} questions',
                style: AppFonts.sans(
                    fontWeight: FontWeight.w600, color: AppTheme.forest),
              ),
            ),
          ],
        ],
      ),
    );

    return SectionShell(
      child: wide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: intro),
                const SizedBox(width: 48),
                Expanded(flex: 7, child: list),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [intro, const SizedBox(height: 28), list],
            ),
    );
  }
}

// ── Guides ───────────────────────────────────────────────────────────────────

class GuidesSection extends StatelessWidget {
  const GuidesSection({super.key, required this.onOpen});

  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return SectionShell(
      background: HomeColors.mist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.end,
            runSpacing: 16,
            children: [
              const SectionIntro(
                centered: false,
                eyebrow: 'Host handbook',
                lead: 'Guides for ',
                accent: 'smarter hosting',
              ),
              TextButton(
                onPressed: () => onOpen('The host handbook'),
                child: Text(
                  'Explore the handbook →',
                  style: AppFonts.sans(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.forest,
                      fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 210,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: kGuides.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final (tag, title, icon) = kGuides[i];
                return SizedBox(
                  width: 290,
                  child: Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onOpen(title),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                IconBadge(icon, color: AppTheme.clay, size: 36),
                                const SizedBox(width: 10),
                                Text(
                                  tag.toUpperCase(),
                                  style: AppFonts.sans(
                                    fontSize: 11.5,
                                    letterSpacing: 1.2,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.clay,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Expanded(
                              child: Text(title,
                                  style: _title(size: 17),
                                  overflow: TextOverflow.fade),
                            ),
                            Text('Read guide →',
                                style: AppFonts.sans(
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.forest)),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── Footer ───────────────────────────────────────────────────────────────────

class HomeFooter extends StatelessWidget {
  const HomeFooter({super.key, required this.onLink});

  final ValueChanged<HomeLink> onLink;

  @override
  Widget build(BuildContext context) {
    final wide = HomeLayout.isWide(context);

    Widget link(String label, HomeLink target) => Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: InkWell(
            onTap: () => onLink(target),
            child: Text(label, style: _body(size: 14, color: Colors.white60)),
          ),
        );

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BleibenWordmark(dark: true),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Text(
            'The calm way to run homestays, villas and holiday homes.',
            style: _body(size: 14.5, color: Colors.white60),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 8,
          children: [
            for (final (icon, name) in kSocialLinks)
              IconButton(
                tooltip: name,
                onPressed: () => onLink(PendingLink('Our $name page')),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08)),
                icon: Icon(icon, color: Colors.white70, size: 19),
              ),
          ],
        ),
      ],
    );

    final columns = [
      for (final (heading, items) in kFooterColumns)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(heading.toUpperCase(),
                style: AppFonts.sans(
                    fontSize: 12.5,
                    letterSpacing: 1.3,
                    fontWeight: FontWeight.w600,
                    color: Colors.white)),
            const SizedBox(height: 14),
            for (final (label, target) in items) link(label, target),
          ],
        ),
    ];

    final destinations = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('POPULAR DESTINATIONS',
            style: AppFonts.sans(
                fontSize: 12.5,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final d in kPopularDestinations)
              InkWell(
                onTap: () => onLink(PendingLink('Stays in $d')),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  child: Text('Stays in $d',
                      style: AppFonts.sans(
                          fontSize: 13, color: Colors.white70)),
                ),
              ),
          ],
        ),
      ],
    );

    return Container(
      width: double.infinity,
      color: HomeColors.night,
      padding: EdgeInsets.symmetric(
          horizontal: HomeLayout.gutter(context), vertical: 56),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: HomeLayout.maxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: brand),
                    for (final c in columns) Expanded(child: c),
                  ],
                )
              else ...[
                brand,
                const SizedBox(height: 32),
                Wrap(spacing: 48, runSpacing: 28, children: columns),
              ],
              const SizedBox(height: 36),
              destinations,
              const SizedBox(height: 36),
              const Divider(color: Colors.white12),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 24,
                runSpacing: 12,
                children: [
                  Text('© ${DateTime.now().year} Bleiben. All rights reserved.',
                      style: _body(size: 13, color: Colors.white38)),
                  Wrap(
                    spacing: 18,
                    children: [
                      link('Book a demo', const DemoLink()),
                      link('List your property', const SignUpLink()),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
