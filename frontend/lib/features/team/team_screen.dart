import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

class TeamMember {
  TeamMember.fromJson(Map<String, dynamic> json)
      : id = json['id'] as int,
        role = OrgRole.fromApi(json['role'] as String?),
        status = json['status'] as String,
        expired = (json['expired'] as bool?) ?? false,
        name = ((json['user'] as Map?)?['name'] as String?) ?? '',
        email = ((json['user'] as Map?)?['email'] as String?) ??
            json['invited_email'] as String?,
        phone = (json['user'] as Map?)?['phone'] as String?;

  final int id;
  final OrgRole role;
  final String status;
  final bool expired;
  final String name;
  final String? email;
  final String? phone;

  String get displayName =>
      name.isNotEmpty ? name : (email ?? phone ?? 'Member');
}

/// Members and pending invites of the active organisation, with role
/// changes and invites for roles that may manage the team (PRD AUTH-2:
/// Owner, Manager, Staff, Read-only). Used in Account settings → Team & roles.
class TeamPanel extends StatefulWidget {
  const TeamPanel({super.key, required this.auth, required this.api});

  final AuthController auth;
  final ApiClient api;

  @override
  State<TeamPanel> createState() => _TeamPanelState();
}

class _TeamPanelState extends State<TeamPanel> {
  List<TeamMember> _members = [];
  bool _loading = true;
  String? _error;

  Membership get _me => widget.auth.activeMembership!;
  bool get _canManage => _me.can('team.manage');
  bool get _canGrantOwner => _me.can('team.assign_owner');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list =
          await widget.api.get('/api/orgs/${_me.orgId}/members') as List;
      _members = list
          .map((m) => TeamMember.fromJson((m as Map).cast<String, dynamic>()))
          .toList();
    } on ApiException catch (e) {
      _error = e.message;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _guard(Future<void> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      await _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  List<OrgRole> get _assignable => [
        if (_canGrantOwner) OrgRole.owner,
        OrgRole.manager,
        OrgRole.staff,
        OrgRole.readOnly,
      ];

  bool _canTouch(TeamMember m) =>
      _canManage && (m.role != OrgRole.owner || _canGrantOwner);

  Future<void> _invite() async {
    final result = await showDialog<(String, OrgRole)>(
      context: context,
      builder: (_) => _InviteDialog(roles: _assignable),
    );
    if (result == null) return;
    await _guard(
      () => widget.api.post('/api/orgs/${_me.orgId}/invites',
          {'email': result.$1, 'role': result.$2.apiValue}),
      'Invite sent to ${result.$1}',
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Column(children: [
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Retry')),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('Team members (${_members.length})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            if (_canManage)
              ElevatedButton.icon(
                onPressed: _invite,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: const EdgeInsets.symmetric(horizontal: 16)),
                icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                label: const Text('Invite member'),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _canManage
              ? 'Invite managers, staff or read-only members by email and choose what they can do.'
              : 'Only owners and managers can invite people or change roles.',
          style: const TextStyle(color: AppTheme.muted, fontSize: 13),
        ),
        const SizedBox(height: 12),
        for (final m in _members) _memberTile(m),
      ],
    );
  }

  Widget _memberTile(TeamMember m) {
    final pending = m.status == 'invited';
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.forest.withValues(alpha: 0.1),
          child: Text(m.displayName.characters.first.toUpperCase(),
              style: const TextStyle(
                  color: AppTheme.forest, fontWeight: FontWeight.w700)),
        ),
        title: Text(m.displayName),
        subtitle: Text([
          if (m.email != null && m.name.isNotEmpty) m.email!,
          if (pending) m.expired ? 'Invite expired' : 'Invite sent',
        ].join(' · ')),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Chip(
                label: Text(m.role.label),
                visualDensity: VisualDensity.compact),
            if (_canTouch(m))
              PopupMenuButton<String>(
                tooltip: 'Manage ${m.displayName}',
                itemBuilder: (_) => [
                  for (final r in _assignable)
                    if (r != m.role)
                      PopupMenuItem(
                          value: 'role:${r.apiValue}',
                          child: Text('Make ${r.label}')),
                  if (pending)
                    const PopupMenuItem(
                        value: 'resend', child: Text('Resend invite')),
                  PopupMenuItem(
                      value: 'remove',
                      child:
                          Text(pending ? 'Cancel invite' : 'Remove from team')),
                ],
                onSelected: (v) async {
                  if (v.startsWith('role:')) {
                    final role = OrgRole.fromApi(v.substring(5));
                    await _guard(
                      () => widget.api.patch(
                          '/api/orgs/${_me.orgId}/members/${m.id}',
                          {'role': role.apiValue}),
                      '${m.displayName} is now ${role.label}',
                    );
                  } else if (v == 'resend' && m.email != null) {
                    await _guard(
                      () => widget.api.post('/api/orgs/${_me.orgId}/invites',
                          {'email': m.email, 'role': m.role.apiValue}),
                      'Invite re-sent to ${m.email}',
                    );
                  } else if (v == 'remove') {
                    await _guard(
                      () => widget.api
                          .delete('/api/orgs/${_me.orgId}/members/${m.id}'),
                      pending ? 'Invite cancelled' : '${m.displayName} removed',
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _InviteDialog extends StatefulWidget {
  const _InviteDialog({required this.roles});

  final List<OrgRole> roles;

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _key = GlobalKey<FormState>();
  final _email = TextEditingController();
  OrgRole _role = OrgRole.staff;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite to team'),
      content: Form(
        key: _key,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[a-zA-Z]{2,}$')
                      .hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a valid email',
            ),
            const SizedBox(height: 12),
            RadioGroup<OrgRole>(
              groupValue: _role,
              onChanged: (v) => setState(() => _role = v ?? OrgRole.staff),
              child: Column(
                children: [
                  for (final r in widget.roles)
                    RadioListTile<OrgRole>(
                      value: r,
                      title: Text(r.label),
                      subtitle: Text(r.description,
                          style: const TextStyle(fontSize: 12)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(120, 44)),
          onPressed: () {
            if (_key.currentState!.validate()) {
              Navigator.pop(context, (_email.text.trim(), _role));
            }
          },
          child: const Text('Send invite'),
        ),
      ],
    );
  }
}
