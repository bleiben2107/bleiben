import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bleiben/app.dart';
import 'package:bleiben/core/network/api_client.dart';
import 'package:bleiben/core/storage/session_store.dart';
import 'package:bleiben/features/auth/auth_controller.dart';
import 'package:bleiben/features/home/home_content.dart';

const _desktop = Size(1440, 900);
const _phone = Size(390, 844);

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final session = SessionStore();
  final api = ApiClient(session: session);
  final auth = AuthController(api: api, session: session);

  await tester.pumpWidget(BleibenApp(auth: auth, api: api));
  await tester.pump();
}

Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('signed-out visitors land on the homepage (desktop)',
      (tester) async {
    await _pumpApp(tester, _desktop);

    expect(find.text('Start free trial'), findsWidgets);
    expect(find.text('Product'), findsOneWidget);
    expect(find.byTooltip('Menu and account'), findsOneWidget);

    // Sign-in lives in the account sheet, as on the reference site.
    await tester.tap(find.byTooltip('Menu and account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign up / Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('account sheet shows signed-out items and closes',
      (tester) async {
    await _pumpApp(tester, _desktop);

    await tester.tap(find.byTooltip('Menu and account'));
    await tester.pumpAndSettle();

    expect(find.text('Hey there!'), findsOneWidget);
    for (final label in [
      'Sign up / Sign in',
      'Book your stay',
      'List your property',
      'About us',
      'Contact us',
      'Help centre',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    // Signed-in only items stay hidden.
    expect(find.text('Log out'), findsNothing);
    expect(find.text('Trips'), findsNothing);

    await tester.tap(find.byTooltip('Close account menu'));
    await tester.pumpAndSettle();
    expect(find.text('Hey there!'), findsNothing);
  });

  testWidgets('account sheet "List your property" opens sign-up',
      (tester) async {
    await _pumpApp(tester, _desktop);

    await tester.tap(find.byTooltip('Menu and account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('List your property').last);
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('phone menu opens the account sheet', (tester) async {
    await _pumpApp(tester, _phone);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Log in or account'));
    await tester.tap(find.text('Log in or account'));
    await tester.pumpAndSettle();

    expect(find.text('Hey there!'), findsOneWidget);
    expect(find.text('Sign up / Sign in'), findsOneWidget);
  });

  test('account menu hides session items when signed out', () {
    List<String> labels(bool signedIn) => [
          for (final g in accountMenuGroups(signedIn: signedIn))
            for (final i in g) i.label,
        ];
    expect(labels(false), contains('Sign up / Sign in'));
    expect(labels(false), isNot(contains('Log out')));
    expect(labels(true), containsAll(['Trips', 'Account settings', 'Log out']));
    expect(labels(true), isNot(contains('Sign up / Sign in')));
  });

  testWidgets('homepage lays out on a phone without overflow', (tester) async {
    await _pumpApp(tester, _phone);

    expect(find.byTooltip('Menu'), findsOneWidget);

    // Scroll the whole page so every section is built and laid out.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 90; i++) {
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
    }
    expect(find.textContaining('All rights reserved'), findsOneWidget);
  });

  testWidgets('Start free trial opens the sign-up form', (tester) async {
    await _pumpApp(tester, _desktop);

    await tester.tap(find.text('Start free trial').first);
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('Product menu opens and lists features', (tester) async {
    await _pumpApp(tester, _desktop);

    await tester.tap(find.text('Product'));
    await tester.pumpAndSettle();

    expect(find.text('Channel manager'), findsWidgets);
    expect(find.text('Smart listings'), findsWidgets);
    expect(find.text('Book a demo →'), findsOneWidget);
  });

  testWidgets('offer bar can be dismissed', (tester) async {
    await _pumpApp(tester, _desktop);
    if (!kLaunchOffer.isLive) return; // Offer has ended.

    expect(find.text('Claim offer'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss offer'));
    await tester.pumpAndSettle();
    expect(find.text('Claim offer'), findsNothing);
  });

  testWidgets('channels chip opens the supported-channels dialog',
      (tester) async {
    await _pumpApp(tester, _desktop);

    await _scrollAndTap(tester, find.byTooltip('See all supported channels'));
    expect(find.text('Supported channels'), findsOneWidget);
  });

  testWidgets('tapping an open calendar date blocks it', (tester) async {
    await _pumpApp(tester, _desktop);

    expect(find.byTooltip('Tap to reopen'), findsNothing);
    await _scrollAndTap(tester, find.byTooltip('Tap to block this date').first);
    expect(find.byTooltip('Tap to reopen'), findsOneWidget);
  });

  testWidgets('FAQ expands to show every question', (tester) async {
    await _pumpApp(tester, _desktop);

    expect(find.text(kFaqs.last.$1), findsNothing);
    await _scrollAndTap(
        tester, find.text('Show all ${kFaqs.length} questions'));
    expect(find.text(kFaqs.last.$1), findsOneWidget);
  });

  testWidgets('demo form validates and confirms a request', (tester) async {
    await _pumpApp(tester, _desktop);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Book a demo'));
    await tester.pumpAndSettle();
    expect(find.text('Request demo'), findsOneWidget);

    // Empty submit shows validation errors.
    await tester.tap(find.text('Request demo'));
    await tester.pumpAndSettle();
    expect(find.text('Please enter your name'), findsOneWidget);
    expect(find.text('Pick a date and a time slot'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your name'), 'Asha Rao');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email or phone number'),
        'asha@example.com');

    await tester.tap(find.text('How many properties?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2–5 properties').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pick a date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('11:30'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Request demo'));
    await tester.pumpAndSettle();
    expect(find.text('Request received'), findsOneWidget);
  });
}
