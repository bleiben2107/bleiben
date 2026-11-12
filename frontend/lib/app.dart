import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/account/account_screen.dart';
import 'features/home/home_screen.dart';

class BleibenApp extends StatelessWidget {
  const BleibenApp({super.key, required this.auth, required this.api});

  final AuthController auth;
  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        // Signing in or out swaps the key, which resets navigation (drops the
        // pushed login screen, or the host area after logging out). Either
        // way the user lands on the homepage, as on homyhuts.
        final signedIn = auth.isSignedIn;
        return MaterialApp(
          key: ValueKey(signedIn ? 'user' : 'public'),
          title: 'Bleiben',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: Builder(
            builder: (context) {
              void openAuth({required bool register}) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        LoginScreen(auth: auth, initialRegister: register),
                  ),
                );
              }

              void openAccountSettings() {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AccountSettingsScreen(auth: auth, api: api),
                  ),
                );
              }

              return HomeScreen(
                api: api,
                signedIn: signedIn,
                displayName: signedIn ? auth.displayName : null,
                onLogin: () => openAuth(register: false),
                onSignUp: () => openAuth(register: true),
                onAccountSettings: openAccountSettings,
                onLogout: auth.logout,
              );
            },
          ),
        );
      },
    );
  }
}
