import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bleiben/app.dart';
import 'package:bleiben/core/network/api_client.dart';
import 'package:bleiben/core/storage/session_store.dart';
import 'package:bleiben/features/auth/auth_controller.dart';
import 'package:bleiben/features/stays/stays_controller.dart';

Future<void> _pumpApp(WidgetTester tester, Size size) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final session = SessionStore();
  final api = ApiClient(session: session);
  final auth = AuthController(api: api, session: session);
  final stays = StaysController(api: api);

  await tester.pumpWidget(BleibenApp(auth: auth, stays: stays));
  await tester.pump();
}

void main() {
  testWidgets('signed-out visitors land on the homepage (desktop)',
      (tester) async {
    await _pumpApp(tester, const Size(1440, 900));

    expect(find.text('Start free trial'), findsWidgets);
    expect(find.text('Log in'), findsOneWidget);
    expect(find.text('Pricing'), findsWidgets);

    await tester.tap(find.text('Log in'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
  });

  testWidgets('homepage lays out on a phone without overflow', (tester) async {
    await _pumpApp(tester, const Size(390, 844));

    expect(find.byTooltip('Menu'), findsOneWidget);

    // Scroll the whole page so every section is built and laid out.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 40; i++) {
      await tester.drag(scrollable, const Offset(0, -600));
      await tester.pump();
    }
    expect(find.textContaining('All rights reserved'), findsOneWidget);
  });

  testWidgets('Start free trial opens the sign-up form', (tester) async {
    await _pumpApp(tester, const Size(1440, 900));

    await tester.tap(find.text('Start free trial').first);
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });
}
