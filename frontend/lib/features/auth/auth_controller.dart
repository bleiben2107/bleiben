import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/session_store.dart';
import 'auth_models.dart';

/// Session state: sign-in (email / phone OTP), the user's account details,
/// their organisations, and which one is active.
class AuthController extends ChangeNotifier {
  AuthController({required this.api, required this.session});

  final ApiClient api;
  final SessionStore session;

  bool busy = false;
  String? error;
  List<Membership> memberships = [];

  /// Full account details, refreshed on sign-in and by [loadProfile].
  AccountUser account = const AccountUser();

  bool get isSignedIn => session.isSignedIn;
  String get displayName => (session.name?.isNotEmpty ?? false)
      ? session.name!
      : (session.email ?? session.phone ?? 'Guest');
  String get email => session.email ?? '';
  String get phone => session.phone ?? '';

  /// The organisation the app is working in, if any.
  Membership? get activeMembership {
    if (memberships.isEmpty) return null;
    return memberships.firstWhere(
      (m) => m.orgId == session.activeOrgId,
      orElse: () => memberships.first,
    );
  }

  // ── Sign-in ────────────────────────────────────────────────────────────────

  /// Which screen the API suggests after an error ("login" or "signup").
  String? suggestedAction;

  /// Sign up step 1: name + email (required) + phone (optional). The OTP is
  /// emailed; nothing is created until it's verified.
  Future<CodeSent?> requestSignupOtp({
    required String name,
    required String email,
    String? phone,
    String countryCode = '+91',
  }) {
    return _run(() async {
      final data = await api.post(
        '/api/auth/signup/request-otp',
        {
          'name': name,
          'email': email,
          if (phone != null && phone.isNotEmpty) 'phone': phone,
          'country_code': countryCode,
        },
        auth: false,
      );
      return CodeSent.fromJson(data as Map<String, dynamic>);
    });
  }

  /// Sign up step 2: verify the emailed OTP; creates the account.
  Future<bool> verifySignupOtp(
      {required String email, required String code}) async {
    final ok = await _run(() async {
      final data = await api.post('/api/auth/signup/verify-otp',
          {'email': email, 'code': code, ..._inviteParam},
          auth: false);
      await _applySession(data as Map<String, dynamic>);
      return true;
    });
    return ok ?? false;
  }

  /// Log in step 1: email (OTP by email) or phone number (OTP by SMS).
  Future<CodeSent?> requestLoginOtp(
      {required String identifier, String countryCode = '+91'}) {
    return _run(() async {
      final data = await api.post(
        '/api/auth/login/request-otp',
        {'identifier': identifier, 'country_code': countryCode},
        auth: false,
      );
      return CodeSent.fromJson(data as Map<String, dynamic>);
    });
  }

  Future<bool> verifyLoginOtp(
      {required String identifier,
      required String code,
      String countryCode = '+91'}) async {
    final ok = await _run(() async {
      final data = await api.post(
        '/api/auth/login/verify-otp',
        {
          'identifier': identifier,
          'code': code,
          'country_code': countryCode,
          ..._inviteParam
        },
        auth: false,
      );
      await _applySession(data as Map<String, dynamic>);
      return true;
    });
    return ok ?? false;
  }

  Future<void> _applySession(Map<String, dynamic> data) async {
    final user = (data['user'] as Map).cast<String, dynamic>();
    await session.save(
      token: data['access_token'] as String,
      name: user['name'] as String?,
      email: user['email'] as String?,
      phone: user['phone'] as String?,
    );
    account = AccountUser.fromJson(user);
    _setMemberships(data['memberships']);
    // The API joins the invited organisation (or creates the user's own) as
    // part of verification, so the invite is consumed here.
    final invite = data['invite'] as String?;
    if (session.pendingInviteToken != null) {
      inviteNotice = invite == 'accepted'
          ? 'You joined ${memberships.isNotEmpty ? memberships.first.orgName : 'the team'}.'
          : invite;
      await session.setPendingInvite(null);
    }
    await _syncActiveOrg();
  }

  Map<String, dynamic> get _inviteParam => session.pendingInviteToken == null
      ? const {}
      : {'invite_token': session.pendingInviteToken};

  /// Safety net for accounts that somehow have no organisation (e.g. created
  /// before auto-provisioning): create one with the user as Owner.
  Future<void> ensureOrganization() async {
    if (!isSignedIn || memberships.isNotEmpty || busy) return;
    final name = (session.name?.trim().length ?? 0) >= 2
        ? session.name!.trim()
        : 'My properties';
    await createOrganization(name);
  }

  // ── Profile & organisations ───────────────────────────────────────────────

  Future<void> loadProfile() async {
    try {
      final data =
          (await api.get('/api/auth/me') as Map).cast<String, dynamic>();
      await applyUser(data, notify: false);
      _setMemberships(data['memberships']);
      await _acceptPendingInvite();
      await _syncActiveOrg();
    } on ApiException catch (e) {
      if (e.statusCode == 401 || e.statusCode == 404) {
        await session.clear();
      }
    } catch (_) {
      // Network failure: keep the stored session and try again later.
    }
    notifyListeners();
  }

  /// Stores updated user details returned by the API (profile saves, email
  /// or phone changes) so the avatar, name and menus refresh everywhere.
  Future<void> applyUser(Map<String, dynamic> user, {bool notify = true}) async {
    account = AccountUser.fromJson(user);
    await session.save(
      token: session.token!,
      name: account.name,
      email: account.email,
      phone: account.phone,
    );
    if (notify) notifyListeners();
  }

  Future<bool> createOrganization(String name) async {
    final ok = await _run(() async {
      final org = (await api.post('/api/orgs', {'name': name}) as Map)
          .cast<String, dynamic>();
      await session.setActiveOrg(org['id'] as int);
      await loadProfile();
      return true;
    });
    return ok ?? false;
  }

  /// Remembers an invite from a link so it's accepted right after sign-in.
  Future<void> rememberInvite(String token) => session.setPendingInvite(token);

  Future<void> _acceptPendingInvite() async {
    final token = session.pendingInviteToken;
    if (token == null || !session.isSignedIn) return;
    try {
      final data =
          (await api.post('/api/invites/accept', {'token': token}) as Map)
              .cast<String, dynamic>();
      _setMemberships(data['memberships']);
      final joined = memberships.isNotEmpty ? memberships.last.orgId : null;
      if (joined != null) await session.setActiveOrg(joined);
      inviteNotice =
          'You joined ${memberships.isNotEmpty ? memberships.last.orgName : 'the organisation'}.';
    } on ApiException catch (e) {
      inviteNotice = e.message;
    } finally {
      await session.setPendingInvite(null);
    }
  }

  /// One-off message about an invite (joined, or why it failed).
  String? inviteNotice;

  void _setMemberships(dynamic raw) {
    memberships = ((raw as List?) ?? const [])
        .map((m) => Membership.fromJson((m as Map).cast<String, dynamic>()))
        .toList();
  }

  Future<void> _syncActiveOrg() async {
    final active = activeMembership;
    if (active?.orgId != session.activeOrgId) {
      await session.setActiveOrg(active?.orgId);
    }
  }

  Future<void> logout() async {
    await session.clear();
    memberships = [];
    account = const AccountUser();
    notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    busy = true;
    error = null;
    suggestedAction = null;
    notifyListeners();
    try {
      return await action();
    } on ApiException catch (e) {
      error = e.message;
      suggestedAction = e.body?['action'] as String?;
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
