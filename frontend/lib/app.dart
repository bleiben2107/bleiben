import 'package:flutter/material.dart';

import 'core/network/api_client.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_screen.dart';
import 'features/account/account_screen.dart';
import 'features/home/home_screen.dart';
import 'features/host/host_control_center.dart';

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
          // Named routes so the Host Control Center lives at #/host/<section>
          // and a browser refresh lands back on it (signed in) instead of home.
          onGenerateInitialRoutes: (initial) => [
            _homeRoute(signedIn),
            if (signedIn && _hostSection(initial) != null) _hostRoute(_hostSection(initial)!),
          ],
          onGenerateRoute: (settings) {
            final section = _hostSection(settings.name ?? '/');
            if (signedIn && section != null) return _hostRoute(section);
            return _homeRoute(signedIn);
          },
        );
      },
    );
  }

  /// The section in a `/host` or `/host/<section>` route, or null.
  static String? _hostSection(String route) {
    final m = RegExp(r'^/host(?:/([a-z]+))?/?$').firstMatch(route.split('?').first);
    if (m == null) return null;
    final key = m.group(1) ?? 'properties';
    return hostSections.any((s) => s.key == key) ? key : 'properties';
  }

  Route<void> _hostRoute(String section) => MaterialPageRoute<void>(
        settings: RouteSettings(name: '/host/$section'),
        builder: (_) => HostControlCenterScreen(auth: auth, api: api, initialSection: section),
      );

  Route<void> _homeRoute(bool signedIn) => MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/'),
        builder: (context) {
          void openAuth({required bool register}) {
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LoginScreen(auth: auth, initialRegister: register),
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
            onHostControlCenter: () => Navigator.of(context).pushNamed('/host/properties'),
            onLogout: auth.logout,
          );
        },
      );
}
