import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/stays/stays_controller.dart';
import 'features/stays/stays_screen.dart';

class BleibenApp extends StatelessWidget {
  const BleibenApp({super.key, required this.auth, required this.stays});

  final AuthController auth;
  final StaysController stays;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        return MaterialApp(
          title: 'Bleiben',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: auth.isSignedIn
              ? StaysScreen(auth: auth, stays: stays)
              : LoginScreen(auth: auth, stays: stays),
        );
      },
    );
  }
}
