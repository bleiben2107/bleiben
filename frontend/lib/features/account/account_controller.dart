import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

/// Account settings actions (`/api/account`). Every successful change is
/// pushed into [AuthController.applyUser] so the avatar and name refresh
/// across the app.
class AccountController extends ChangeNotifier {
  AccountController({required this.api, required this.auth});

  final ApiClient api;
  final AuthController auth;

  bool saving = false;

  /// Full URL for a stored photo path such as /media/avatars/abc.png.
  static String mediaUrl(String path) => '${ApiConfig.baseUrl}$path';

  /// Saves Personal info. Returns an error message, or null on success.
  Future<String?> saveProfile(Map<String, dynamic> values) =>
      _userCall(() => api.patch('/api/account/profile', values));

  Future<String?> uploadAvatar(Uint8List bytes) => _userCall(() =>
      api.post('/api/account/avatar', {'data': base64Encode(bytes)}));

  /// Sends an OTP to a new email ([channel] "email") or phone ("phone").
  Future<(CodeSent?, String?)> requestContactOtp(String channel, String value,
      {String countryCode = '+91'}) async {
    try {
      final res = (await api.post('/api/account/contact/request-otp', {
        'channel': channel,
        'value': value,
        'country_code': countryCode,
      }) as Map)
          .cast<String, dynamic>();
      return (CodeSent.fromJson(res), null);
    } on ApiException catch (e) {
      return (null, e.message);
    }
  }

  /// Confirms the OTP; on success the account has the new email / phone.
  Future<String?> verifyContactOtp(String channel, String value, String code,
          {String countryCode = '+91'}) =>
      _userCall(() => api.post('/api/account/contact/verify-otp', {
            'channel': channel,
            'value': value,
            'code': code,
            'country_code': countryCode,
          }));

  Future<String?> renameOrganization(int orgId, String name) async {
    try {
      await api.patch('/api/orgs/$orgId', {'name': name});
      await auth.loadProfile();
      return null;
    } on ApiException catch (e) {
      return e.message;
    }
  }

  Future<String?> _userCall(Future<dynamic> Function() call) async {
    saving = true;
    notifyListeners();
    try {
      final user = (await call() as Map).cast<String, dynamic>();
      await auth.applyUser(user);
      return null;
    } on ApiException catch (e) {
      return e.message;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
