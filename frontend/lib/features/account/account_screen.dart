import 'package:flutter/material.dart';
import 'package:bleiben/core/theme/app_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../home/home_content.dart';
import '../home/home_nav.dart';
import '../home/home_overlays.dart';
import '../home/home_sections.dart' show BleibenWordmark;
import '../home/home_widgets.dart';
import '../team/team_screen.dart';
import 'account_controller.dart';

enum AccountSection { personal, verification, team }

const _fieldFill = Colors.white;

/// Account settings (homyhuts /account/profile-info and /account/verification)
/// plus Team & roles for the user's organisation (PRD AUTH-2).
class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({
    super.key,
    required this.auth,
    required this.api,
    this.initial = AccountSection.personal,
  });

  final AuthController auth;
  final ApiClient api;
  final AccountSection initial;

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late final AccountController _account =
      AccountController(api: widget.api, auth: widget.auth);
  late AccountSection _section = widget.initial;

  AuthController get auth => widget.auth;

  @override
  void initState() {
    super.initState();
    // Accounts without an organisation (created before auto-provisioning)
    // get one, so Team & roles always has somewhere to live.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (auth.memberships.isEmpty) auth.ensureOrganization();
    });
  }

  @override
  void dispose() {
    _account.dispose();
    super.dispose();
  }

  Future<void> _openMenu() async {
    final action = await showAccountSheet(context,
        signedIn: true, displayName: auth.displayName);
    if (action == AccountAction.logout) await auth.logout();
    // Account settings: already here. Everything else is a placeholder.
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: auth,
      builder: (context, _) {
        final wide = MediaQuery.sizeOf(context).width >= 900;
        final sidebar = _Sidebar(
          selected: _section,
          verified: auth.account.verified,
          showTeam: auth.activeMembership != null,
          onBack: () => Navigator.of(context).maybePop(),
          onSelect: (s) => setState(() => _section = s),
        );
        final content = _ContentCard(
          child: switch (_section) {
            AccountSection.personal =>
              _PersonalInfo(auth: auth, account: _account),
            AccountSection.verification => _Verification(
                auth: auth,
                account: _account,
                onOpenPersonal: () =>
                    setState(() => _section = AccountSection.personal)),
            AccountSection.team => auth.activeMembership == null
                ? const Center(child: CircularProgressIndicator())
                : _TeamAndRoles(auth: auth, account: _account, api: widget.api),
          },
        );

        return Scaffold(
          backgroundColor: AppTheme.paper,
          body: Column(
            children: [
              _TopBar(
                initial: _initialOf(auth.displayName),
                onLogo: () => Navigator.of(context).maybePop(),
                onMenu: _openMenu,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                      horizontal: wide ? 32 : 16, vertical: wide ? 40 : 20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1140),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(width: 304, child: sidebar),
                                const SizedBox(width: 60),
                                Expanded(child: content),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                sidebar,
                                const SizedBox(height: 20),
                                content,
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

String? _initialOf(String name) {
  final n = name.trim();
  return n.isEmpty ? null : n[0].toUpperCase();
}

// ── Chrome ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.initial, required this.onLogo, required this.onMenu});

  final String? initial;
  final VoidCallback onLogo;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return SafeArea(
      bottom: false,
      child: Container(
        height: 72,
        padding: EdgeInsets.symmetric(horizontal: wide ? 48 : 16),
        decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: HomeColors.line))),
        child: Row(
          children: [
            InkWell(
              onTap: onLogo,
              borderRadius: BorderRadius.circular(12),
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: BleibenWordmark(),
              ),
            ),
            const Spacer(),
            // Placeholder for now, like the rest of the menu.
            if (wide)
              Padding(
                padding: const EdgeInsets.only(right: 24),
                child: Text('List Your Property',
                    style: AppFonts.sans(
                        fontSize: 15, fontWeight: FontWeight.w500)),
              ),
            AccountMenuButton(onPressed: onMenu, initial: initial),
          ],
        ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selected,
    required this.verified,
    required this.showTeam,
    required this.onBack,
    required this.onSelect,
  });

  final AccountSection selected;
  final bool verified;
  final bool showTeam;
  final VoidCallback onBack;
  final ValueChanged<AccountSection> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(AccountSection s, IconData icon, String label, {Widget? badge}) {
      final active = s == selected;
      return Material(
        color: active ? AppTheme.sage : Colors.transparent,
        child: InkWell(
          onTap: () => onSelect(s),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Row(
              children: [
                Icon(icon, size: 24, color: AppTheme.ink),
                const SizedBox(width: 18),
                Expanded(
                  child: Text(label,
                      style: AppFonts.sans(fontSize: 16.5)),
                ),
                if (badge != null) badge,
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onBack,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 20, 18),
              child: Row(children: [
                const Icon(Icons.chevron_left_rounded, size: 26),
                const SizedBox(width: 8),
                Flexible(
                  child: Text('Account Settings',
                      overflow: TextOverflow.ellipsis,
                      style: AppFonts.sans(
                          fontSize: 17, fontWeight: FontWeight.w500)),
                ),
              ]),
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
          item(AccountSection.personal, Icons.person_outline_rounded,
              'Personal info'),
          item(
            AccountSection.verification,
            Icons.assignment_ind_outlined,
            'Account Verifications',
            badge: _StatusBadge(verified: verified),
          ),
          if (showTeam)
            item(AccountSection.team, Icons.groups_2_outlined,
                'Team & roles'),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: verified ? AppTheme.success : AppTheme.danger,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(verified ? 'Verified' : 'Pending',
          style: AppFonts.sans(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Container(
      padding: EdgeInsets.all(wide ? 26 : 18),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      // Grey filled fields on the white card, as in the reference.
      child: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: Theme.of(context).inputDecorationTheme.copyWith(
                fillColor: _fieldFill,
              ),
        ),
        child: child,
      ),
    );
  }
}

TextStyle _heading() =>
    AppFonts.sans(fontSize: 21, fontWeight: FontWeight.w600);

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

// ── Personal info ────────────────────────────────────────────────────────────

const _textKeys = [
  'first_name',
  'last_name',
  'preferred_name',
  'date_of_birth',
  'address1',
  'address2',
  'city',
  'pincode',
  'profession',
  'hobbies',
  'pet_name',
  'languages',
  'school',
  'about',
];

const _indianStates = [
  'Andaman and Nicobar Islands', 'Andhra Pradesh', 'Arunachal Pradesh', //
  'Assam', 'Bihar', 'Chandigarh', 'Chhattisgarh',
  'Dadra and Nagar Haveli and Daman and Diu', 'Delhi', 'Goa', 'Gujarat',
  'Haryana', 'Himachal Pradesh', 'Jammu and Kashmir', 'Jharkhand',
  'Karnataka', 'Kerala', 'Ladakh', 'Lakshadweep', 'Madhya Pradesh',
  'Maharashtra', 'Manipur', 'Meghalaya', 'Mizoram', 'Nagaland', 'Odisha',
  'Puducherry', 'Punjab', 'Rajasthan', 'Sikkim', 'Tamil Nadu', 'Telangana',
  'Tripura', 'Uttar Pradesh', 'Uttarakhand', 'West Bengal',
];

class _PersonalInfo extends StatefulWidget {
  const _PersonalInfo({required this.auth, required this.account});

  final AuthController auth;
  final AccountController account;

  @override
  State<_PersonalInfo> createState() => _PersonalInfoState();
}

class _PersonalInfoState extends State<_PersonalInfo> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _c;
  String? _country;
  String? _state;
  late bool _emailNotifications;

  AccountUser get _user => widget.auth.account;

  @override
  void initState() {
    super.initState();
    final user = _user;
    final names = user.name.trim().split(RegExp(r'\s+'));
    _c = {
      for (final k in _textKeys) k: TextEditingController(text: user.field(k)),
    };
    // Accounts from sign-up only have a full name: split it once.
    if (_c['first_name']!.text.isEmpty && names.first.isNotEmpty) {
      _c['first_name']!.text = names.first;
      _c['last_name']!.text = names.skip(1).join(' ');
    }
    _country = user.field('country').isEmpty ? null : user.field('country');
    _state = _indianStates.contains(user.field('state')) ? user.field('state') : null;
    _emailNotifications = user.profile['email_notifications'] != false;
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final error = await widget.account.saveProfile({
      for (final e in _c.entries) e.key: e.value.text.trim(),
      'country': _country ?? '',
      'state': _state ?? '',
      'email_notifications': _emailNotifications,
    });
    if (mounted) _snack(context, error ?? 'Changes saved');
  }

  Future<void> _pickPhoto() async {
    final file = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (file == null) return;
    final error = await widget.account.uploadAvatar(await file.readAsBytes());
    if (mounted) _snack(context, error ?? 'Profile photo updated');
  }

  Future<void> _pickDob() async {
    final now = DateTime.now();
    final current = DateTime.tryParse(_c['date_of_birth']!.text);
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime(now.year - 25),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      _c['date_of_birth']!.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _editContact(String channel) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => ContactDialog(account: widget.account, channel: channel),
    );
    if (ok == true && mounted) {
      _snack(context, channel == 'email' ? 'Email updated' : 'Phone number verified');
    }
  }

  Widget _field(String key, String label,
      {String? Function(String?)? validator,
      TextInputType? keyboard,
      int maxLines = 1,
      int? maxLength,
      bool readOnly = false,
      VoidCallback? onTap,
      Widget? suffix}) {
    return TextFormField(
      key: ValueKey('field-$key'),
      controller: _c[key],
      validator: validator,
      keyboardType: keyboard,
      maxLines: maxLines,
      maxLength: maxLength,
      readOnly: readOnly,
      onTap: onTap,
      decoration: InputDecoration(labelText: label, suffixIcon: suffix),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    final initial = _initialOf(widget.auth.displayName);
    return LayoutBuilder(builder: (context, constraints) {
      final two = constraints.maxWidth >= 560;
      Widget pair(Widget a, Widget b) => two
          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: a),
              const SizedBox(width: 24),
              Expanded(child: b),
            ])
          : Column(children: [a, const SizedBox(height: 16), b]);
      const gap = SizedBox(height: 18);

      return Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text('Personal Info', style: _heading()),
                  ),
                ),
                _AvatarEditor(
                  initial: initial,
                  avatarUrl: user.avatarUrl,
                  busy: widget.account.saving,
                  onEdit: _pickPhoto,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ContactRow(
              label: 'Email',
              value: user.email ?? '',
              note: user.email != null && !user.emailVerified ? 'Not verified' : null,
              action: 'Edit',
              onAction: () => _editContact('email'),
            ),
            const Divider(height: 1),
            _ContactRow(
              label: 'Phone Number',
              value: user.phone ?? '+91',
              note: user.phone != null && !user.phoneVerified ? 'Not verified' : null,
              action: user.phone == null ? 'Add' : 'Edit',
              onAction: () => _editContact('phone'),
            ),
            const Divider(height: 1),
            const SizedBox(height: 22),
            pair(
              _field('first_name', 'First Name *', validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return 'First name is required';
                if (!RegExp(r'^[a-zA-Z]+(\s[a-zA-Z]+)*$').hasMatch(t)) {
                  return 'Only alphabets are allowed';
                }
                return null;
              }),
              _field('last_name', 'Last Name', validator: (v) {
                final t = (v ?? '').trim();
                return t.isEmpty || RegExp(r'^[a-zA-Z]+(\s[a-zA-Z]+)*$').hasMatch(t)
                    ? null
                    : 'Only alphabets are allowed';
              }),
            ),
            gap,
            pair(
              _field('preferred_name', 'Preferred Name'),
              _field('date_of_birth', 'Date of Birth',
                  readOnly: true,
                  onTap: _pickDob,
                  suffix: const Icon(Icons.calendar_month_outlined)),
            ),
            gap,
            pair(_field('address1', 'Address1'), _field('address2', 'Address2')),
            gap,
            pair(
              DropdownButtonFormField<String>(
                key: const ValueKey('field-country'),
                initialValue: _country,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Select Country'),
                items: const [
                  DropdownMenuItem(value: 'India', child: Text('India')),
                ],
                onChanged: (v) => setState(() => _country = v),
              ),
              DropdownButtonFormField<String>(
                key: const ValueKey('field-state'),
                initialValue: _state,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Select State'),
                items: [
                  for (final s in _indianStates)
                    DropdownMenuItem(value: s, child: Text(s, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _state = v),
              ),
            ),
            gap,
            pair(
              _field('city', 'City'),
              _field('pincode', 'Pincode',
                  keyboard: TextInputType.number,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    return t.isEmpty || RegExp(r'^\d{6}$').hasMatch(t)
                        ? null
                        : 'Pincode should be 6 digits';
                  }),
            ),
            const SizedBox(height: 26),
            Text(
              'Share a little more about yourself. Only hosts of your confirmed bookings can see this, and you can see theirs too.',
              style: AppFonts.sans(color: HomeColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 16),
            pair(_field('profession', 'Profession'), _field('hobbies', 'Hobbies')),
            gap,
            pair(_field('pet_name', 'Pet Name'),
                _field('languages', 'Known Languages')),
            gap,
            _field('school', 'Where did I go to school?'),
            gap,
            Text('About yourself',
                style: AppFonts.sans(fontSize: 15, fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _field('about', 'About yourself (Max 500 characters)',
                maxLines: 4, maxLength: 500),
            const SizedBox(height: 12),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _emailNotifications,
              activeThumbColor: AppTheme.forest,
              onChanged: (v) => setState(() => _emailNotifications = v),
              title: Text('Email notifications',
                  style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w500)),
              subtitle: const Text('Booking updates and account alerts by email'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton(
                onPressed: widget.account.saving ? null : _save,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(180, 50),
                    backgroundColor: AppTheme.ink),
                child: Text(widget.account.saving ? 'Saving…' : 'Save changes'),
              ),
            ),
          ],
        ),
      );
    });
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.initial,
    required this.avatarUrl,
    required this.busy,
    required this.onEdit,
  });

  final String? initial;
  final String? avatarUrl;
  final bool busy;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 84,
      height: 92,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: AppTheme.ink,
            foregroundImage: avatarUrl == null
                ? null
                : NetworkImage(AccountController.mediaUrl(avatarUrl!)),
            child: Text(initial ?? '',
                style: const TextStyle(
                    color: Colors.white, fontSize: 32, fontWeight: FontWeight.w500)),
          ),
          Positioned(
            bottom: 0,
            child: Material(
              color: Colors.white,
              elevation: 2,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: busy ? null : onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.photo_camera_rounded, size: 14),
                    const SizedBox(width: 4),
                    Text('Edit',
                        semanticsLabel: 'Change profile photo',
                        style: AppFonts.sans(fontSize: 13, fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.label,
    required this.value,
    required this.action,
    required this.onAction,
    this.note,
  });

  final String label;
  final String value;
  final String action;
  final VoidCallback onAction;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppFonts.sans(fontSize: 17, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: AppFonts.sans(fontSize: 16)),
                if (note != null)
                  Text(note!,
                      style: AppFonts.sans(fontSize: 12.5, color: HomeColors.danger)),
              ],
            ),
          ),
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: AppTheme.ink),
            child: Text(action,
                semanticsLabel: '$action $label',
                style: AppFonts.sans(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline)),
          ),
        ],
      ),
    );
  }
}

/// Change email / add phone: enter the new value, get an OTP on it, verify.
class ContactDialog extends StatefulWidget {
  const ContactDialog({super.key, required this.account, required this.channel});

  final AccountController account;

  /// "email" or "phone".
  final String channel;

  @override
  State<ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<ContactDialog> {
  final _value = TextEditingController();
  final _code = TextEditingController();
  CodeSent? _sent;
  String? _error;
  bool _busy = false;

  bool get _isEmail => widget.channel == 'email';

  @override
  void initState() {
    super.initState();
    final user = widget.account.auth.account;
    // Re-verifying an unconfirmed value: start from it.
    if (_isEmail && user.email != null && !user.emailVerified) _value.text = user.email!;
    if (!_isEmail && user.phone != null && !user.phoneVerified) {
      _value.text = user.phone!.replaceFirst('+91', '');
    }
  }

  @override
  void dispose() {
    _value.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final (sent, error) =
        await widget.account.requestContactOtp(widget.channel, _value.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _sent = sent;
      _error = error;
    });
  }

  Future<void> _verify() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await widget.account
        .verifyContactOtp(widget.channel, _value.text.trim(), _code.text.trim());
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sent = _sent;
    return AlertDialog(
      title: Text(sent != null
          ? 'Enter OTP'
          : _isEmail
              ? 'Change email'
              : 'Add phone number'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sent == null)
              TextField(
                controller: _value,
                autofocus: true,
                keyboardType: _isEmail ? TextInputType.emailAddress : TextInputType.phone,
                decoration: InputDecoration(
                  labelText: _isEmail ? 'New email address' : 'Phone number',
                  prefixText: _isEmail ? null : '+91 ',
                ),
                onSubmitted: (_) => _send(),
              )
            else ...[
              Text('Please enter the OTP sent to ${sent.sentTo}'),
              const SizedBox(height: 12),
              TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(labelText: '6-digit OTP', counterText: ''),
                onSubmitted: (_) => _verify(),
              ),
              if (sent.devCode != null)
                Text('Dev mode: your OTP is ${sent.devCode}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.muted)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: const TextStyle(color: HomeColors.danger)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
          onPressed: _busy ? null : (sent == null ? _send : _verify),
          child: Text(sent == null ? 'Send OTP' : 'Verify'),
        ),
      ],
    );
  }
}

// ── Account verification ─────────────────────────────────────────────────────

class _Verification extends StatelessWidget {
  const _Verification({
    required this.auth,
    required this.account,
    required this.onOpenPersonal,
  });

  final AuthController auth;
  final AccountController account;
  final VoidCallback onOpenPersonal;

  @override
  Widget build(BuildContext context) {
    final user = auth.account;

    Future<void> verify(String channel) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => ContactDialog(account: account, channel: channel),
      );
      if (ok == true && context.mounted) _snack(context, 'Verified');
    }

    Widget check(String title, String subtitle, bool done,
        {String? action, VoidCallback? onAction}) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          color: done ? HomeColors.success : HomeColors.muted,
        ),
        title: Text(title, style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle),
        trailing: done || action == null
            ? null
            : OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                child: Text(action),
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(child: Text('Account Verification', style: _heading())),
          _StatusBadge(verified: user.verified),
        ]),
        const SizedBox(height: 22),
        Text('Verify your identity',
            style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(
          'A quick, one-time check that keeps Bleiben safe for hosts and guests.',
          style: AppFonts.sans(color: HomeColors.muted, fontSize: 15),
        ),
        const SizedBox(height: 14),
        check(
          'Email address',
          user.email ?? 'No email on your account',
          user.emailVerified,
          action: 'Verify',
          onAction: () => verify('email'),
        ),
        const Divider(height: 1),
        check(
          'Phone number',
          user.phone ?? 'Add a phone number and confirm it with an OTP',
          user.phoneVerified,
          action: user.phone == null ? 'Add' : 'Verify',
          onAction: () => verify('phone'),
        ),
        const Divider(height: 1),
        check(
          'Government ID',
          'ID card and selfie check — coming soon',
          false,
        ),
      ],
    );
  }
}

// ── Team & roles (organisation settings) ─────────────────────────────────────

class _TeamAndRoles extends StatelessWidget {
  const _TeamAndRoles({required this.auth, required this.account, required this.api});

  final AuthController auth;
  final AccountController account;
  final ApiClient api;

  Future<void> _rename(BuildContext context, Membership m) async {
    final controller = TextEditingController(text: m.orgName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Organisation name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(minimumSize: const Size(100, 44)),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name == m.orgName) return;
    final error = await account.renameOrganization(m.orgId, name);
    if (context.mounted) _snack(context, error ?? 'Organisation renamed');
  }

  @override
  Widget build(BuildContext context) {
    final m = auth.activeMembership!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Team & roles', style: _heading()),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Organisation',
                      style: AppFonts.sans(fontSize: 17, fontWeight: FontWeight.w500)),
                  Text(m.orgName, style: AppFonts.sans(fontSize: 16)),
                  Text('Your role: ${m.role.label}',
                      style: AppFonts.sans(color: HomeColors.muted, fontSize: 14)),
                ],
              ),
            ),
            if (m.can('org.update'))
              TextButton(
                onPressed: () => _rename(context, m),
                style: TextButton.styleFrom(foregroundColor: AppTheme.ink),
                child: Text('Edit',
                    semanticsLabel: 'Edit organisation name',
                    style: AppFonts.sans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline)),
              ),
          ],
        ),
        const SizedBox(height: 14),
        const Divider(height: 1),
        const SizedBox(height: 14),
        Text('Roles', style: AppFonts.sans(fontSize: 17, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final r in OrgRole.values)
              Container(
                width: 250,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: r == m.role ? AppTheme.forest.withValues(alpha: 0.07) : _fieldFill,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.label,
                        style: AppFonts.sans(fontSize: 15, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(r.description,
                        style: AppFonts.sans(fontSize: 13, color: HomeColors.muted)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 18),
        TeamPanel(key: ValueKey('team-${m.orgId}'), auth: auth, api: api),
      ],
    );
  }
}
