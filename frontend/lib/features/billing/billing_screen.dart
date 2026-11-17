import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/download.dart';
import '../../core/util/razorpay.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart' show errorText, showSnack;
import '../bookings/bookings_api.dart' show money, prettyDate;

/// Host Control Center → Subscription & Billing (MVP plan §2.11): current
/// plan / trial, usage and limits, plan comparison + checkout, cancel/resume,
/// history and invoices.
class BillingScreen extends StatefulWidget {
  const BillingScreen({super.key, required this.api, required this.membership, this.onChanged});

  final ApiClient api;
  final Membership membership;
  final VoidCallback? onChanged;

  @override
  State<BillingScreen> createState() => _BillingScreenState();
}

const _statusText = {
  'trialing': 'Free trial',
  'active': 'Active',
  'cancelling': 'Cancelled — active until the end of the period',
  'grace': 'Read-only — renew to keep editing',
  'expired': 'Expired — booking page closed',
};

class _BillingScreenState extends State<BillingScreen> {
  Map<String, dynamic>? _sub;
  Map<String, dynamic>? _plans;
  List<Map>? _invoices;
  String? _error;
  String _interval = 'month';
  int _units = 1;
  bool _busy = false;

  bool get _owner => widget.membership.can('billing.manage');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([widget.api.get('/api/billing'), widget.api.get('/api/billing/plans'), widget.api.get('/api/billing/invoices')]);
      if (!mounted) return;
      setState(() {
        _sub = (r[0] as Map).cast();
        _plans = (r[1] as Map).cast();
        _invoices = (r[2] as List).cast<Map>();
        final used = ((_sub!['usage'] as Map)['units'] as num).toInt();
        final bought = (_sub!['units'] as num?)?.toInt() ?? 0;
        _units = [used, bought, 1].reduce((a, b) => a > b ? a : b);
        if (_sub!['interval'] != null) _interval = _sub!['interval'] as String;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _buy(String plan) async {
    setState(() => _busy = true);
    try {
      final o = (await widget.api.post('/api/billing/checkout', {'plan': plan, 'interval': _interval, 'units': _units}) as Map).cast<String, dynamic>();
      Map<String, dynamic>? body;
      if (!mounted) return;
      if (o['provider'] == 'test') {
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Test payment'),
            content: Text('Billing is in test mode — no real money moves.\nAmount: ${money(o['amount'] as num)} (incl. GST)'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Simulate failure')),
              TextButton(key: const Key('billing-test-pay'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Pay (test)')),
            ],
          ),
        );
        if (ok == null) return;
        body = {'test_outcome': ok ? 'success' : 'failure'};
      } else {
        final r = await openRazorpayCheckout(
          keyId: o['key_id'] as String,
          orderId: o['order_id'] as String,
          amountPaise: ((o['amount'] as num) * 100).round(),
          name: 'Bleiben',
          description: 'Subscription',
        );
        if (r == null) return;
        body = r.containsKey('error') ? {'error': {'description': r['error']}} : r;
      }
      await widget.api.post('/api/billing/checkout/${o['id']}/verify', body);
      if (mounted) showSnack(context, 'Payment received — your plan is active');
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  Future<void> _cancelOrResume(bool cancel) async {
    if (cancel) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel your plan?'),
          content: Text('Everything keeps working until ${prettyDate(_sub!['current_period_end'] as String, year: true)}. After that your account becomes read-only and your booking page closes.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep plan')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.danger), child: const Text('Cancel plan')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await widget.api.post(cancel ? '/api/billing/cancel' : '/api/billing/resume', {});
      widget.onChanged?.call();
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _invoice(Map i) async {
    try {
      final html = await widget.api.get('/api/billing/invoices/${i['id']}?format=html');
      final ok = downloadText('${i['number']}.html', '$html', mime: 'text/html');
      if (mounted && !ok) showSnack(context, 'Invoices download on the web app');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _sub;
    final p = _plans;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (s == null || p == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    final usage = (s['usage'] as Map).cast<String, dynamic>();
    final limits = (s['limits'] as Map).cast<String, dynamic>();
    final status = s['status'] as String;
    final bad = status == 'grace' || status == 'expired';
    final daysLeft = s['status_ends'] == null ? null : DateTime.parse(s['status_ends'] as String).difference(DateTime.now()).inDays + 1;
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12, vertical: 20),
      children: [
        Text('Subscription & Billing', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: bad ? AppTheme.dangerSoft : Colors.white,
            border: Border.all(color: bad ? AppTheme.danger : AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('${s['plan_name']}', key: const Key('plan-name'), style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700))),
              Text(_statusText[status] ?? status, style: AppFonts.sans(fontWeight: FontWeight.w600, color: bad ? AppTheme.danger : AppTheme.forest)),
            ]),
            const SizedBox(height: 6),
            Text(
              switch (status) {
                'trialing' => 'Your ${p['trial_days']}-day trial ends ${prettyDate(s['trial_ends_at'] as String, year: true)}${daysLeft != null ? ' ($daysLeft day(s) left)' : ''}. No card needed until you choose a plan.',
                'active' => '${s['units']} unit(s), billed ${s['interval'] == 'year' ? 'yearly' : 'monthly'}. Renews ${prettyDate(s['current_period_end'] as String, year: true)} — pay from here to renew.',
                'cancelling' => 'Active until ${prettyDate(s['current_period_end'] as String, year: true)}.',
                'grace' => 'Your account is read-only until ${prettyDate(s['status_ends'] as String, year: true)}. Guests can still book. Renew now to keep editing.',
                _ => 'Renew to reopen your booking page and make changes.',
              },
            ),
            const SizedBox(height: 10),
            Text('Using ${usage['properties']} propert${usage['properties'] == 1 ? 'y' : 'ies'}${limits['max_properties'] != null ? ' of ${limits['max_properties']}' : ''} · '
                '${usage['units']} unit(s)${limits['max_units'] != null ? ' of ${limits['max_units']}' : ''}', style: AppFonts.sans(color: AppTheme.muted)),
            if (_owner && status == 'active') TextButton(onPressed: () => _cancelOrResume(true), style: TextButton.styleFrom(foregroundColor: AppTheme.danger), child: const Text('Cancel plan')),
            if (_owner && status == 'cancelling') TextButton(onPressed: () => _cancelOrResume(false), child: const Text('Keep my plan')),
          ]),
        ),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: Text(s['plan'] == null ? 'Choose a plan' : 'Renew or change plan', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700))),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'month', label: Text('Monthly')), ButtonSegment(value: 'year', label: Text('Yearly · 2 months free'))],
            selected: {_interval},
            onSelectionChanged: (v) => setState(() => _interval = v.first),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('Units (rooms you rent out): ', style: AppFonts.sans()),
          IconButton(tooltip: 'Fewer units', onPressed: _units > ((usage['units'] as num).toInt()).clamp(1, 1000) ? () => setState(() => _units--) : null, icon: const Icon(Icons.remove_circle_outline)),
          Text('$_units', key: const Key('billing-units'), style: AppFonts.sans(fontWeight: FontWeight.w700)),
          IconButton(tooltip: 'More units', onPressed: _units < 1000 ? () => setState(() => _units++) : null, icon: const Icon(Icons.add_circle_outline)),
        ]),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 14, children: [
          for (final plan in (p['plans'] as List).cast<Map>()) _planCard(plan, (p['feature_labels'] as Map).cast(), s, p['gst_rate'] as num),
        ]),
        if (!_owner) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Only the owner can change the plan.', style: AppFonts.sans(color: AppTheme.muted))),
        const SizedBox(height: 26),
        Text('Invoices', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
        if ((_invoices ?? const []).isEmpty) Text('No invoices yet.', style: AppFonts.sans(color: AppTheme.muted)),
        for (final i in _invoices ?? const <Map>[])
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('${i['number']} · ${money(i['total'] as num)}'),
            subtitle: Text('${prettyDate(i['issued_on'] as String, year: true)} · ${i['description']}'),
            trailing: TextButton.icon(onPressed: () => _invoice(i), icon: const Icon(Icons.download, size: 18), label: const Text('Download')),
          ),
        const SizedBox(height: 20),
        Text('History', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
        for (final h in (s['history'] as List).cast<Map>())
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text('${prettyDate((h['at'] as String).substring(0, 10), year: true)} · ${(h['action'] as String).replaceAll('_', ' ')}${'${h['detail']}'.isEmpty ? '' : ' — ${h['detail']}'}',
                style: AppFonts.sans(fontSize: 13.5)),
          ),
        const SizedBox(height: 10),
        Text('Prices exclude ${((p['gst_rate'] as num) * 100).round()}% GST. After a plan or trial ends you get ${p['grace_days']} days of read-only access before the booking page closes.',
            style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
      ],
    );
  }

  Widget _planCard(Map plan, Map<String, dynamic> labels, Map<String, dynamic> s, num gst) {
    final price = ((plan['unit_price'] as Map)[_interval] as num);
    final maxUnits = plan['max_units'] as num?;
    final fits = maxUnits == null || _units <= maxUnits;
    final current = s['plan'] == plan['id'] && ['active', 'cancelling'].contains(s['status']);
    final subtotal = price * _units;
    return Container(
      width: 320,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: current ? AppTheme.forest : AppTheme.border, width: current ? 2 : 1),
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${plan['name']}', style: AppFonts.sans(fontSize: 18, fontWeight: FontWeight.w700)),
        Text('${plan['tagline']}', style: AppFonts.sans(color: AppTheme.muted, fontSize: 13)),
        const SizedBox(height: 10),
        Text('${money(price)} / unit / ${_interval == 'year' ? 'year' : 'month'}', style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w600)),
        Text('$_units unit(s): ${money(subtotal)} + GST = ${money(subtotal * (1 + gst))}', style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
        Text('${plan['max_properties'] == null ? 'Unlimited properties' : 'Up to ${plan['max_properties']} properties'} · ${maxUnits == null ? 'any number of units' : 'up to $maxUnits units'}',
            style: AppFonts.sans(fontSize: 13)),
        const SizedBox(height: 8),
        for (final f in (plan['features'] as List))
          Row(children: [const Icon(Icons.check, size: 16, color: AppTheme.forest), const SizedBox(width: 6), Expanded(child: Text('${labels[f] ?? f}', style: AppFonts.sans(fontSize: 13.5)))]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            key: Key('buy-${plan['id']}'),
            onPressed: !_owner || _busy || !fits ? null : () => _buy(plan['id'] as String),
            child: Text(!fits ? 'Too many units for this plan' : current ? 'Renew' : s['plan'] == null ? 'Choose ${plan['name']}' : 'Switch to ${plan['name']}'),
          ),
        ),
      ]),
    );
  }
}
