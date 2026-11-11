/// Roles in an organisation, mirroring the API's role matrix.
enum OrgRole {
  owner('owner', 'Owner'),
  manager('manager', 'Manager'),
  staff('staff', 'Staff'),
  readOnly('read_only', 'Read-only');

  const OrgRole(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static OrgRole fromApi(String? value) => OrgRole.values
      .firstWhere((r) => r.apiValue == value, orElse: () => OrgRole.readOnly);

  String get description => switch (this) {
        OrgRole.owner => 'Full control, including billing and owners',
        OrgRole.manager =>
          'Runs properties and the team, except owners and billing',
        OrgRole.staff => 'Handles day-to-day bookings and stays',
        OrgRole.readOnly => 'Can view everything but change nothing',
      };
}

class Membership {
  Membership({
    required this.orgId,
    required this.orgName,
    required this.role,
    required this.permissions,
  });

  final int orgId;
  final String orgName;
  final OrgRole role;
  final Set<String> permissions;

  bool can(String permission) => permissions.contains(permission);

  factory Membership.fromJson(Map<String, dynamic> json) {
    return Membership(
      orgId: json['org_id'] as int,
      orgName: (json['org_name'] as String?) ?? '',
      role: OrgRole.fromApi(json['role'] as String?),
      permissions: {
        ...((json['permissions'] as List?) ?? const []).cast<String>()
      },
    );
  }
}

/// Result of asking for an OTP.
class CodeSent {
  CodeSent({
    required this.sentTo,
    required this.resendIn,
    this.devCode,
    this.channel = 'email',
  });

  final String sentTo;
  final int resendIn;

  /// Only present when the API runs without an SMS/email provider (dev).
  final String? devCode;

  /// "email" or "phone": where the OTP was sent.
  final String channel;

  factory CodeSent.fromJson(Map<String, dynamic> json) => CodeSent(
        sentTo: (json['sent_to'] as String?) ?? '',
        resendIn: (json['resend_in'] as int?) ?? 60,
        devCode: json['dev_code'] as String?,
        channel: (json['channel'] as String?) ?? 'email',
      );
}

/// The signed-in user's account details (Account settings).
class AccountUser {
  const AccountUser({
    this.name = '',
    this.email,
    this.phone,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.avatarUrl,
    this.profile = const {},
  });

  final String name;
  final String? email;
  final String? phone;
  final bool emailVerified;
  final bool phoneVerified;

  /// Server path of the profile photo (e.g. /media/avatars/abc.png).
  final String? avatarUrl;

  /// Personal info fields (first_name, last_name, city, about, …).
  final Map<String, dynamic> profile;

  String field(String key) => (profile[key] as String?) ?? '';

  /// Email and phone both confirmed with an OTP.
  bool get verified => emailVerified && phoneVerified;

  factory AccountUser.fromJson(Map<String, dynamic> json) => AccountUser(
        name: (json['name'] as String?) ?? '',
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        emailVerified: (json['email_verified'] as bool?) ?? false,
        phoneVerified: (json['phone_verified'] as bool?) ?? false,
        avatarUrl: json['avatar_url'] as String?,
        profile: ((json['profile'] as Map?) ?? const {}).cast<String, dynamic>(),
      );
}
