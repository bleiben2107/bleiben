import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _tokenKey = 'bleiben_token';
  static const _nameKey = 'bleiben_name';
  static const _emailKey = 'bleiben_email';

  String? token;
  String? name;
  String? email;

  bool get isSignedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
    name = prefs.getString(_nameKey);
    email = prefs.getString(_emailKey);
  }

  Future<void> save({required String token, required String name, required String email}) async {
    this.token = token;
    this.name = name;
    this.email = email;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_nameKey, name);
    await prefs.setString(_emailKey, email);
  }

  Future<void> clear() async {
    token = null;
    name = null;
    email = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_nameKey);
    await prefs.remove(_emailKey);
  }
}
