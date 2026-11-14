import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../core/util/download.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart' show errorText, showSnack;
import '../bookings/bookings_api.dart' show money, prettyDate, ymd;

class ExpenseLine {
  ExpenseLine.fromJson(Map<String, dynamic> j)
      : index = (j['index'] as num?)?.toInt() ?? 0,
        category = j['category'] as String,
        amount = (j['amount'] as num).toDouble(),
        note = (j['note'] as String?) ?? '',
        ruleId = (j['rule_id'] as num?)?.toInt(),
        skipped = (j['skipped'] as bool?) ?? false;

  final int index;
  final String category;
  final double amount;
  final String note;
  final int? ruleId;
  final bool skipped;
}

class ExpenseEntry {
  ExpenseEntry.fromJson(Map<String, dynamic> j)
      : id = (j['id'] as num).toInt(),
        date = j['date'] as String,
        propertyId = ((j['property'] as Map)['id'] as num).toInt(),
        propertyTitle = ((j['property'] as Map)['title'] as String?) ?? '',
        paymentMode = j['payment_mode'] as String,
        paymentModeLabel = (j['payment_mode_label'] as String?) ?? '',
        notes = (j['notes'] as String?) ?? '',
        attachments = [for (final a in (j['attachments'] as List?) ?? const []) ((a as Map)['url'] as String)],
        lines = [for (final l in j['lines'] as List) ExpenseLine.fromJson((l as Map).cast())],
        total = (j['total'] as num).toDouble(),
        repeatsMonthly = (j['repeats_monthly'] as bool?) ?? false,
        skipped = (j['skipped'] as bool?) ?? false,
        autoFiled = (j['auto_filed'] as bool?) ?? false,
        addedBy = (j['added_by'] as String?) ?? '',
        addedOn = (j['added_on'] as String?) ?? '';

  final int id;
  final String date;
  final int propertyId;
  final String propertyTitle;
  final String paymentMode;
  final String paymentModeLabel;
  final String notes;
  final List<String> attachments;
  final List<ExpenseLine> lines;
  final double total;
  final bool repeatsMonthly;
  final bool skipped;
  final bool autoFiled;
  final String addedBy;
  final String addedOn;
}

class ExpensesApi {
  ExpensesApi(this.api);

  final ApiClient api;

  Future<Map<String, dynamic>> meta() async => (await api.get('/api/expenses/meta') as Map).cast();

  String _q(Map<String, String> q) => q.entries.where((e) => e.value.isNotEmpty).map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');

  Future<Map<String, dynamic>> list(Map<String, String> q) async => (await api.get('/api/expenses?${_q(q)}') as Map).cast();
  Future<String> export(Map<String, String> q) async => (await api.get('/api/expenses/export?${_q(q)}')).toString();
  Future<void> create(Map<String, dynamic> body) => api.post('/api/expenses', body);
  Future<void> update(int id, Map<String, dynamic> body) => api.patch('/api/expenses/$id', body);
  Future<void> delete(int id) => api.delete('/api/expenses/$id');
  Future<String> upload(String base64, String name) async =>
      ((await api.post('/api/expenses/attachments', {'data': base64, 'name': name}) as Map)['url'] as String);
  Future<List<Map<String, dynamic>>> rules() async => [for (final r in await api.get('/api/expenses/rules') as List) (r as Map).cast()];
  Future<Map<String, dynamic>> rule(int id) async => (await api.get('/api/expenses/rules/$id') as Map).cast();
  Future<Map<String, dynamic>> ruleAction(int id, String action, [Map<String, dynamic> body = const {}]) async =>
      (await api.post('/api/expenses/rules/$id/$action', body) as Map).cast();
  Future<Map<String, dynamic>> updateRule(int id, Map<String, dynamic> body) async =>
      (await api.patch('/api/expenses/rules/$id', body) as Map).cast();
  Future<List<({int id, String title})>> properties() async => [
        for (final p in await api.get('/api/properties') as List)
          (id: ((p as Map)['id'] as num).toInt(), title: (p['title'] as String?)?.isNotEmpty == true ? p['title'] as String : 'Untitled property'),
      ];
}

/// Host Control Center → Expenses: entries with expense lines, filters,
/// running totals, monthly repeats and CSV export (REA 08 §4).
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key, required this.api, required this.membership, this.openAddOnStart = false});

  final ApiClient api;
  final Membership membership;
  final bool openAddOnStart;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  late final ExpensesApi _x = ExpensesApi(widget.api);
  final _search = TextEditingController();
  final _over = TextEditingController();
  final _under = TextEditingController();
  List<String> _categories = const [];
  Map<String, String> _modes = const {};
  List<({int id, String title})> _props = const [];
  String _property = '';
  String _category = 'all';
  String _mode = 'all';
  String _period = 'this_month';
  DateTimeRange? _custom;
  String _attachments = 'any';
  bool _recurring = false;
  String _sort = 'date_desc';
  bool _more = false;
  Map<String, dynamic>? _data;
  String? _error;
  bool _loading = false;
  int _page = 1;
  final Set<int> _expanded = {};

  bool get _canWrite => widget.membership.can('expenses.write');

  @override
  void initState() {
    super.initState();
    Future.wait([_x.meta(), _x.properties()]).then((r) {
      if (!mounted) return;
      final meta = r[0] as Map<String, dynamic>;
      setState(() {
        _categories = (meta['categories'] as List).cast<String>();
        _modes = (meta['payment_modes'] as Map).cast<String, String>();
        _props = r[1] as List<({int id, String title})>;
      });
      if (widget.openAddOnStart && _canWrite) _edit();
    }).catchError((Object e) {
      if (mounted) setState(() => _error = errorText(e));
    });
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _over.dispose();
    _under.dispose();
    super.dispose();
  }

  (String, String) get _range {
    final now = DateTime.now();
    return switch (_period) {
      'this_month' => (ymd(DateTime(now.year, now.month, 1)), ymd(now)),
      'last_month' => (ymd(DateTime(now.year, now.month - 1, 1)), ymd(DateTime(now.year, now.month, 0))),
      'last_90' => (ymd(now.subtract(const Duration(days: 89))), ymd(now)),
      'this_year' => (ymd(DateTime(now.year, 1, 1)), ymd(now)),
      'custom' when _custom != null => (ymd(_custom!.start), ymd(_custom!.end)),
      _ => ('', ''),
    };
  }

  Map<String, String> get _query {
    final (from, to) = _range;
    return {
      'q': _search.text.trim(),
      'property_id': _property,
      'category': _category == 'all' ? '' : _category,
      'payment_mode': _mode == 'all' ? '' : _mode,
      'from': from,
      'to': to,
      'min': _over.text.trim(),
      'max': _under.text.trim(),
      'attachments': _attachments == 'any' ? '' : _attachments,
      'recurring': _recurring ? 'true' : '',
      'sort': _sort,
    };
  }

  int get _moreCount => [_over.text.trim().isNotEmpty, _under.text.trim().isNotEmpty, _attachments != 'any', _recurring].where((b) => b).length;

  bool get _anyFilter =>
      _search.text.trim().isNotEmpty || _property.isNotEmpty || _category != 'all' || _mode != 'all' || _period != 'this_month' || _moreCount > 0;

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });
    try {
      final d = await _x.list({..._query, 'page': '$page', 'page_size': '25'});
      if (mounted) setState(() => _data = d);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _reset() {
    _search.clear();
    _over.clear();
    _under.clear();
    _property = '';
    _category = 'all';
    _mode = 'all';
    _period = 'this_month';
    _custom = null;
    _attachments = 'any';
    _recurring = false;
    _load();
  }

  Future<void> _export() async {
    showSnack(context, 'Preparing export…');
    try {
      final csv = await _x.export(_query);
      final ok = downloadText('bleiben-expenses-${ymd(DateTime.now())}.csv', csv);
      if (mounted) showSnack(context, ok ? 'Expenses exported' : 'Export is available in the web app');
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _edit([ExpenseEntry? e]) async {
    if (_props.isEmpty) return showSnack(context, 'Add a property first, then log its expenses.');
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _EntryDialog(x: _x, entry: e, properties: _props, categories: _categories, modes: _modes),
    );
    if (saved == true && mounted) {
      showSnack(context, e == null ? 'Expense added' : 'Expense updated');
      _load(page: _page);
    }
  }

  Future<void> _delete(ExpenseEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text(e.repeatsMonthly
            ? 'This removes ${prettyDate(e.date, year: true)} only. The monthly repeat continues — stop it from Repeating expenses.'
            : 'This deletes the whole entry (${money(e.total)}) and its expense lines.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            key: const Key('confirm-delete-expense'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Delete entry'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _x.delete(e.id);
      if (mounted) showSnack(context, 'Entry deleted');
      _load(page: _page);
    } catch (err) {
      if (mounted) showSnack(context, errorText(err));
    }
  }

  Future<void> _openRules() async {
    await showDialog<void>(context: context, builder: (_) => _RulesDialog(x: _x, props: _props, canWrite: _canWrite));
    _load(page: _page);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final d = _data;
    final items = [for (final i in (d?['items'] as List?) ?? const []) ExpenseEntry.fromJson((i as Map).cast())];
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12, vertical: 20),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Expenses', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600)),
              if (d != null)
                Text('${d['total']} entr${d['total'] == 1 ? 'y' : 'ies'} · ${money(d['sum'] as num)}',
                    key: const Key('expenses-total'), style: AppFonts.sans(color: AppTheme.muted)),
            ]),
          ),
          TextButton.icon(onPressed: _openRules, icon: const Icon(Icons.event_repeat_outlined), label: const Text('Repeating expenses')),
          IconButton(tooltip: 'Export expenses', onPressed: _export, icon: const Icon(Icons.download_outlined)),
          if (_canWrite)
            SizedBox(
              width: 160,
              child: ElevatedButton.icon(
                  key: const Key('add-expense'), onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('Add expense')),
            ),
        ]),
        const SizedBox(height: 14),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: wide ? 340 : double.infinity,
            child: TextField(
              key: const Key('expense-search'),
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: const InputDecoration(
                  hintText: 'Search expenses by type, amount or payment method', prefixIcon: Icon(Icons.search), isDense: true),
            ),
          ),
          _drop('Property', _property, {'': 'All properties', for (final p in _props) '${p.id}': p.title}, (v) => _property = v),
          _drop('Category', _category, {'all': 'All categories', for (final c in _categories) c: c}, (v) => _category = v),
          _drop('Payment mode', _mode, {'all': 'All payment modes', ..._modes}, (v) => _mode = v),
          _drop('Period', _period, const {
            'this_month': 'This month',
            'last_month': 'Last month',
            'last_90': 'Last 90 days',
            'this_year': 'This year',
            'all': 'All time',
            'custom': 'Custom range',
          }, (v) async {
            _period = v;
            if (v == 'custom') {
              final now = DateTime.now();
              _custom = await showDateRangePicker(context: context, firstDate: DateTime(now.year - 5), lastDate: now, initialDateRange: _custom);
              if (_custom == null) _period = 'this_month';
              _load();
            }
          }, reload: (v) => v != 'custom'),
          OutlinedButton.icon(
            onPressed: () => setState(() => _more = !_more),
            icon: const Icon(Icons.tune, size: 18),
            label: Text(_moreCount == 0 ? 'More filters' : 'More filters, $_moreCount applied'),
          ),
          if (_anyFilter) TextButton(onPressed: _reset, child: const Text('Clear all')),
        ]),
        if (_more) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
            SizedBox(width: 150, child: _amountField(_over, 'Over (₹)')),
            SizedBox(width: 150, child: _amountField(_under, 'Under (₹)')),
            _drop('Attachments', _attachments, const {'any': 'Any', 'with': 'With attachments', 'without': 'Without attachments'}, (v) => _attachments = v),
            _drop('Sort by', _sort, const {
              'date_desc': 'Newest first',
              'date_asc': 'Oldest first',
              'amount_desc': 'Highest amount',
              'amount_asc': 'Lowest amount',
            }, (v) => _sort = v),
            FilterChip(
              label: const Text('Only monthly recurring'),
              tooltip: 'Your fixed commitments',
              selected: _recurring,
              onSelected: (v) {
                _recurring = v;
                _load();
              },
            ),
            TextButton(onPressed: _load, child: const Text('Apply')),
          ]),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Amount range matches the entry total, not individual expense lines.',
                style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
          ),
        ],
        const SizedBox(height: 14),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_error != null)
          Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: AppFonts.sans(color: AppTheme.danger)))
        else if (d != null && items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(40),
            child: Column(children: [
              Text(d['has_any'] == true ? 'Nothing matches these filters' : 'No expenses yet',
                  style: AppFonts.sans(fontSize: 17, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(
                d['has_any'] == true
                    ? 'Widen the period or clear a filter.'
                    : 'Log your first bill, salary or repair and it appears here with running totals.',
                textAlign: TextAlign.center,
                style: AppFonts.sans(color: AppTheme.muted),
              ),
            ]),
          )
        else
          for (final e in items) _row(e),
        if (d != null && (d['total'] as int) > 25)
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            IconButton(tooltip: 'Previous page', onPressed: _page > 1 ? () => _load(page: _page - 1) : null, icon: const Icon(Icons.chevron_left)),
            Text('Page $_page'),
            IconButton(
                tooltip: 'Next page',
                onPressed: _page * 25 < (d['total'] as int) ? () => _load(page: _page + 1) : null,
                icon: const Icon(Icons.chevron_right)),
          ]),
      ],
    );
  }

  Widget _amountField(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        onSubmitted: (_) => _load(),
        decoration: InputDecoration(labelText: label, isDense: true),
      );

  Widget _drop(String label, String value, Map<String, String> items, void Function(String) set, {bool Function(String)? reload}) =>
      SizedBox(
        width: 190,
        child: DropdownButtonFormField<String>(
          key: ValueKey('$label-$value'),
          initialValue: items.containsKey(value) ? value : items.keys.first,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v == null) return;
            set(v);
            if (reload == null || reload(v)) _load();
          },
        ),
      );

  Widget _badge(String t, Color bg, Color fg) => Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: AppFonts.sans(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
      );

  Widget _row(ExpenseEntry e) {
    final open = _expanded.contains(e.id);
    final cats = e.lines.map((l) => l.category).toSet().join(', ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 92,
              child: Text(prettyDate(e.date, year: true), style: AppFonts.sans(fontWeight: FontWeight.w600)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(cats, style: AppFonts.sans(fontWeight: FontWeight.w600)),
                Text('${e.propertyTitle} · ${e.paymentModeLabel}', style: AppFonts.sans(fontSize: 13, color: AppTheme.muted)),
                const SizedBox(height: 4),
                Wrap(runSpacing: 4, children: [
                  if (e.repeatsMonthly) _badge('Repeats monthly', AppTheme.sage, AppTheme.forest),
                  if (e.autoFiled) _badge('Auto-filed', AppTheme.sage, AppTheme.inkSoft),
                  if (e.skipped) _badge('Skipped', AppTheme.warningSoft, AppTheme.warningInk),
                  if (e.attachments.isNotEmpty) _badge('${e.attachments.length} attachment(s)', AppTheme.sand, AppTheme.inkSoft),
                ]),
              ]),
            ),
            Text(money(e.total), style: AppFonts.sans(fontWeight: FontWeight.w700, fontSize: 16)),
            PopupMenuButton<String>(
              tooltip: 'Entry actions',
              onSelected: (v) => v == 'edit' ? _edit(e) : _delete(e),
              itemBuilder: (_) => [
                if (_canWrite) const PopupMenuItem(value: 'edit', child: Text('Edit entry')),
                if (_canWrite) const PopupMenuItem(value: 'delete', child: Text('Delete entry')),
              ],
              enabled: _canWrite,
            ),
          ]),
          TextButton(
            onPressed: () => setState(() => open ? _expanded.remove(e.id) : _expanded.add(e.id)),
            child: Text(open ? 'Hide expense types' : 'Show expense types (${e.lines.length})'),
          ),
          if (open) ...[
            for (final l in e.lines)
              Padding(
                padding: const EdgeInsets.only(left: 92, right: 48, bottom: 4),
                child: Row(children: [
                  Expanded(child: Text('${l.category}${l.note.isEmpty ? '' : ' — ${l.note}'}${l.skipped ? ' (skipped)' : ''}')),
                  Text(money(l.skipped ? 0 : l.amount)),
                ]),
              ),
            if (e.notes.isNotEmpty)
              Padding(padding: const EdgeInsets.only(left: 92, bottom: 4), child: Text(e.notes, style: AppFonts.sans(color: AppTheme.muted))),
            if (e.attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 92, bottom: 6),
                child: Wrap(spacing: 8, children: [
                  for (final a in e.attachments)
                    InkWell(
                      onTap: () => _viewImage(a),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network('${ApiConfig.baseUrl}$a', width: 64, height: 64, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox(width: 64, height: 64, child: Icon(Icons.broken_image_outlined))),
                      ),
                    ),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 92),
              child: Text(
                'Added by ${e.addedBy.isEmpty ? '—' : e.addedBy}${e.addedOn.length >= 10 ? ' · Added on ${prettyDate(e.addedOn.substring(0, 10), year: true)}' : ''}',
                style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  /// Attachment viewer with zoom and rotate.
  void _viewImage(String url) {
    var turns = 0;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              IconButton(tooltip: 'Rotate', onPressed: () => setS(() => turns = (turns + 1) % 4), icon: const Icon(Icons.rotate_right)),
              IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close)),
            ]),
            Flexible(
              child: InteractiveViewer(
                maxScale: 5,
                child: RotatedBox(quarterTurns: turns, child: Image.network('${ApiConfig.baseUrl}$url')),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _LineDraft {
  _LineDraft({this.index, this.category, String amount = '', String note = '', this.ruleId})
      : amount = TextEditingController(text: amount),
        note = TextEditingController(text: note);

  final int? index;
  String? category;
  final TextEditingController amount;
  final TextEditingController note;
  final int? ruleId;
  bool repeat = false;
}

class _EntryDialog extends StatefulWidget {
  const _EntryDialog({required this.x, required this.entry, required this.properties, required this.categories, required this.modes});

  final ExpensesApi x;
  final ExpenseEntry? entry;
  final List<({int id, String title})> properties;
  final List<String> categories;
  final Map<String, String> modes;

  @override
  State<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends State<_EntryDialog> {
  late DateTime _date = widget.entry == null ? DateTime.now() : DateTime.parse(widget.entry!.date);
  late int _property = widget.entry?.propertyId ?? widget.properties.first.id;
  late String _mode = widget.entry?.paymentMode ?? 'cash';
  late final _notes = TextEditingController(text: widget.entry?.notes ?? '');
  late final List<_LineDraft> _lines = widget.entry == null
      ? [_LineDraft()]
      : [
          for (final l in widget.entry!.lines)
            _LineDraft(index: l.index, category: l.category, amount: l.amount.toStringAsFixed(0), note: l.note, ruleId: l.ruleId),
        ];
  late final List<Map<String, String>> _attachments = [for (final a in widget.entry?.attachments ?? const <String>[]) {'url': a}];
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.entry == null;

  @override
  void dispose() {
    _notes.dispose();
    for (final l in _lines) {
      l.amount.dispose();
      l.note.dispose();
    }
    super.dispose();
  }

  double get _total => _lines.fold(0, (s, l) => s + (double.tryParse(l.amount.text) ?? 0));

  Future<void> _attach() async {
    final f = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1800, imageQuality: 85);
    if (f == null) return;
    try {
      final url = await widget.x.upload(base64Encode(await f.readAsBytes()), f.name);
      setState(() => _attachments.add({'url': url, 'name': f.name}));
    } catch (e) {
      setState(() => _error = errorText(e));
    }
  }

  Future<void> _save() async {
    for (final l in _lines) {
      if (l.category == null || double.tryParse(l.amount.text.trim()) == null) {
        return setState(() => _error = 'Each line needs a category and an amount');
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final body = {
      'property_id': _property,
      'date': ymd(_date),
      'payment_mode': _mode,
      'notes': _notes.text.trim(),
      'attachments': _attachments,
      'lines': [
        for (final l in _lines)
          {
            if (l.index != null) 'index': l.index,
            'category': l.category,
            'amount': double.parse(l.amount.text.trim()),
            'note': l.note.text.trim(),
            if (_isNew && l.repeat) 'repeat_monthly': true,
          },
      ],
    };
    try {
      _isNew ? await widget.x.create(body) : await widget.x.update(widget.entry!.id, body);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_isNew ? 'Add expense' : 'Edit entry'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final now = DateTime.now();
                      final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(now.year - 5), lastDate: now);
                      if (d != null) setState(() => _date = d);
                    },
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Expense date: ${prettyDate(ymd(_date), year: true)}'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _mode,
                    decoration: const InputDecoration(labelText: 'Payment mode', isDense: true),
                    items: [for (final e in widget.modes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                    onChanged: (v) => setState(() => _mode = v ?? 'cash'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                key: const Key('expense-property'),
                initialValue: _property,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Property', isDense: true),
                items: [for (final p in widget.properties) DropdownMenuItem(value: p.id, child: Text(p.title))],
                onChanged: (v) => setState(() => _property = v ?? _property),
              ),
              const SizedBox(height: 14),
              Text('Expense lines', style: AppFonts.sans(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              for (final (i, l) in _lines.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(children: [
                    Row(children: [
                      Expanded(
                        flex: 5,
                        child: DropdownButtonFormField<String>(
                          key: Key('line-category-$i'),
                          initialValue: l.category,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Category', isDense: true),
                          items: [for (final c in widget.categories) DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))],
                          onChanged: l.ruleId != null ? null : (v) => setState(() => l.category = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          key: Key('line-amount-$i'),
                          controller: l.amount,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                          decoration: const InputDecoration(labelText: 'Amount (₹)', isDense: true),
                        ),
                      ),
                      IconButton(
                        tooltip: l.ruleId != null ? 'Repeating lines are skipped, not removed' : 'Remove line',
                        onPressed: _lines.length == 1 || l.ruleId != null ? null : () => setState(() => _lines.removeAt(i)),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: TextField(controller: l.note, decoration: const InputDecoration(labelText: 'Note (optional)', isDense: true))),
                      if (_isNew) ...[
                        const SizedBox(width: 8),
                        Checkbox(value: l.repeat, onChanged: (v) => setState(() => l.repeat = v ?? false)),
                        const Text('Repeat every month'),
                      ] else if (l.ruleId != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text('Repeats monthly · this month only', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
                        ),
                    ]),
                  ]),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => setState(() => _lines.add(_LineDraft())), icon: const Icon(Icons.add), label: const Text('Add another line')),
              ),
              Text('Entry total: ${money(_total)}', style: AppFonts.sans(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes')),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final a in _attachments)
                  InputChip(
                    label: Text(a['name']?.isNotEmpty == true ? a['name']! : 'Attachment'),
                    onDeleted: () => setState(() => _attachments.remove(a)),
                  ),
                OutlinedButton.icon(onPressed: _attach, icon: const Icon(Icons.attach_file), label: const Text('Attach bill')),
              ]),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: AppFonts.sans(color: AppTheme.danger)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          SizedBox(
            width: 150,
            child: ElevatedButton(
                key: const Key('save-expense'), onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          ),
        ],
      );
}

/// Monthly rules: schedule with Skip / Unskip, amount for the months ahead, stop.
class _RulesDialog extends StatefulWidget {
  const _RulesDialog({required this.x, required this.props, required this.canWrite});

  final ExpensesApi x;
  final List<({int id, String title})> props;
  final bool canWrite;

  @override
  State<_RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<_RulesDialog> {
  List<Map<String, dynamic>>? _rules;
  Map<String, dynamic>? _open;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.x.rules();
      if (mounted) setState(() => _rules = r);
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _select(int id) async {
    final r = await widget.x.rule(id);
    if (mounted) setState(() => _open = r);
  }

  Future<void> _act(Future<Map<String, dynamic>> Function() call) async {
    try {
      final r = await call();
      if (!mounted) return;
      setState(() => _open = r);
      if (r['message'] != null) showSnack(context, r['message'] as String);
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<String?> _prompt(String title, String label, {String initial = '', bool number = false}) async {
    final c = TextEditingController(text: initial);
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: number ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    return r;
  }

  String _propTitle(int id) => widget.props.where((p) => p.id == id).map((p) => p.title).firstOrNull ?? 'Property';

  @override
  Widget build(BuildContext context) {
    final open = _open;
    return AlertDialog(
      title: Row(children: [
        if (open != null) IconButton(tooltip: 'Back', onPressed: () => setState(() => _open = null), icon: const Icon(Icons.arrow_back)),
        Expanded(child: Text(open == null ? 'Repeating expenses' : '${open['category']} · ${_propTitle((open['property_id'] as num).toInt())}')),
        IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ]),
      content: SizedBox(
        width: 560,
        child: _rules == null
            ? (_error != null ? Text(_error!) : const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())))
            : open == null
                ? (_rules!.isEmpty
                    ? const Text('No repeating expenses yet. Tick "Repeat every month" on a line when you add an expense.')
                    : ListView(shrinkWrap: true, children: [
                        for (final r in _rules!)
                          ListTile(
                            title: Text('${r['category']} · ${money(r['amount'] as num)} / month'),
                            subtitle: Text(
                                '${_propTitle((r['property_id'] as num).toInt())} · from ${r['start_month']}${r['status'] == 'active' ? ' · files on day ${r['day']}' : ' · ended ${r['end_month']}'}'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _select((r['id'] as num).toInt()),
                          ),
                      ]))
                : _detail(open),
      ),
    );
  }

  Widget _detail(Map<String, dynamic> r) {
    final id = (r['id'] as num).toInt();
    final active = r['status'] == 'active';
    final now = ymd(DateTime.now()).substring(0, 7);
    return ListView(shrinkWrap: true, children: [
      if (!active)
        Text('This repeat has ended. Its filed months stay in your ledger.', style: AppFonts.sans(color: AppTheme.warningInk))
      else if (r['nothing_will_file'] == true)
        Text('Nothing will file. Unskip a month, or stop the repeat.', style: AppFonts.sans(color: AppTheme.warningInk)),
      const SizedBox(height: 8),
      Text('Schedule', style: AppFonts.sans(fontWeight: FontWeight.w700)),
      for (final s in (r['schedule'] as List).cast<Map>().reversed)
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text('${s['month']} · ${money(s['amount'] as num)}'),
          subtitle: Text(switch (s['status']) {
            'filed' => 'Filed',
            'skipped' => 'Skipped${(s['skip_reason'] as String?)?.isNotEmpty == true ? ' — ${s['skip_reason']}' : ''}',
            'removed' => 'Removed',
            _ => 'Upcoming',
          }),
          trailing: !widget.canWrite || !active || s['status'] == 'removed'
              ? null
              : s['status'] == 'skipped'
                  ? TextButton(onPressed: () => _act(() => widget.x.ruleAction(id, 'unskip', {'month': s['month']})), child: const Text('Unskip'))
                  : TextButton(
                      onPressed: () async {
                        final reason = await _prompt('Skip ${s['month']}', 'Reason (optional)');
                        if (reason != null) await _act(() => widget.x.ruleAction(id, 'skip', {'month': s['month'], 'reason': reason}));
                      },
                      child: Text((s['month'] as String).compareTo(now) <= 0 ? 'Skip (₹0)' : 'Skip'),
                    ),
        ),
      if (widget.canWrite && active) ...[
        const Divider(),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton(
            onPressed: () async {
              final v = await _prompt('Amount for the months ahead', 'Amount (₹)', initial: '${(r['amount'] as num).round()}', number: true);
              final a = double.tryParse(v ?? '');
              if (a != null) await _act(() => widget.x.updateRule(id, {'amount': a}));
            },
            child: const Text('Edit repeating expense'),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Stop repeating?'),
                  content: const Text('Months already filed stay in your ledger. Upcoming months won\'t file.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep repeating')),
                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop from today')),
                  ],
                ),
              );
              if (ok == true) await _act(() => widget.x.ruleAction(id, 'stop'));
            },
            child: const Text('Stop repeating'),
          ),
        ]),
      ],
    ]);
  }
}
