import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../account/account_screen.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart' show errorText, showSnack;
import '../bookings/bookings_api.dart' show prettyDate, ymd;
import '../team/team_screen.dart';

/// Host Control Center → Settings (MVP plan §2.9, R1 basic): organisation,
/// property defaults, notifications, payment gateway, security, activity, team.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.auth, required this.membership, this.initialTab = 0});

  final ApiClient api;
  final AuthController auth;
  final Membership membership;
  final int initialTab;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

String _when(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '—';
  return '${prettyDate(ymd(t), year: true)}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

const _policyLabels = {'flexible': 'Flexible', 'moderate': 'Moderate', 'strict': 'Strict', 'non_refundable': 'Non-refundable'};

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? _s;
  String? _error;

  bool get _canEdit => widget.membership.can('org.update');
  bool get _isOwner => widget.membership.can('billing.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/api/settings');
      if (mounted) setState(() => _s = (r as Map).cast());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _save(String path, Map<String, dynamic> body, String done, {bool put = false}) async {
    try {
      put ? await widget.api.put(path, body) : await widget.api.patch(path, body);
      if (mounted) showSnack(context, done);
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (s == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    final tabs = <(String, Widget)>[
      ('Organisation', _OrgTab(key: ValueKey(s['organization']), data: (s['organization'] as Map).cast(), canEdit: _canEdit, api: widget.api, onSave: (b) => _save('/api/settings/organization', b, 'Organisation saved'), onReload: _load)),
      ('Property defaults', _PrefsTab(key: ValueKey(s['preferences']), data: (s['preferences'] as Map).cast(), canEdit: _canEdit, onSave: (b) => _save('/api/settings/preferences', b, 'Defaults saved'))),
      ('Notifications', _NotifTab(data: (s['notifications'] as Map).cast(), kinds: (s['notification_kinds'] as Map).cast(), canEdit: _canEdit, onSave: (b) => _save('/api/settings/notifications', b, 'Notification settings saved'))),
      ('Payments', _GatewayTab(key: ValueKey(s['payment_gateway']), data: (s['payment_gateway'] as Map).cast(), canEdit: _isOwner, onSave: (b) => _save('/api/settings/payment-gateway', b, 'Payment settings saved', put: true))),
      ('Security', _SecurityTab(api: widget.api, auth: widget.auth)),
      ('Activity log', _ActivityTab(api: widget.api)),
      ('Team', TeamPanel(auth: widget.auth, api: widget.api)),
    ];
    return DefaultTabController(
      length: tabs.length,
      initialIndex: widget.initialTab.clamp(0, tabs.length - 1),
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 12, 18, wide ? 32 : 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Settings', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AccountSettingsScreen(auth: widget.auth, api: widget.api))),
              icon: const Icon(Icons.person_outline),
              label: const Text('My profile'),
            ),
          ]),
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [for (final t in tabs) Tab(text: t.$1)]),
          Expanded(child: TabBarView(children: [for (final t in tabs) t.$2])),
        ]),
      ),
    );
  }
}

Widget _section(String title, List<Widget> children, {String? help}) => Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700)),
        if (help != null) Text(help, style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
        const SizedBox(height: 10),
        ...children,
      ]),
    );

Widget _pane(List<Widget> children) => ListView(padding: const EdgeInsets.only(top: 18, bottom: 40), children: [
      Align(alignment: Alignment.topLeft, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 640), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))),
    ]);

class _OrgTab extends StatefulWidget {
  const _OrgTab({super.key, required this.data, required this.canEdit, required this.api, required this.onSave, required this.onReload});

  final Map<String, dynamic> data;
  final bool canEdit;
  final ApiClient api;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final VoidCallback onReload;

  @override
  State<_OrgTab> createState() => _OrgTabState();
}

class _OrgTabState extends State<_OrgTab> {
  late final Map<String, TextEditingController> c = {
    for (final k in ['name', 'legal_name', 'contact_email', 'contact_phone', 'website', 'gstin', 'description']) k: TextEditingController(text: '${widget.data[k] ?? ''}'),
    for (final k in ['line', 'city', 'state', 'postal_code', 'country'])
      'a_$k': TextEditingController(text: '${(widget.data['address_parts'] as Map?)?[k] ?? (k == 'country' ? 'India' : '')}'),
  };

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Widget _f(String k, String label, {int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(key: Key('org-$k'), controller: c[k], enabled: widget.canEdit, maxLines: lines, decoration: InputDecoration(labelText: label)),
      );

  Future<void> _logo() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 600, imageQuality: 90);
    if (f == null) return;
    try {
      await widget.api.post('/api/settings/organization/logo', {'data': base64Encode(await f.readAsBytes())});
      widget.onReload();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final logo = widget.data['logo_url'] as String?;
    return _pane([
      _section('Logo', [
        Row(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppTheme.sage, borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: logo == null ? const Icon(Icons.storefront_outlined, color: AppTheme.forest) : Image.network('${ApiConfig.baseUrl}$logo', fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          if (widget.canEdit) OutlinedButton(onPressed: _logo, child: Text(logo == null ? 'Upload logo' : 'Change logo')),
        ]),
      ]),
      _section('Business', [
        _f('name', 'Business name'),
        _f('legal_name', 'Legal name (for invoices)'),
        _f('gstin', 'GSTIN (optional)'),
        _f('description', 'About the business', lines: 3),
      ]),
      _section('Contact', [_f('contact_email', 'Contact email'), _f('contact_phone', 'Contact phone'), _f('website', 'Website')]),
      _section('Address', [_f('a_line', 'Street address'), _f('a_city', 'City'), _f('a_state', 'State'), _f('a_postal_code', 'PIN code'), _f('a_country', 'Country')]),
      if (widget.canEdit)
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 180,
            child: ElevatedButton(
              key: const Key('save-org'),
              onPressed: () => widget.onSave({
                for (final k in ['name', 'legal_name', 'contact_email', 'contact_phone', 'website', 'gstin', 'description']) k: c[k]!.text,
                'address': {for (final k in ['line', 'city', 'state', 'postal_code', 'country']) k: c['a_$k']!.text},
              }),
              child: const Text('Save'),
            ),
          ),
        ),
    ]);
  }
}

class _PrefsTab extends StatefulWidget {
  const _PrefsTab({super.key, required this.data, required this.canEdit, required this.onSave});

  final Map<String, dynamic> data;
  final bool canEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_PrefsTab> createState() => _PrefsTabState();
}

class _PrefsTabState extends State<_PrefsTab> {
  late String _in = '${widget.data['check_in_time']}';
  late String _out = '${widget.data['check_out_time']}';
  late String _policy = '${widget.data['cancellation_policy']}';
  late bool _incl = widget.data['prices_include_tax'] == true;
  late final _tax = TextEditingController(text: '${widget.data['tax_percent']}');
  late final _adv = TextEditingController(text: '${widget.data['default_advance_percent']}');

  @override
  void dispose() {
    _tax.dispose();
    _adv.dispose();
    super.dispose();
  }

  Future<void> _time(bool checkIn) async {
    final parts = (checkIn ? _in : _out).split(':').map(int.parse).toList();
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: parts[0], minute: parts[1]));
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => checkIn ? _in = v : _out = v);
  }

  @override
  Widget build(BuildContext context) => _pane([
        _section('Check-in and check-out', [
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: widget.canEdit ? () => _time(true) : null, icon: const Icon(Icons.login), label: Text('Check-in from $_in'))),
            const SizedBox(width: 10),
            Expanded(child: OutlinedButton.icon(onPressed: widget.canEdit ? () => _time(false) : null, icon: const Icon(Icons.logout), label: Text('Check-out by $_out'))),
          ]),
        ], help: 'Defaults for new properties and guest messages.'),
        _section('Cancellation policy', [
          DropdownButtonFormField<String>(
            initialValue: _policyLabels.containsKey(_policy) ? _policy : 'flexible',
            items: [for (final e in _policyLabels.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: widget.canEdit ? (v) => setState(() => _policy = v ?? 'flexible') : null,
          ),
        ]),
        _section('Tax and pricing', [
          TextField(
            key: const Key('pref-tax'),
            controller: _tax,
            enabled: widget.canEdit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'GST on room tariff (%)', helperText: 'e.g. 0, 5, 12 or 18 depending on your tariff slab'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _incl,
            onChanged: widget.canEdit ? (v) => setState(() => _incl = v) : null,
            title: const Text('Prices already include tax'),
          ),
          TextField(
            controller: _adv,
            enabled: widget.canEdit,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'Default advance for new properties (%)'),
          ),
        ]),
        if (widget.canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 180,
              child: ElevatedButton(
                key: const Key('save-prefs'),
                onPressed: () => widget.onSave({
                  'check_in_time': _in,
                  'check_out_time': _out,
                  'cancellation_policy': _policy,
                  'tax_percent': double.tryParse(_tax.text) ?? 0,
                  'prices_include_tax': _incl,
                  'default_advance_percent': int.tryParse(_adv.text) ?? 0,
                }),
                child: const Text('Save'),
              ),
            ),
          ),
      ]);
}

class _NotifTab extends StatelessWidget {
  const _NotifTab({required this.data, required this.kinds, required this.canEdit, required this.onSave});

  final Map<String, dynamic> data;
  final Map<String, dynamic> kinds;
  final bool canEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  Widget build(BuildContext context) {
    final events = (data['events'] as Map).cast<String, dynamic>();
    Widget sw(String label, String sub, String key) => SwitchListTile(
          key: Key('notif-$key'),
          contentPadding: EdgeInsets.zero,
          value: data[key] == true,
          onChanged: canEdit ? (v) => onSave({key: v}) : null,
          title: Text(label),
          subtitle: Text(sub),
        );
    return _pane([
      _section('Channels', [
        sw('Email guests', 'Confirmations, payment receipts and cancellations', 'guest_email'),
        sw('SMS guests without email', 'Fallback when a guest has no email or it fails', 'guest_sms'),
        sw('Email the owner and managers', 'Alerts for new bookings, payments and calendar problems', 'owner_email'),
      ]),
      _section('Events', [
        for (final e in kinds.entries)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: events[e.key] != false,
            onChanged: canEdit ? (v) => onSave({'events': {e.key: v == true}}) : null,
            title: Text('${e.value}'),
          ),
      ], help: 'Turned-off events still appear in Inbox → Notifications, but nothing is sent.'),
    ]);
  }
}

class _GatewayTab extends StatefulWidget {
  const _GatewayTab({super.key, required this.data, required this.canEdit, required this.onSave});

  final Map<String, dynamic> data;
  final bool canEdit;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  State<_GatewayTab> createState() => _GatewayTabState();
}

class _GatewayTabState extends State<_GatewayTab> {
  late String _provider = '${widget.data['provider']}';
  late final _keyId = TextEditingController(text: '${widget.data['key_id'] ?? ''}');
  final _secret = TextEditingController();
  final _webhook = TextEditingController();

  @override
  void dispose() {
    _keyId.dispose();
    _secret.dispose();
    _webhook.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final providers = (widget.data['providers'] as Map).cast<String, dynamic>();
    return _pane([
      _section('Online payments on your booking page', [
        RadioGroup<String>(
          groupValue: _provider,
          onChanged: (v) => widget.canEdit ? setState(() => _provider = v ?? 'none') : null,
          child: Column(children: [
            const RadioListTile<String>(contentPadding: EdgeInsets.zero, value: 'none', title: Text('Off — guests send booking requests'), subtitle: Text('You confirm and collect payment yourself')),
            for (final e in providers.entries)
              RadioListTile<String>(key: Key('gw-${e.key}'), contentPadding: EdgeInsets.zero, value: e.key, title: Text('${e.value}'), subtitle: Text(e.key == 'razorpay' ? 'Guests pay online; money goes to your Razorpay account' : 'For trying the flow — no real money moves')),
          ]),
        ),
      ], help: 'Guests are charged the advance % set on each property (or the full amount).'),
      if (_provider == 'razorpay')
        _section('Razorpay keys', [
          TextField(key: const Key('rzp-key'), controller: _keyId, enabled: widget.canEdit, decoration: const InputDecoration(labelText: 'Key ID (rzp_live_… or rzp_test_…)')),
          const SizedBox(height: 10),
          TextField(
            key: const Key('rzp-secret'),
            controller: _secret,
            enabled: widget.canEdit,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Key secret', helperText: widget.data['key_secret_masked'] != null ? 'Saved (${widget.data['key_secret_masked']}). Leave empty to keep.' : null),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _webhook,
            enabled: widget.canEdit,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Webhook secret', helperText: widget.data['has_webhook_secret'] == true ? 'Saved. Leave empty to keep.' : 'Recommended: confirms payments even if the guest closes the page'),
          ),
          const SizedBox(height: 10),
          Text('Webhook URL (Razorpay → Settings → Webhooks, events payment.captured and payment.failed):', style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
          SelectableText('${widget.data['webhook_url']}', style: AppFonts.sans(fontSize: 13)),
          if (widget.data['verified_at'] != null) Text('Keys verified ${_when(widget.data['verified_at'] as String?)}', style: AppFonts.sans(fontSize: 13, color: AppTheme.success)),
        ], help: 'Find these in your Razorpay Dashboard → Account & Settings → API keys. The secret is stored encrypted and never shown again.'),
      if (!widget.canEdit) Text('Only the owner can change payment settings.', style: AppFonts.sans(color: AppTheme.muted)),
      if (widget.canEdit)
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: 200,
            child: ElevatedButton(
              key: const Key('save-gateway'),
              onPressed: () => widget.onSave({
                'provider': _provider,
                if (_provider == 'razorpay') ...{
                  'key_id': _keyId.text.trim(),
                  if (_secret.text.trim().isNotEmpty) 'key_secret': _secret.text.trim(),
                  if (_webhook.text.trim().isNotEmpty) 'webhook_secret': _webhook.text.trim(),
                },
              }),
              child: Text(_provider == 'razorpay' ? 'Verify and save' : 'Save'),
            ),
          ),
        ),
    ]);
  }
}

class _SecurityTab extends StatefulWidget {
  const _SecurityTab({required this.api, required this.auth});

  final ApiClient api;
  final AuthController auth;

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  List<Map>? _sessions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.get('/api/account/sessions');
    if (mounted) setState(() => _sessions = (r as List).cast<Map>());
  }

  Future<void> _signOut(Map s) async {
    await widget.api.delete('/api/account/sessions/${s['id']}');
    if (s['current'] == true) {
      await widget.auth.logout();
      return;
    }
    if (mounted) showSnack(context, 'Signed out of ${s['device']}');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _sessions;
    if (list == null) return const Center(child: CircularProgressIndicator());
    final active = list.where((s) => s['active'] == true).toList();
    return _pane([
      _section('Active sessions', [
        for (final s in active)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(s['device'].toString().contains('Android') || s['device'].toString().contains('iOS') ? Icons.phone_iphone : Icons.computer),
            title: Text('${s['device']}${s['current'] == true ? ' · this device' : ''}'),
            subtitle: Text('Signed in ${_when(s['created_at'] as String?)} · last active ${_when(s['last_seen_at'] as String?)}${s['ip'] != null ? ' · ${s['ip']}' : ''}'),
            trailing: TextButton(onPressed: () => _signOut(s), child: const Text('Sign out')),
          ),
        if (active.length > 1)
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () async {
                await widget.api.post('/api/account/sessions/sign-out-others', {});
                if (!context.mounted) return;
                showSnack(context, 'Signed out of other devices');
                _load();
              },
              child: const Text('Sign out of all other devices'),
            ),
          ),
      ], help: 'Sign out of anything you don\'t recognise.'),
      _section('Sign-in history', [
        for (final s in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('${_when(s['created_at'] as String?)} · ${s['device']} · ${s['method'] == 'signup' ? 'account created' : 'signed in'}${s['revoked_at'] != null ? ' · signed out ${_when(s['revoked_at'] as String?)}' : ''}',
                style: AppFonts.sans(fontSize: 13.5)),
          ),
      ]),
    ]);
  }
}

class _ActivityTab extends StatefulWidget {
  const _ActivityTab({required this.api});

  final ApiClient api;

  @override
  State<_ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<_ActivityTab> {
  Map<String, dynamic>? _d;
  final _q = TextEditingController();
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final r = await widget.api.get('/api/settings/activity?page=$_page&q=${Uri.encodeQueryComponent(_q.text.trim())}');
    if (mounted) setState(() => _d = (r as Map).cast());
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    final items = ((d?['items'] as List?) ?? const []).cast<Map>();
    return _pane([
      TextField(
        controller: _q,
        onSubmitted: (_) {
          _page = 1;
          _load();
        },
        decoration: const InputDecoration(hintText: 'Search actions or people', prefixIcon: Icon(Icons.search), isDense: true),
      ),
      const SizedBox(height: 10),
      if (d == null) const Center(child: CircularProgressIndicator()),
      if (d != null && items.isEmpty) Text('No activity yet.', style: AppFonts.sans(color: AppTheme.muted)),
      for (final a in items)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history, size: 18),
          title: Text('${a['action']}'),
          subtitle: Text('${a['user_name']} · ${_when(a['at'] as String?)}'),
        ),
      if (d != null && (d['total'] as int) > 50)
        Row(children: [
          IconButton(
              onPressed: _page > 1
                  ? () {
                      _page--;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_left)),
          Text('Page $_page'),
          IconButton(
              onPressed: _page * 50 < (d['total'] as int)
                  ? () {
                      _page++;
                      _load();
                    }
                  : null,
              icon: const Icon(Icons.chevron_right)),
        ]),
    ]);
  }
}
