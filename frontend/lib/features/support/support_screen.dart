import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';

/// Host Control Center → Support (MVP plan §2.8, R1): help centre with
/// guides and FAQs, plus a contact route. Tickets come later.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  static const email = 'team@bleiben.co.in';

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

const _guides = <(String, IconData, List<(String, String)>)>[
  ('Getting started', Icons.flag_outlined, [
    ('What should I set up first?', 'Create your property (Properties → Create new listing), add rooms with unit counts and prices, publish it, then share your booking link. Connect Airbnb/Booking.com calendars in Channel Manager so dates never double-book.'),
    ('How does the free trial work?', 'You get 14 days with every feature and no card. Choose a plan in Subscription & Billing before it ends. If it lapses, your account becomes read-only for 7 days, then your booking page closes until you renew.'),
  ]),
  ('Property setup', Icons.holiday_village_outlined, [
    ('Rooms vs units', 'A room is a type you sell (e.g. "Deluxe"). Units are how many identical ones you have. A room with 3 units can take 3 bookings on the same night.'),
    ('How do I change prices for some dates?', 'Open Calendar, tap the first and last date in the room\'s row, then use Pricing → Set price or Adjust by % (optionally only on chosen weekdays).'),
    ('Why can\'t I publish?', 'Publishing needs a title, a property type and at least one room (or a nightly price for entire-place listings).'),
  ]),
  ('Bookings', Icons.event_available_outlined, [
    ('Adding a phone or walk-in booking', 'Use Create booking in Reservations, Calendar or the Dashboard. Record any advance; the rest shows as balance due.'),
    ('What is a 15-minute hold?', 'When a guest starts paying on your booking page we hold the room for 15 minutes so nobody else can take it. Unpaid holds are released automatically.'),
    ('What is an enquiry?', 'An enquiry records interest without blocking the room. Confirm it when the guest commits — we re-check availability first.'),
  ]),
  ('Payments', Icons.payments_outlined, [
    ('How do guests pay online?', 'Connect your Razorpay account in Settings → Payments. Money goes straight to you; Bleiben confirms the booking once Razorpay verifies the payment.'),
    ('A guest paid but the booking isn\'t confirmed', 'Check Inbox → Notifications for a "Payment failed" or "refund needed" alert. Adding the webhook secret in Settings → Payments makes confirmations reliable even if the guest closes the page.'),
  ]),
  ('Channel Manager', Icons.sync_alt_rounded, [
    ('How often do calendars sync?', 'Every 30 minutes, or immediately with Sync now. iCal is never instant, so a short double-booking window is possible — keep an eye on Channel Manager → Conflicts.'),
    ('Which link goes where?', 'Paste the Airbnb/Booking.com export link into Connect calendar. Paste our export link (Channel Manager → Export links) into Airbnb/Booking.com.'),
  ]),
];

class _SupportScreenState extends State<SupportScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final q = _q.toLowerCase();
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12, vertical: 20),
      children: [
        Text('Help centre', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: TextField(
            key: const Key('help-search'),
            onChanged: (v) => setState(() => _q = v.trim()),
            decoration: const InputDecoration(hintText: 'Search help', prefixIcon: Icon(Icons.search), isDense: true),
          ),
        ),
        const SizedBox(height: 16),
        for (final g in _guides)
          if (q.isEmpty || g.$3.any((x) => '${x.$1} ${x.$2}'.toLowerCase().contains(q)))
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ListTile(leading: Icon(g.$2, color: AppTheme.forest), title: Text(g.$1, style: AppFonts.sans(fontWeight: FontWeight.w700, fontSize: 16))),
                  for (final item in g.$3)
                    if (q.isEmpty || '${item.$1} ${item.$2}'.toLowerCase().contains(q))
                      ExpansionTile(
                        title: Text(item.$1),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        expandedAlignment: Alignment.centerLeft,
                        children: [Text(item.$2, style: AppFonts.sans(height: 1.5))],
                      ),
                ]),
              ),
            ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppTheme.sage, borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
          child: Row(children: [
            const Icon(Icons.support_agent, color: AppTheme.forest, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Still stuck? Write to us', style: AppFonts.sans(fontWeight: FontWeight.w700, fontSize: 16)),
                const Text('Email ${SupportScreen.email} with your property name and what happened. We reply within one working day.'),
              ]),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: SupportScreen.email));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Support email copied')));
                }
              },
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy email'),
            ),
          ]),
        ),
      ],
    );
  }
}
