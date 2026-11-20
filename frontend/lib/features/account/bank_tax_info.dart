import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/input_rules.dart';

/// Account settings → Bank Account and Tax Info: where this organisation gets
/// paid (bank transfer + UPI) and its tax details. Used when recording UPI /
/// bank payments and, when online payments are off, shown to guests so they
/// can pay the host directly after a booking request.
class BankTaxInfoSection extends StatefulWidget {
  const BankTaxInfoSection({super.key, required this.api});

  final ApiClient api;

  @override
  State<BankTaxInfoSection> createState() => _BankTaxInfoSectionState();
}

class _BankTaxInfoSectionState extends State<BankTaxInfoSection> {
  final _form = GlobalKey<FormState>();
  final _bank = TextEditingController();
  final _beneficiary = TextEditingController();
  final _account = TextEditingController();
  final _confirm = TextEditingController();
  final _ifsc = TextEditingController();
  final _gstin = TextEditingController();
  final _gstName = TextEditingController();
  final _pan = TextEditingController();
  final _upi = TextEditingController();
  String _type = 'savings';
  bool _share = true;
  Map<String, dynamic>? _data;
  String? _error;
  bool _saving = false;

  bool get _canEdit => _data?['can_edit'] == true;
  bool get _hasAccount => _data?['account_number_masked'] != null;
  bool get _hasPan => _data?['pan_masked'] != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_bank, _beneficiary, _account, _confirm, _ifsc, _gstin, _gstName, _pan, _upi]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = (await widget.api.get('/api/settings/payout') as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _data = d;
        _error = null;
        _bank.text = '${d['bank_name'] ?? ''}';
        _beneficiary.text = '${d['beneficiary_name'] ?? ''}';
        _ifsc.text = '${d['ifsc'] ?? ''}';
        _gstin.text = '${d['gstin'] ?? ''}';
        _gstName.text = '${d['gst_business_name'] ?? ''}';
        _upi.text = '${d['upi_id'] ?? ''}';
        _type = (d['account_type'] as String?) ?? 'savings';
        _share = d['share_with_guests'] != false;
        _account.clear();
        _confirm.clear();
        _pan.clear();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final d = await widget.api.put('/api/settings/payout', {
        'bank_name': _bank.text.trim(),
        'beneficiary_name': _beneficiary.text.trim(),
        if (_account.text.trim().isNotEmpty) 'account_number': _account.text.trim(),
        if (_account.text.trim().isNotEmpty) 'confirm_account_number': _confirm.text.trim(),
        'ifsc': _ifsc.text.trim(),
        'account_type': _type,
        'gstin': _gstin.text.trim(),
        'gst_business_name': _gstName.text.trim(),
        if (_pan.text.trim().isNotEmpty) 'pan': _pan.text.trim(),
        'upi_id': _upi.text.trim(),
        'share_with_guests': _share,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank account and tax info saved')));
      setState(() => _data = (d as Map).cast<String, dynamic>());
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label, {bool required = false, String? helper, String? hint}) => InputDecoration(
        label: Text.rich(TextSpan(children: [
          TextSpan(text: label),
          if (required) const TextSpan(text: ' *', style: TextStyle(color: AppTheme.danger)),
        ])),
        helperText: helper,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFF4F4F2),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      );

  @override
  Widget build(BuildContext context) {
    if (_error != null) return Text(_error!, style: AppFonts.sans(color: AppTheme.danger));
    final d = _data;
    if (d == null) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    final types = ((d['account_types'] as Map?) ?? const {'savings': 'Savings', 'current': 'Current'}).cast<String, String>();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    Widget pair(Widget a, Widget b) => wide
        ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: a), const SizedBox(width: 20), Expanded(child: b)])
        : Column(children: [a, const SizedBox(height: 16), b]);
    const gap = SizedBox(height: 16);
    final ro = !_canEdit;
    return Form(
      key: _form,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Bank Account And Tax Info', style: AppFonts.sans(fontSize: 26, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('Where you receive money from guests. Used when you record UPI or bank-transfer payments, and shown to guests to pay you directly when online payments are off.',
            style: AppFonts.sans(color: AppTheme.muted)),
        if (ro)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Only an owner or manager can change these details.', style: AppFonts.sans(color: AppTheme.warningInk)),
          ),
        const SizedBox(height: 24),
        pair(
          TextFormField(
            key: const Key('payout-bank'),
            controller: _bank,
            readOnly: ro,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r"[A-Za-z .&'\-]")), LengthLimitingTextInputFormatter(80)],
            decoration: _dec('Bank Name', required: true, hint: 'e.g. HDFC Bank'),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter the bank name' : null,
          ),
          TextFormField(
            key: const Key('payout-beneficiary'),
            controller: _beneficiary,
            readOnly: ro,
            inputFormatters: InputRules.name,
            textCapitalization: TextCapitalization.words,
            decoration: _dec('Beneficiary Name', required: true, hint: 'As on the bank account'),
            validator: (v) => InputRules.requiredName(v, what: 'the beneficiary name'),
          ),
        ),
        gap,
        pair(
          TextFormField(
            key: const Key('payout-account'),
            controller: _account,
            readOnly: ro,
            keyboardType: TextInputType.number,
            inputFormatters: [...InputRules.digits, LengthLimitingTextInputFormatter(18)],
            decoration: _dec('Account number',
                required: !_hasAccount, helper: _hasAccount ? 'Saved (${d['account_number_masked']}). Leave empty to keep it.' : null),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return _hasAccount ? null : 'Enter the account number';
              return RegExp(r'^\d{9,18}$').hasMatch(t) ? null : 'Account number should be 9 to 18 digits';
            },
          ),
          TextFormField(
            key: const Key('payout-confirm'),
            controller: _confirm,
            readOnly: ro,
            keyboardType: TextInputType.number,
            inputFormatters: [...InputRules.digits, LengthLimitingTextInputFormatter(18)],
            decoration: _dec('Confirm account number', required: !_hasAccount),
            validator: (v) => _account.text.trim().isEmpty || (v ?? '').trim() == _account.text.trim() ? null : "Account numbers don't match",
          ),
        ),
        gap,
        pair(
          TextFormField(
            key: const Key('payout-ifsc'),
            controller: _ifsc,
            readOnly: ro,
            inputFormatters: InputRules.code(11),
            decoration: _dec('IFSC code', required: true, hint: 'e.g. HDFC0001234'),
            validator: (v) => RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid 11-character IFSC code',
          ),
          DropdownButtonFormField<String>(
            key: const Key('payout-type'),
            initialValue: types.containsKey(_type) ? _type : types.keys.first,
            decoration: _dec('Account type', required: true),
            items: [for (final e in types.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: ro ? null : (v) => setState(() => _type = v ?? 'savings'),
          ),
        ),
        gap,
        pair(
          TextFormField(
            key: const Key('payout-gstin'),
            controller: _gstin,
            readOnly: ro,
            inputFormatters: InputRules.code(15),
            decoration: _dec('GST Number (Optional)', hint: '15 characters'),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || RegExp(r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][1-9A-Z]Z[0-9A-Z]$').hasMatch(t) ? null : 'Enter a valid GST number';
            },
          ),
          TextFormField(
            key: const Key('payout-gst-name'),
            controller: _gstName,
            readOnly: ro,
            inputFormatters: [LengthLimitingTextInputFormatter(120)],
            decoration: _dec('GST Business Name (Optional)'),
          ),
        ),
        gap,
        pair(
          TextFormField(
            key: const Key('payout-pan'),
            controller: _pan,
            readOnly: ro,
            inputFormatters: InputRules.code(10),
            decoration: _dec('PAN Number', required: !_hasPan, hint: 'e.g. ABCDE1234F', helper: _hasPan ? 'Saved (${d['pan_masked']}). Leave empty to keep it.' : null),
            validator: (v) {
              final t = (v ?? '').trim();
              if (t.isEmpty) return _hasPan ? null : 'Enter the PAN number';
              return RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(t) ? null : 'Enter a valid PAN (5 letters, 4 digits, 1 letter)';
            },
          ),
          TextFormField(
            key: const Key('payout-upi'),
            controller: _upi,
            readOnly: ro,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._@\-]')), LengthLimitingTextInputFormatter(80)],
            decoration: _dec('UPI Id', hint: 'e.g. name@okhdfcbank'),
            validator: (v) {
              final t = (v ?? '').trim();
              return t.isEmpty || RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z][A-Za-z0-9]{1,}$').hasMatch(t) ? null : 'Enter a valid UPI ID (name@bank)';
            },
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          key: const Key('payout-share'),
          contentPadding: EdgeInsets.zero,
          value: _share,
          onChanged: ro ? null : (v) => setState(() => _share = v),
          title: const Text('Show my UPI and bank details to guests'),
          subtitle: const Text('When online payments are off, guests see these after sending a booking request so they can pay you directly.'),
        ),
        const SizedBox(height: 16),
        if (_canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton(
              key: const Key('payout-save'),
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(minimumSize: const Size(160, 50)),
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
      ]),
    );
  }
}
