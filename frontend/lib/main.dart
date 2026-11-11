import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_store.dart';
import 'features/auth/auth_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionStore();
  await session.load();
  final api = ApiClient(session: session);
  final auth = AuthController(api: api, session: session);

  // Team invite links land here (?invite_token=…); the invite is accepted
  // as soon as the user is signed in.
  final invite = Uri.base.queryParameters['invite_token'];
  if (invite != null && invite.isNotEmpty) {
    await auth.rememberInvite(invite);
  }

  if (session.isSignedIn) await auth.loadProfile();
  runApp(BleibenApp(auth: auth, api: api));
}
