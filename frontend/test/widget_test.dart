import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bleiben/app.dart';
import 'package:bleiben/core/network/api_client.dart';
import 'package:bleiben/core/storage/session_store.dart';
import 'package:bleiben/features/auth/auth_controller.dart';
import 'package:bleiben/features/stays/stays_controller.dart';

void main() {
  testWidgets('BleibenApp renders login screen when signed out', (WidgetTester tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    final session = SessionStore();
    final api = ApiClient(session: session);
    final auth = AuthController(api: api, session: session);
    final stays = StaysController(api: api);

    await tester.pumpWidget(BleibenApp(auth: auth, stays: stays));
    await tester.pump();

    expect(find.text('Bleiben'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
  });
}
