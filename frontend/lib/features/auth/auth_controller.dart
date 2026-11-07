import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';

class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.session});

  final ApiClient api;
  final SessionStore session;

  bool busy = false;
  String? error;

  bool get isSignedIn => session.isSignedIn;
  String get displayName => session.name ?? 'Guest';
  String get email => session.email ?? '';

  Future<void> loadProfile() async {
    try {
      final data = await api.get('/api/auth/me') as Map<String, dynamic>;
      await session.save(
        token: session.token!,
        name: data['name'] as String,
        email: data['email'] as String,
      );
      notifyListeners();
    } catch (_) {
      await session.clear();
      notifyListeners();
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) {
    return _authenticate('/api/auth/register', {
      'name': name,
      'email': email,
      'password': password,
    });
  }

  Future<bool> login({required String email, required String password}) {
    return _authenticate('/api/auth/login', {
      'email': email,
      'password': password,
    });
  }

  Future<bool> _authenticate(String path, Map<String, dynamic> body) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final data = await api.post(path, body, auth: false) as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>;
      await session.save(
        token: data['access_token'] as String,
        name: user['name'] as String,
        email: user['email'] as String,
      );
      return true;
    } on ApiException catch (e) {
      error = e.message;
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await session.clear();
    notifyListeners();
  }
}
