import 'package:shared_preferences/shared_preferences.dart';

/// Persists the signed-in session and a few client-side preferences.
class SessionStore {
  static const _tokenKey = 'bleiben_token';
  static const _nameKey = 'bleiben_name';
  static const _emailKey = 'bleiben_email';
  static const _phoneKey = 'bleiben_phone';
  static const _orgKey = 'bleiben_active_org';
  static const _inviteKey = 'bleiben_pending_invite';

  String? token;
  String? name;
  String? email;
  String? phone;

  /// Organisation used for org-scoped requests (sent as `X-Org-Id`).
  int? activeOrgId;

  /// Invite token from an emailed link, kept until the user has signed in.
  String? pendingInviteToken;

  bool get isSignedIn => token != null && token!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
    name = prefs.getString(_nameKey);
    email = prefs.getString(_emailKey);
    phone = prefs.getString(_phoneKey);
    activeOrgId = prefs.getInt(_orgKey);
    pendingInviteToken = prefs.getString(_inviteKey);
  }

  Future<void> save({
    required String token,
    String? name,
    String? email,
    String? phone,
  }) async {
    this.token = token;
    this.name = name;
    this.email = email;
    this.phone = phone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await _setOrRemove(prefs, _nameKey, name);
    await _setOrRemove(prefs, _emailKey, email);
    await _setOrRemove(prefs, _phoneKey, phone);
  }

  Future<void> setActiveOrg(int? orgId) async {
    activeOrgId = orgId;
    final prefs = await SharedPreferences.getInstance();
    if (orgId == null) {
      await prefs.remove(_orgKey);
    } else {
      await prefs.setInt(_orgKey, orgId);
    }
  }

  Future<void> setPendingInvite(String? token) async {
    pendingInviteToken = token;
    final prefs = await SharedPreferences.getInstance();
    await _setOrRemove(prefs, _inviteKey, token);
  }

  Future<void> clear() async {
    token = null;
    name = null;
    email = null;
    phone = null;
    activeOrgId = null;
    final prefs = await SharedPreferences.getInstance();
    for (final key in [_tokenKey, _nameKey, _emailKey, _phoneKey, _orgKey]) {
      await prefs.remove(key);
    }
  }

  static Future<void> _setOrRemove(
      SharedPreferences prefs, String key, String? value) async {
    if (value == null || value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}
