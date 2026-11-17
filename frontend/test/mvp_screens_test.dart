import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bleiben/core/network/api_client.dart';
import 'package:bleiben/core/storage/session_store.dart';
import 'package:bleiben/features/booking/public_booking_screen.dart';
import 'package:bleiben/features/bookings/bookings_api.dart';
import 'package:bleiben/main.dart' show bookingDates, bookingSlug;

import 'booking_modules_test.dart' show FakeHostApi, pumpSection;

String _d(int n) => ymd(DateTime.now().add(Duration(days: n)));

void main() {
  testWidgets('inbox → notifications: delivery status, mark all read', (tester) async {
    final fake = await pumpSection(tester, 'inbox');
    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('Booking BLB-ABC123 confirmed'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsWidgets, reason: 'failed delivery flagged');

    await tester.tap(find.byKey(const Key('notification-9')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Guest email · ravi@example.com · sent'), findsOneWidget);
    expect(find.textContaining('failed — SMTP down'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(fake.notificationsRead, isTrue);
  });

  testWidgets('channel manager: connect a calendar, export link, resolve a conflict', (tester) async {
    final fake = await pumpSection(tester, 'channels');
    expect(find.textContaining('No calendars connected yet'), findsOneWidget);

    await tester.tap(find.byKey(const Key('connect-calendar')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('channel-url')), 'https://www.airbnb.com/calendar/ical/12.ics');
    await tester.tap(find.byKey(const Key('channel-save')));
    await tester.pumpAndSettle();
    expect(fake.bodies['POST /api/channels'], {'channel': 'airbnb', 'room_id': 11, 'url': 'https://www.airbnb.com/calendar/ical/12.ics'});
    expect(find.text('Airbnb · Deluxe'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);

    await tester.tap(find.text('Export links'));
    await tester.pumpAndSettle();
    expect(find.text('http://127.0.0.1:8000/api/ical/tok.ics'), findsOneWidget);

    await tester.tap(find.textContaining('Conflicts'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Already booked: Ravi Kumar (BLB-ABC123)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('resolve-4')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('resolve-note')), 'Moved guest');
    await tester.tap(find.byKey(const Key('resolve-save')));
    await tester.pumpAndSettle();
    expect(fake.bodies['POST /api/channels/conflicts/4/resolve'], {'note': 'Moved guest'});
    expect(find.textContaining('Resolved by Asha Rao'), findsOneWidget);
  });

  testWidgets('billing: trial shown, buy a plan in test mode, invoice listed', (tester) async {
    final fake = await pumpSection(tester, 'billing');
    expect(find.text('Free trial'), findsWidgets);
    expect(find.byKey(const Key('plan-chip')), findsOneWidget);
    expect(find.text('2'), findsWidgets); // units default to units in use

    await tester.tap(find.byTooltip('More units'));
    await tester.tap(find.byTooltip('More units'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('buy-starter')));
    await tester.tap(find.byKey(const Key('buy-starter')));
    await tester.pumpAndSettle();
    expect(fake.bodies['POST /api/billing/checkout'], {'plan': 'starter', 'interval': 'month', 'units': 4});
    await tester.tap(find.byKey(const Key('billing-test-pay')));
    await tester.pumpAndSettle();
    expect(fake.bodies['POST /api/billing/checkout/3/verify'], {'test_outcome': 'success'});
    expect(find.text('Starter'), findsWidgets);
    expect(find.textContaining('BLB-2026-00001'), findsOneWidget);
  });

  testWidgets('settings: save organisation and turn on test payments', (tester) async {
    final fake = await pumpSection(tester, 'settings');
    await tester.enterText(find.byKey(const Key('org-name')), 'Asha Stays & Co');
    await tester.enterText(find.byKey(const Key('org-gstin')), '29ABCDE1234F1Z5');
    await tester.drag(find.byKey(const Key('org-name')), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('org-a_city')), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-org')));
    await tester.pumpAndSettle();
    final org = fake.bodies['PATCH /api/settings/organization']!;
    expect(org['name'], 'Asha Stays & Co');
    expect(org['gstin'], '29ABCDE1234F1Z5');
    expect((org['address'] as Map)['country'], 'India');

    await tester.tap(find.text('Payments'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('gw-test')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-gateway')));
    await tester.pumpAndSettle();
    expect(fake.bodies['PUT /api/settings/payment-gateway'], {'provider': 'test'});
  });

  testWidgets('dashboard: booking, payment and property overviews', (tester) async {
    await pumpSection(tester, 'dashboard');
    expect(find.byKey(const Key('booking-overview')), findsOneWidget);
    expect(find.byKey(const Key('ov-total')), findsOneWidget);
    expect(find.text('2 · 1 · 1'), findsOneWidget);
    expect(find.text('Pending balances'), findsOneWidget);
    expect(find.text('1 · ₹2,000'), findsOneWidget);
    expect(find.text('1 of 2 free'), findsOneWidget);
    expect(find.byKey(const Key('qa-calendar')), findsOneWidget);
    expect(find.byKey(const Key('qa-block')), findsOneWidget);
  });

  testWidgets('calendar: month view with blocked day; reservations: guests view', (tester) async {
    await pumpSection(tester, 'calendar');
    await tester.tap(find.text('Month'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('month-label')), findsOneWidget);
    final blocked = find.byKey(Key('month-cell-11-${_d(6)}'));
    expect(blocked, findsOneWidget);
    expect(find.descendant(of: blocked, matching: find.text('Blocked')), findsOneWidget);
  });

  testWidgets('reservations: guests view lists repeat guests', (tester) async {
    await pumpSection(tester, 'reservations');
    await tester.tap(find.descendant(of: find.byKey(const Key('reservations-view')), matching: find.text('Guests')));
    await tester.pumpAndSettle();
    expect(find.text('Ravi Kumar  ·  repeat guest'), findsOneWidget);
  });

  test('booking links: slug and dates from the URL', () {
    expect(bookingSlug(Uri.parse('http://x/#/p/pine-cottage')), 'pine-cottage');
    expect(bookingSlug(Uri.parse('http://x/p/goa-house')), 'goa-house');
    expect(bookingSlug(Uri.parse('http://x/')), isNull);
    final r = bookingDates(Uri.parse('http://x/#/p/pine-cottage?checkin=${_d(3)}&checkout=${_d(5)}'));
    expect(ymd(r!.start), _d(3));
    expect(bookingDates(Uri.parse('http://x/#/p/a?checkin=2020-01-01&checkout=2020-01-03')), isNull);
  });

  testWidgets('guest booking page: dates → room → details → hold → test payment → confirmed', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakeHostApi();
    final session = SessionStore();
    await session.load();
    final api = ApiClient(session: session, httpClient: fake.client);
    final range = DateTimeRange(start: DateTime.now().add(const Duration(days: 3)), end: DateTime.now().add(const Duration(days: 5)));
    await tester.pumpWidget(MaterialApp(home: PublicBookingScreen(api: api, slug: 'pine-cottage', initialRange: range)));
    await tester.pumpAndSettle();

    expect(find.text('Pine Cottage'), findsWidgets);
    expect(find.text('2 night(s) · ₹8,000'), findsOneWidget);
    await tester.tap(find.byKey(const Key('select-room-11')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pay 25% now'), findsOneWidget);
    await tester.tap(find.byKey(const Key('continue-booking')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('book-now')));
    await tester.pumpAndSettle();
    expect(find.text('Enter your full name'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('guest-name')), 'Meera Shah');
    await tester.enterText(find.byKey(const Key('guest-phone')), '+91 98222 22222');
    await tester.enterText(find.byKey(const Key('guest-email')), 'meera@example.com');
    await tester.tap(find.byKey(const Key('book-now')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final book = fake.bodies['POST /api/public/stays/pine-cottage/book']!;
    expect(book['room_id'], 11);
    expect(book['guest'], {'name': 'Meera Shah', 'phone': '+91 98222 22222', 'email': 'meera@example.com'});
    expect(find.textContaining('Room held for you: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('pay-now')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const Key('test-pay')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(fake.bodies['POST /api/public/payments/5/verify'], {'test_outcome': 'success', 'token': 'tok123'});
    expect(find.text('Booking confirmed!'), findsOneWidget);
    expect(find.text('₹6,000'), findsOneWidget);
    // Stop the hold-countdown timer before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
