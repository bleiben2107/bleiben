import 'package:flutter/material.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'core/storage/session_store.dart';
import 'features/auth/auth_controller.dart';
import 'features/stays/stays_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final session = SessionStore();
  await session.load();
  final api = ApiClient(session: session);
  final auth = AuthController(api: api, session: session);
  final stays = StaysController(api: api);
  if (session.isSignedIn) {
    await auth.loadProfile();
    await stays.refresh();
  }
  runApp(BleibenApp(auth: auth, stays: stays));
}
