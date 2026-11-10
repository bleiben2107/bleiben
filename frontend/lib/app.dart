import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_screen.dart';
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
          // A new key when the session changes resets the navigator, so a
          // login screen pushed from the homepage is dropped after sign-in.
          key: ValueKey(auth.isSignedIn),
          title: 'Bleiben',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: auth.isSignedIn
              ? StaysScreen(auth: auth, stays: stays)
              : Builder(
                  builder: (context) {
                    void openAuth({required bool register}) {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LoginScreen(
                            auth: auth,
                            stays: stays,
                            initialRegister: register,
                          ),
                        ),
                      );
                    }

                    return HomeScreen(
                      onLogin: () => openAuth(register: false),
                      onSignUp: () => openAuth(register: true),
                    );
                  },
                ),
        );
      },
    );
  }
}
