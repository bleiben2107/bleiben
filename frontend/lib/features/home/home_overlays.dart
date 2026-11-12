import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'home_content.dart';
import 'home_widgets.dart';

// ── Offer countdown ──────────────────────────────────────────────────────────

/// Rebuilds [builder] every [tick] with the time left until [endsAt].
class Countdown extends StatefulWidget {
  const Countdown({
    super.key,
    required this.endsAt,
    required this.builder,
    this.tick = const Duration(seconds: 30),
  });

  final DateTime endsAt;
  final Duration tick;
  final Widget Function(BuildContext context, Duration left) builder;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.tick, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.endsAt.difference(DateTime.now());
    return widget.builder(context, left.isNegative ? Duration.zero : left);
  }
}

class _TimeBlocks extends StatelessWidget {
  const _TimeBlocks(this.left, {this.dark = true});

  final Duration left;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    Widget block(int value, String unit) {
      return Container(
        width: 38,
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: BoxDecoration(
          color: dark ? Colors.white.withValues(alpha: 0.12) : HomeColors.mist,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(
              value.toString().padLeft(2, '0'),
              style: AppFonts.sans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: dark ? Colors.white : AppTheme.ink,
                height: 1.1,
              ),
            ),
            Text(
              unit,
              style: AppFonts.sans(
                fontSize: 8.5,
                letterSpacing: 0.6,
                color: dark ? Colors.white60 : HomeColors.muted,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        block(left.inDays, 'DAYS'),
        const SizedBox(width: 4),
        block(left.inHours % 24, 'HRS'),
        const SizedBox(width: 4),
        block(left.inMinutes % 60, 'MIN'),
      ],
    );
  }
}

/// Thin announcement bar above the nav.
class OfferBar extends StatelessWidget {
  const OfferBar(
      {super.key,
      required this.offer,
      required this.onClaim,
      required this.onDismiss});

  final LaunchOffer offer;
  final VoidCallback onClaim;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final medium = HomeLayout.isMedium(context);
    return Material(
      color: HomeColors.night,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: HomeLayout.gutter(context), vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          const WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Icon(Icons.local_offer_rounded,
                                size: 15, color: Color(0xFFF2B28E)),
                          ),
                          TextSpan(
                            text: '  ${offer.headline}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFF2B28E)),
                          ),
                          if (medium) TextSpan(text: ' — ${offer.detail}'),
                        ],
                      ),
                      style: AppFonts.sans(
                          fontSize: 13.5, color: Colors.white),
                    ),
                    Countdown(
                      endsAt: offer.endsAt,
                      builder: (context, left) => _TimeBlocks(left),
                    ),
                    TextButton(
                      onPressed: onClaim,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: AppTheme.clay,
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        minimumSize: Size.zero,
                        textStyle: AppFonts.sans(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      child: const Text('Claim offer'),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Dismiss offer',
                onPressed: onDismiss,
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close_rounded,
                    size: 18, color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact offer card shown under the hero call-to-action buttons.
class OfferCard extends StatelessWidget {
  const OfferCard({super.key, required this.offer, required this.onSeePricing});

  final LaunchOffer offer;
  final VoidCallback onSeePricing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBF1E6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.clay.withValues(alpha: 0.25)),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                offer.headline,
                style: AppFonts.sans(
                    fontWeight: FontWeight.w700, color: AppTheme.clay),
              ),
              Text(
                'Save ${(offer.annualDiscount * 100).round()}% on annual plans',
                style:
                    AppFonts.sans(fontSize: 12.5, color: HomeColors.muted),
              ),
            ],
          ),
          Countdown(
            endsAt: offer.endsAt,
            builder: (context, left) => _TimeBlocks(left, dark: false),
          ),
          TextButton(
            onPressed: onSeePricing,
            child: Text(
              'See pricing →',
              style: AppFonts.sans(
                  fontWeight: FontWeight.w600, color: AppTheme.forest),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Book a demo ──────────────────────────────────────────────────────────────

/// Collected demo request. Sent nowhere yet — see [showDemoDialog].
class DemoRequest {
  const DemoRequest({
    required this.name,
    required this.contact,
    required this.properties,
    required this.date,
    required this.slot,
  });

  final String name;
  final String contact;
  final String properties;
  final DateTime date;
  final String slot;
}

/// Opens the "Book a demo" form. Resolves to the request when submitted.
// TODO(backend): POST the request to a demo-booking endpoint once it exists.
Future<DemoRequest?> showDemoDialog(BuildContext context) {
  return showDialog<DemoRequest>(
    context: context,
    builder: (_) => const _DemoDialog(),
  );
}

class _DemoDialog extends StatefulWidget {
  const _DemoDialog();

  @override
  State<_DemoDialog> createState() => _DemoDialogState();
}

class _DemoDialogState extends State<_DemoDialog> {
  static const _sizes = [
    '1 property',
    '2–5 properties',
    '6–20 properties',
    '21–100 properties',
    '100+ properties'
  ];
  static const _slots = ['10:00', '11:30', '13:00', '15:00', '16:30', '18:00'];

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _contact = TextEditingController();
  String? _size;
  DateTime? _date;
  String? _slot;
  bool _showSlotError = false;
  DemoRequest? _done;

  @override
  void dispose() {
    _name.dispose();
    _contact.dispose();
    super.dispose();
  }

  static bool _validContact(String v) {
    final email = RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$');
    final phone = RegExp(r'^\+?[0-9 ]{10,15}$');
    return email.hasMatch(v) || phone.hasMatch(v);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _submit() {
    final formOk = _formKey.currentState!.validate();
    setState(() => _showSlotError = _date == null || _slot == null);
    if (!formOk || _showSlotError) return;
    setState(() {
      _done = DemoRequest(
        name: _name.text.trim(),
        contact: _contact.text.trim(),
        properties: _size!,
        date: _date!,
        slot: _slot!,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: _done == null ? _form() : _confirmation(_done!),
        ),
      ),
    );
  }

  InputDecoration _input(String label) => InputDecoration(
        labelText: label,
        fillColor: HomeColors.mist,
      );

  Widget _form() {
    final dateText =
        _date == null ? 'Pick a date' : DateFormat('EEE, d MMM').format(_date!);
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Book a demo',
                  style: AppFonts.display(
                      fontSize: 26, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          Text(
            'A 30-minute walkthrough with our team, tailored to your properties.',
            style: AppFonts.sans(color: HomeColors.muted),
          ),
          const SizedBox(height: 22),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: _input('Your name'),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter your name'
                : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _contact,
            keyboardType: TextInputType.emailAddress,
            decoration: _input('Email or phone number'),
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return 'We need a way to reach you';
              }
              return _validContact(v.trim())
                  ? null
                  : 'Enter a valid email or phone number';
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _size,
            decoration: _input('How many properties?'),
            items: [
              for (final s in _sizes) DropdownMenuItem(value: s, child: Text(s))
            ],
            onChanged: (v) => setState(() => _size = v),
            validator: (v) => v == null ? 'Choose one' : null,
          ),
          const SizedBox(height: 18),
          Text('Preferred time (IST)',
              style: AppFonts.sans(fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(dateText),
            style: OutlinedButton.styleFrom(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in _slots)
                ChoiceChip(
                  label: Text(s),
                  selected: _slot == s,
                  onSelected: (_) => setState(() => _slot = s),
                  selectedColor: AppTheme.forest,
                  labelStyle: AppFonts.sans(
                    color: _slot == s ? Colors.white : AppTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                  showCheckmark: false,
                ),
            ],
          ),
          if (_showSlotError) ...[
            const SizedBox(height: 8),
            Text(
              'Pick a date and a time slot',
              style: AppFonts.sans(
                  color: Theme.of(context).colorScheme.error, fontSize: 12.5),
            ),
          ],
          const SizedBox(height: 24),
          PillButton(label: 'Request demo', onPressed: _submit),
        ],
      ),
    );
  }

  Widget _confirmation(DemoRequest r) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircleAvatar(
          radius: 30,
          backgroundColor: Color(0x1A2E8B57),
          child: Icon(Icons.check_rounded, size: 34, color: HomeColors.success),
        ),
        const SizedBox(height: 16),
        Text(
          'Request received',
          style:
              AppFonts.display(fontSize: 26, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'Thanks, ${r.name.split(' ').first}. We will confirm your demo for '
          '${DateFormat('EEE, d MMM').format(r.date)} at ${r.slot} IST at ${r.contact}.',
          textAlign: TextAlign.center,
          style: AppFonts.sans(color: HomeColors.muted, height: 1.5),
        ),
        const SizedBox(height: 24),
        PillButton(label: 'Done', onPressed: () => Navigator.pop(context, r)),
      ],
    );
  }
}

// ── Channels dialog ──────────────────────────────────────────────────────────

Future<void> showChannelsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Supported channels',
                      style: AppFonts.display(
                          fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in kSupportedChannels)
                    Chip(
                      avatar: const Icon(Icons.check_circle_rounded,
                          size: 16, color: HomeColors.success),
                      label: Text(c),
                      labelStyle: AppFonts.sans(fontSize: 13.5),
                      backgroundColor: HomeColors.mist,
                      side: BorderSide.none,
                      shape: const StadiumBorder(),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Availability can vary by region. We confirm your channels during onboarding.',
                style:
                    AppFonts.sans(fontSize: 12.5, color: HomeColors.muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

// ── Floating actions ─────────────────────────────────────────────────────────

/// Bottom-right "Book a demo" pill plus a back-to-top button that appears
/// once the visitor has scrolled.
class FloatingActions extends StatelessWidget {
  const FloatingActions({
    super.key,
    required this.showBackToTop,
    required this.onDemo,
    required this.onBackToTop,
    this.compact = false,
  });

  /// Icon-only demo button for phones, so it doesn't cover page content.
  final bool compact;
  final bool showBackToTop;
  final VoidCallback onDemo;
  final VoidCallback onBackToTop;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedScale(
          scale: showBackToTop ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton.small(
            heroTag: 'back-to-top',
            tooltip: 'Back to top',
            backgroundColor: Colors.white,
            foregroundColor: AppTheme.forest,
            onPressed: onBackToTop,
            child: const Icon(Icons.keyboard_arrow_up_rounded),
          ),
        ),
        const SizedBox(height: 10),
        if (compact)
          FloatingActionButton(
            heroTag: 'book-demo',
            tooltip: 'Book a demo',
            backgroundColor: AppTheme.forest,
            foregroundColor: Colors.white,
            onPressed: onDemo,
            child: const Icon(Icons.video_call_outlined),
          )
        else
          FloatingActionButton.extended(
            heroTag: 'book-demo',
            backgroundColor: AppTheme.forest,
            foregroundColor: Colors.white,
            onPressed: onDemo,
            icon: const Icon(Icons.video_call_outlined),
            label: Text('Book a demo',
                style: AppFonts.sans(fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }
}

// ── Account sheet ────────────────────────────────────────────────────────────

/// Slides the account menu in from the right. Resolves to the tapped action,
/// or null when the sheet is dismissed.
Future<AccountAction?> showAccountSheet(
  BuildContext context, {
  bool signedIn = false,
  String? displayName,
}) {
  return showGeneralDialog<AccountAction>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close account menu',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: AccountSheet(signedIn: signedIn, displayName: displayName),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class AccountSheet extends StatelessWidget {
  const AccountSheet({super.key, this.signedIn = false, this.displayName});

  final bool signedIn;
  final String? displayName;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final groups = accountMenuGroups(signedIn: signedIn);
    final name = displayName?.trim() ?? '';
    final initial = name.isEmpty ? null : name[0].toUpperCase();

    return Material(
      color: Colors.white,
      elevation: 16,
      child: SizedBox(
        width: width < 420 ? width * 0.88 : 385,
        height: double.infinity,
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 18),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: signedIn && initial != null
                          ? AppTheme.ink
                          : HomeColors.mist,
                      child: signedIn && initial != null
                          ? Text(initial,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600))
                          : const Icon(Icons.person_rounded,
                              color: HomeColors.muted, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        signedIn && displayName != null
                            ? displayName!
                            : 'Hey there!',
                        overflow: TextOverflow.ellipsis,
                        style: AppFonts.sans(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close account menu',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              for (var g = 0; g < groups.length; g++)
                Container(
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: HomeColors.line)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final item in groups[g])
                        _AccountRow(item: item, emphasised: g == 0),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.item, required this.emphasised});

  final AccountMenuItem item;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: emphasised ? HomeColors.mist : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, item.action),
        hoverColor: HomeColors.line,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(item.icon,
                  size: 19,
                  color: emphasised ? AppTheme.forest : HomeColors.muted),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  item.label,
                  style: AppFonts.sans(
                    fontSize: 14.5,
                    fontWeight: emphasised ? FontWeight.w600 : FontWeight.w400,
                    color: AppTheme.ink,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
