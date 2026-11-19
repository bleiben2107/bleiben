import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_store.dart';
import 'core/theme/app_theme.dart';
import 'core/util/url_strategy.dart';
import 'features/booking/public_booking_screen.dart';
import 'features/auth/auth_controller.dart';

Future<void> main() async {
  useCleanUrls();
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionStore();
  await session.load();
  final api = ApiClient(session: session);
  final auth = AuthController(api: api, session: session);

  // Guest booking pages: /p/<slug> (old /#/p/<slug> links are rewritten).
  final slug = bookingSlug(Uri.base);
  if (slug != null) {
    runApp(MaterialApp(
      title: 'Book your stay',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Keep the booking route in the address bar so a refresh stays on this page.
      initialRoute: '/p/$slug',
      onGenerateRoute: (_) => MaterialPageRoute<void>(
        builder: (_) => PublicBookingScreen(api: api, slug: slug, initialRange: bookingDates(Uri.base)),
      ),
    ));
    return;
  }

  // Team invite links land here (?invite_token=…); the invite is accepted
  // as soon as the user is signed in.
  final invite = Uri.base.queryParameters['invite_token'];
  if (invite != null && invite.isNotEmpty) {
    await auth.rememberInvite(invite);
  }

  if (session.isSignedIn) await auth.loadProfile();
  runApp(BleibenApp(auth: auth, api: api));
}

/// The property slug when the URL is a guest booking page, else null.
String? bookingSlug(Uri uri) {
  final m = RegExp(r'^/p/([A-Za-z0-9_-]+)').firstMatch(uri.path) ?? RegExp(r'^/?p/([A-Za-z0-9_-]+)').firstMatch(uri.fragment);
  return m?.group(1);
}

/// Optional dates on a booking link: ?checkin=YYYY-MM-DD&checkout=YYYY-MM-DD
/// (in the query or after the #).
DateTimeRange? bookingDates(Uri uri) {
  final frag = uri.fragment.contains('?') ? Uri.splitQueryString(uri.fragment.split('?').last) : const <String, String>{};
  final q = {...frag, ...uri.queryParameters};
  final a = DateTime.tryParse(q['checkin'] ?? '');
  final b = DateTime.tryParse(q['checkout'] ?? '');
  final today = DateTime.now();
  if (a == null || b == null || !b.isAfter(a) || a.isBefore(DateTime(today.year, today.month, today.day))) return null;
  return DateTimeRange(start: a, end: b);
}
