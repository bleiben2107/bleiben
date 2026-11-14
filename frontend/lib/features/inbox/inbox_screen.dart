import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart';
import '../bookings/bookings_api.dart';

const _stages = {'any': 'Any stage', 'upcoming': 'Upcoming', 'ongoing': 'Ongoing', 'completed': 'Completed', 'cancelled': 'Cancelled'};

String _ago(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().toUtc().difference(t.toUtc());
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

String _clock(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  return '${prettyDate(ymd(t))}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

String _mins(num? m) {
  if (m == null) return '—';
  if (m < 60) return '${m.round()} min';
  if (m < 1440) return '${(m / 60).toStringAsFixed(1)} h';
  return '${(m / 1440).toStringAsFixed(1)} d';
}

/// Host Control Center → Messages (REA 08 §5, Bleiben side): conversations
/// per booking, reply / log guest message, quick replies with variables,
/// send later, team note, per-user flags, reply times, details panel.
class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.api, required this.bookings, required this.membership, this.onUnreadChanged});

  final ApiClient api;
  final BookingsApi bookings;
  final Membership membership;
  final VoidCallback? onUnreadChanged;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  final _search = TextEditingController();
  String _view = 'all';
  bool _unread = false;
  String _channel = 'all';
  String _stage = 'any';
  Map<String, dynamic>? _list;
  int? _openId;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _load(quiet: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    final q = {
      'view': _view,
      if (_unread) 'unread': 'true',
      if (_channel != 'all') 'channel': _channel,
      if (_stage != 'any') 'stage': _stage,
      if (_search.text.trim().length >= 2) 'q': _search.text.trim(),
    };
    try {
      final r = await widget.api.get('/api/messages?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}');
      if (mounted) setState(() => _list = (r as Map).cast());
      widget.onUnreadChanged?.call();
    } catch (e) {
      if (mounted && !quiet) setState(() => _error = errorText(e));
    }
  }

  void _showReplyTimes() => showDialog<void>(context: context, builder: (_) => _ReplyTimes(api: widget.api));

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1000;
    final listPane = _listPane();
    final thread = _openId == null
        ? Center(child: Text('Choose a conversation', style: AppFonts.sans(color: AppTheme.muted)))
        : _Thread(
            key: ValueKey(_openId),
            id: _openId!,
            api: widget.api,
            bookings: widget.bookings,
            membership: widget.membership,
            wide: width >= 1350,
            onBack: wide ? null : () => setState(() => _openId = null),
            onChanged: () => _load(quiet: true),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 32 : 12, 18, wide ? 32 : 12, 12),
      child: wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 380, child: listPane),
              const SizedBox(width: 14),
              Expanded(child: thread),
            ])
          : (_openId == null ? listPane : thread),
    );
  }

  Widget _listPane() {
    final items = ((_list?['items'] as List?) ?? const []).cast<Map>();
    final channels = ((_list?['channels'] as Map?) ?? const {}).cast<String, String>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Messages', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600))),
        ActionChip(key: const Key('reply-times'), avatar: const Icon(Icons.timer_outlined, size: 16), label: const Text('Reply times'), onPressed: _showReplyTimes),
      ]),
      const SizedBox(height: 10),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'all', label: Text('All')),
          ButtonSegment(value: 'starred', label: Text('Starred')),
          ButtonSegment(value: 'archived', label: Text('Archived')),
        ],
        selected: {_view},
        onSelectionChanged: (v) {
          _view = v.first;
          _load();
        },
      ),
      const SizedBox(height: 10),
      TextField(
        key: const Key('inbox-search'),
        controller: _search,
        onChanged: (v) {
          if (v.trim().length >= 2 || v.isEmpty) _load(quiet: true);
        },
        decoration: const InputDecoration(hintText: 'Search guest, property or message', prefixIcon: Icon(Icons.search), isDense: true),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        FilterChip(
          key: const Key('unread-filter'),
          label: const Text('Unread'),
          selected: _unread,
          onSelected: (v) {
            _unread = v;
            _load();
          },
        ),
        _miniDrop(_channel, {'all': 'All channels', ...channels}, (v) => _channel = v),
        _miniDrop(_stage, _stages, (v) => _stage = v),
      ]),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text('Waiting on you, most urgent first · ${items.length} result${items.length == 1 ? '' : 's'}',
            style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
      ),
      Expanded(
        child: _list == null
            ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
            : items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        _view == 'archived'
                            ? 'Nothing archived.'
                            : _unread
                                ? "No unread conversations. You're all caught up."
                                : _channel != 'all'
                                    ? 'No conversations on ${channels[_channel] ?? _channel} yet.'
                                    : 'No conversations yet. Each booking gets a conversation here.',
                        textAlign: TextAlign.center,
                        style: AppFonts.sans(color: AppTheme.muted),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _tile(items[i]),
                  ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('Stars, priority and filters are yours alone. Your team sees their own.',
            style: AppFonts.sans(fontSize: 11.5, color: AppTheme.hint)),
      ),
    ]);
  }

  Widget _miniDrop(String value, Map<String, String> items, void Function(String) set) => DropdownButton<String>(
        value: items.containsKey(value) ? value : items.keys.first,
        isDense: true,
        underline: const SizedBox.shrink(),
        items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: AppFonts.sans(fontSize: 13.5)))],
        onChanged: (v) {
          if (v == null) return;
          set(v);
          _load();
        },
      );

  Widget _tile(Map t) {
    final selected = t['id'] == _openId;
    final last = t['last_message'] as Map?;
    final unread = t['unread'] == true;
    final b = t['booking'] as Map?;
    return Material(
      color: selected ? AppTheme.sage : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: Key('thread-${t['id']}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => setState(() => _openId = (t['id'] as num).toInt()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: AppTheme.sand,
              child: Text((t['guest_name'] as String).isEmpty ? '?' : (t['guest_name'] as String)[0].toUpperCase(),
                  style: AppFonts.sans(fontWeight: FontWeight.w700, color: AppTheme.inkSoft)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (t['priority'] == true) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.flag, size: 14, color: AppTheme.danger)),
                  Expanded(
                    child: Text(t['guest_name'] as String,
                        overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
                  ),
                  if (t['starred'] == true) const Icon(Icons.star, size: 14, color: AppTheme.clay),
                  const SizedBox(width: 4),
                  Text(_ago((t['last_message_at'] as String?) ?? ''), style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
                ]),
                Text(
                  '${t['channel_label']} · ${(t['property'] as Map)['title']}${b == null ? '' : ' · ${prettyDate(b['check_in'] as String)}–${prettyDate(b['check_out'] as String)}'}',
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.sans(fontSize: 12, color: AppTheme.muted),
                ),
                const SizedBox(height: 2),
                Text(
                  last == null ? 'No messages yet' : '${last['direction'] == 'out' ? 'You: ' : ''}${last['body']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.sans(fontSize: 13, fontWeight: unread ? FontWeight.w600 : FontWeight.w400, color: unread ? AppTheme.ink : AppTheme.muted),
                ),
                if (t['waiting_since'] != null)
                  Text('Waiting ${_ago(t['waiting_since'] as String)}', style: AppFonts.sans(fontSize: 11.5, color: AppTheme.warningInk)),
              ]),
            ),
            if (unread)
              Container(
                  margin: const EdgeInsets.only(left: 6, top: 6), width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.clay, shape: BoxShape.circle)),
          ]),
        ),
      ),
    );
  }
}

class _Thread extends StatefulWidget {
  const _Thread({
    super.key,
    required this.id,
    required this.api,
    required this.bookings,
    required this.membership,
    required this.wide,
    required this.onBack,
    required this.onChanged,
  });

  final int id;
  final ApiClient api;
  final BookingsApi bookings;
  final Membership membership;
  final bool wide;
  final VoidCallback? onBack;
  final VoidCallback onChanged;

  @override
  State<_Thread> createState() => _ThreadState();
}

class _ThreadState extends State<_Thread> {
  final _compose = TextEditingController();
  final _note = TextEditingController();
  final _scroll = ScrollController();
  Map<String, dynamic>? _t;
  Map<String, dynamic>? _qr;
  bool _logGuest = false;
  bool _sending = false;
  bool _editingNote = false;

  bool get _canWrite => widget.membership.can('messages.write');
  String get _base => '/api/messages/${widget.id}';

  @override
  void initState() {
    super.initState();
    _load(markRead: true);
    widget.api.get('/api/messages/quick-replies').then((r) {
      if (mounted) setState(() => _qr = (r as Map).cast());
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _compose.dispose();
    _note.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool markRead = false}) async {
    try {
      if (markRead && _canWrite) await widget.api.post('$_base/state', {'read': true});
      final r = (await widget.api.get(_base) as Map).cast<String, dynamic>();
      if (!mounted) return;
      setState(() {
        _t = r;
        _note.text = ((r['note'] as Map?)?['text'] as String?) ?? '';
      });
      if (markRead) widget.onChanged();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _state(Map<String, dynamic> body, String done) async {
    try {
      await widget.api.post('$_base/state', body);
      if (!mounted) return;
      showSnack(context, done);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _send() async {
    final text = _compose.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await widget.api.post('$_base/messages', {'body': text, 'direction': _logGuest ? 'in' : 'out'});
      _compose.clear();
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<DateTime?> _pickWhen([DateTime? initial]) async {
    final now = DateTime.now();
    final start = initial ?? now.add(const Duration(hours: 1));
    final d = await showDatePicker(context: context, initialDate: start, firstDate: now, lastDate: now.add(const Duration(days: 365)), helpText: 'Send on (IST)');
    if (d == null || !mounted) return null;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(start), helpText: 'Send at (IST)');
    if (t == null) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _sendLater() async {
    final text = _compose.text.trim();
    if (text.isEmpty) return showSnack(context, 'Write the message first');
    final when = await _pickWhen();
    if (when == null) return;
    try {
      await widget.api.post('$_base/scheduled', {'body': text, 'send_at': when.toUtc().toIso8601String()});
      _compose.clear();
      if (mounted) showSnack(context, 'Scheduled for ${_clock(when.toUtc().toIso8601String())}');
      _load();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    }
  }

  Future<void> _quickReplies() async {
    final qr = _qr;
    if (qr == null) return;
    final picked = await showDialog<String>(context: context, builder: (_) => _QuickReplies(api: widget.api, initial: qr));
    final fresh = await widget.api.get('/api/messages/quick-replies');
    if (mounted) setState(() => _qr = (fresh as Map).cast());
    if (picked == null) return;
    // Preview with this guest's details filled in.
    final r = await widget.api.post('$_base/render', {'body': picked}) as Map;
    _putInReply(r['body'] as String);
  }

  void _putInReply(String text) {
    final cur = _compose.text.trim();
    _compose.text = cur.isEmpty ? text : '$cur\n$text';
    _compose.selection = TextSelection.collapsed(offset: _compose.text.length);
    setState(() => _logGuest = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    if (t == null) return const Center(child: CircularProgressIndicator());
    final main = Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _header(t),
        const Divider(height: 1),
        Expanded(child: _messages(t)),
        if (_canWrite) _composer(),
      ]),
    );
    if (!widget.wide) return main;
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: main),
      const SizedBox(width: 14),
      SizedBox(width: 320, child: _details(t)),
    ]);
  }

  Widget _header(Map<String, dynamic> t) {
    final b = t['booking'] as Map?;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(children: [
        if (widget.onBack != null) IconButton(tooltip: 'Back to conversations', onPressed: widget.onBack, icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 6),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t['guest_name'] as String, style: AppFonts.sans(fontSize: 17, fontWeight: FontWeight.w700)),
            Text('${t['channel_label']} · ${(t['property'] as Map)['title']}${b == null ? '' : ' · ${b['code']}'}',
                style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
          ]),
        ),
        if (!widget.wide && b != null)
          IconButton(tooltip: 'Conversation details', onPressed: () => _detailsSheet(t), icon: const Icon(Icons.info_outline)),
        IconButton(
          tooltip: t['starred'] == true ? 'Unstar' : 'Star',
          onPressed: () => _state({'starred': t['starred'] != true}, t['starred'] == true ? 'Unstarred' : 'Starred'),
          icon: Icon(t['starred'] == true ? Icons.star : Icons.star_border, color: AppTheme.clay),
        ),
        IconButton(
          tooltip: t['priority'] == true ? 'Remove priority' : 'Mark as priority',
          onPressed: () => _state({'priority': t['priority'] != true}, t['priority'] == true ? 'Priority removed' : 'Marked as priority'),
          icon: Icon(t['priority'] == true ? Icons.flag : Icons.outlined_flag, color: AppTheme.danger),
        ),
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) => switch (v) {
            'unread' => _state({'read': false}, 'Marked as unread'),
            'archive' => _state({'archived': t['archived'] != true}, t['archived'] == true ? 'Moved to inbox' : 'Archived'),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'unread', child: Text('Mark as unread')),
            PopupMenuItem(value: 'archive', child: Text(t['archived'] == true ? 'Move to inbox' : 'Archive')),
          ],
        ),
      ]),
    );
  }

  Widget _messages(Map<String, dynamic> t) {
    final msgs = (t['messages'] as List).cast<Map>();
    final scheduled = (t['scheduled'] as List).cast<Map>();
    final note = t['note'] as Map?;
    return ListView(controller: _scroll, padding: const EdgeInsets.all(14), children: [
      _noteBox(note),
      const SizedBox(height: 10),
      if (msgs.isEmpty)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No messages yet. Log what the guest sent you (phone, WhatsApp or the booking channel), or write to them.',
            textAlign: TextAlign.center,
            style: AppFonts.sans(color: AppTheme.muted),
          ),
        ),
      for (final m in msgs) _bubble(m),
      for (final s in scheduled) _scheduled(s),
    ]);
  }

  Widget _noteBox(Map? note) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppTheme.warningSoft.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const Icon(Icons.sticky_note_2_outlined, size: 16, color: AppTheme.warningInk),
          const SizedBox(width: 6),
          Expanded(child: Text('Team note', style: AppFonts.sans(fontWeight: FontWeight.w700, color: AppTheme.warningInk))),
          if (_canWrite)
            TextButton(
              onPressed: () async {
                if (_editingNote) {
                  try {
                    await widget.api.put('$_base/note', {'text': _note.text});
                    if (mounted) showSnack(context, 'Note saved');
                    await _load();
                  } catch (e) {
                    if (mounted) showSnack(context, errorText(e));
                  }
                }
                setState(() => _editingNote = !_editingNote);
              },
              child: Text(_editingNote ? 'Save' : note == null ? 'Add' : 'Edit'),
            ),
        ]),
        if (_editingNote)
          TextField(key: const Key('team-note'), controller: _note, maxLines: 3, decoration: const InputDecoration(isDense: true))
        else if (note != null)
          Text(note['text'] as String)
        else
          Text('Only your team can see this. It is never sent to the guest.', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.warningInk)),
        if (note != null && !_editingNote)
          Text('Last edited by ${note['edited_by']} · ${_clock(note['edited_at'] as String)}',
              style: AppFonts.sans(fontSize: 11.5, color: AppTheme.muted)),
      ]),
    );
  }

  Widget _bubble(Map m) {
    final out = m['direction'] == 'out';
    return Align(
      alignment: out ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: out ? AppTheme.forest : AppTheme.paper,
            border: out ? null : Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SelectableText(m['body'] as String, style: AppFonts.sans(color: out ? Colors.white : AppTheme.ink)),
            const SizedBox(height: 3),
            Text(
              '${m['by']} · ${_clock(m['at'] as String)}${m['scheduled'] == true ? ' · scheduled' : ''}'
              '${m['logged_by'] != null ? ' · logged by ${m['logged_by']}' : ''}${out ? ' · recorded' : ''}',
              style: AppFonts.sans(fontSize: 11, color: out ? Colors.white70 : AppTheme.muted),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _scheduled(Map s) {
    final held = s['status'] == 'held';
    final id = (s['id'] as num).toInt();
    Future<void> act(Future<dynamic> Function() f, String done) async {
      try {
        await f();
        if (mounted) showSnack(context, done);
        _load();
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
    }

    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          border: Border.all(color: held ? AppTheme.danger : AppTheme.borderStrong, style: BorderStyle.solid),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s['body'] as String),
          const SizedBox(height: 4),
          Text(
            held ? 'Held — ${s['held_reason']}. Check it, then send or reschedule.' : 'Scheduled for ${_clock(s['send_at'] as String)} · by ${s['by_name']}',
            style: AppFonts.sans(fontSize: 12, color: held ? AppTheme.danger : AppTheme.muted),
          ),
          if (_canWrite)
            Wrap(spacing: 4, children: [
              TextButton(onPressed: () => act(() => widget.api.post('$_base/scheduled/$id/send-now', {}), 'Sent'), child: const Text('Send now')),
              TextButton(
                onPressed: () async {
                  final when = await _pickWhen(DateTime.tryParse(s['send_at'] as String)?.toLocal());
                  if (when != null) {
                    await act(() => widget.api.patch('$_base/scheduled/$id', {'send_at': when.toUtc().toIso8601String()}), 'Rescheduled');
                  }
                },
                child: const Text('Edit time'),
              ),
              TextButton(onPressed: () => act(() => widget.api.delete('$_base/scheduled/$id'), 'Scheduled message cancelled'), child: const Text('Cancel')),
            ]),
        ]),
      ),
    );
  }

  Widget _composer() => Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppTheme.border))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ChoiceChip(label: const Text('Reply'), selected: !_logGuest, onSelected: (_) => setState(() => _logGuest = false)),
            const SizedBox(width: 6),
            ChoiceChip(
                key: const Key('log-guest'), label: const Text('Log guest message'), selected: _logGuest, onSelected: (_) => setState(() => _logGuest = true)),
            const Spacer(),
            TextButton.icon(
                key: const Key('quick-replies'), onPressed: _quickReplies, icon: const Icon(Icons.bolt, size: 18), label: const Text('Quick replies')),
          ]),
          const SizedBox(height: 6),
          CallbackShortcuts(
            bindings: {const SingleActivator(LogicalKeyboardKey.enter, control: true): _send},
            child: TextField(
              key: const Key('composer'),
              controller: _compose,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: _logGuest ? 'Paste what the guest sent' : 'Write a message — {guest_first_name} and other variables are filled in',
                isDense: true,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: Text(
                _logGuest
                    ? 'Saved as a message from the guest.'
                    : 'Replies are recorded here; no guest channel is connected yet, so send it on the guest\'s channel too.',
                style: AppFonts.sans(fontSize: 11.5, color: AppTheme.muted),
              ),
            ),
            if (!_logGuest) TextButton(onPressed: _sendLater, child: const Text('Send later')),
            SizedBox(
              width: 110,
              child: ElevatedButton(
                key: const Key('send-message'),
                onPressed: _sending ? null : _send,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                child: Text(_logGuest ? 'Log' : 'Send'),
              ),
            ),
          ]),
        ]),
      );

  void _detailsSheet(Map<String, dynamic> t) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * 0.75, child: _details(t)),
      );

  Widget _details(Map<String, dynamic> t) => _Details(
        t: t,
        onManage: (id) async {
          final changed = await showBookingDetail(context, api: widget.bookings, bookingId: id, membership: widget.membership);
          if (changed == true) _load();
        },
        onPut: _putInReply,
      );
}

class _Details extends StatefulWidget {
  const _Details({required this.t, required this.onManage, required this.onPut});

  final Map<String, dynamic> t;
  final ValueChanged<int> onManage;
  final ValueChanged<String> onPut;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final b = widget.t['booking'] as Map?;
    final d = widget.t['details'] as Map?;
    final info = (widget.t['property_info'] as List).cast<Map>().where((i) => _q.isEmpty || '${i['label']} ${i['value']}'.toLowerCase().contains(_q)).toList();
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 90, child: Text(k, style: AppFonts.sans(fontSize: 13, color: AppTheme.muted))),
            Expanded(child: Text(v, style: AppFonts.sans(fontSize: 13.5))),
          ]),
        );
    return Container(
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppTheme.border), borderRadius: BorderRadius.circular(AppTheme.radiusCard)),
      child: ListView(padding: const EdgeInsets.all(14), children: [
        Text('Trip details', style: AppFonts.sans(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        if (b == null)
          Text('No booking linked.', style: AppFonts.sans(color: AppTheme.muted))
        else ...[
          Align(alignment: Alignment.centerLeft, child: StatusPill(b['status'] as String)),
          const SizedBox(height: 6),
          kv('Dates', '${prettyDate(b['check_in'] as String)} → ${prettyDate(b['check_out'] as String, year: true)}'),
          if (d != null) ...[
            kv('Nights', '${d['nights']}'),
            kv('Guests', '${d['adults']} adult(s)${(d['children'] as num) > 0 ? ', ${d['children']} child(ren)' : ''}'),
            if (((d['guest'] as Map?)?['phone'] as String?)?.isNotEmpty == true) kv('Phone', (d['guest'] as Map)['phone'] as String),
            if (((d['guest'] as Map?)?['email'] as String?)?.isNotEmpty == true) kv('Email', (d['guest'] as Map)['email'] as String),
            const SizedBox(height: 6),
            Text('Your payout ${money(d['total'] as num)} before taxes', style: AppFonts.sans(fontWeight: FontWeight.w600)),
            kv('Paid', money(d['paid'] as num)),
            kv('Balance', money(d['balance'] as num)),
            if (d['payout_note'] != null) Text(d['payout_note'] as String, style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
          ],
          const SizedBox(height: 6),
          OutlinedButton(onPressed: () => widget.onManage((b['id'] as num).toInt()), child: const Text('Manage reservation')),
        ],
        const Divider(height: 26),
        Text('Property info', style: AppFonts.sans(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        TextField(
          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          decoration: const InputDecoration(hintText: 'Search property info', prefixIcon: Icon(Icons.search, size: 18), isDense: true),
        ),
        const SizedBox(height: 6),
        if (info.isEmpty) Text('Nothing here yet. Fill in the listing to use it in replies.', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
        for (final i in info)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i['label'] as String, style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
              Text(i['value'] as String, maxLines: 4, overflow: TextOverflow.ellipsis),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 28)),
                onPressed: () => widget.onPut('${i['label']}: ${i['value']}'),
                child: const Text('Put in reply'),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Quick replies: starters (shared) + your own (editable). Returns the body.
class _QuickReplies extends StatefulWidget {
  const _QuickReplies({required this.api, required this.initial});

  final ApiClient api;
  final Map<String, dynamic> initial;

  @override
  State<_QuickReplies> createState() => _QuickRepliesState();
}

class _QuickRepliesState extends State<_QuickReplies> {
  late Map<String, dynamic> _qr = widget.initial;
  String _q = '';

  Future<void> _reload() async {
    final r = await widget.api.get('/api/messages/quick-replies');
    if (mounted) setState(() => _qr = (r as Map).cast());
  }

  Future<void> _edit([Map? existing]) async {
    final shortcut = TextEditingController(text: existing?['shortcut'] as String? ?? '');
    final title = TextEditingController(text: existing?['title'] as String? ?? '');
    final body = TextEditingController(text: existing?['body'] as String? ?? '');
    final vars = (_qr['variables'] as List).cast<String>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'New quick reply' : 'Edit quick reply'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: shortcut, decoration: const InputDecoration(labelText: 'Shortcut, e.g. wifi')),
              const SizedBox(height: 10),
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              TextField(controller: body, maxLines: 5, decoration: const InputDecoration(labelText: 'Reply')),
              const SizedBox(height: 8),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final v in vars)
                  ActionChip(
                    visualDensity: VisualDensity.compact,
                    label: Text('{$v}', style: AppFonts.sans(fontSize: 11.5)),
                    onPressed: () => body.text = '${body.text}{$v}',
                  ),
              ]),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      final payload = {'shortcut': shortcut.text, 'title': title.text, 'body': body.text};
      try {
        existing == null
            ? await widget.api.post('/api/messages/quick-replies', payload)
            : await widget.api.patch('/api/messages/quick-replies/${existing['id']}', payload);
        await _reload();
      } catch (e) {
        if (mounted) showSnack(context, errorText(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    bool match(Map r) => _q.isEmpty || '${r['shortcut']} ${r['title']} ${r['body']}'.toLowerCase().contains(_q);
    final own = (_qr['own'] as List).cast<Map>().where(match).toList();
    final starter = (_qr['starter'] as List).cast<Map>().where(match).toList();
    Widget tile(Map r, {bool mine = false}) => ListTile(
          dense: true,
          title: Text('${r['title']}  ·  /${r['shortcut']}'),
          subtitle: Text(r['body'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.pop(context, r['body'] as String),
          trailing: mine
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Edit', onPressed: () => _edit(r), icon: const Icon(Icons.edit_outlined, size: 18)),
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () async {
                      await widget.api.delete('/api/messages/quick-replies/${r['id']}');
                      _reload();
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                  ),
                ])
              : null,
        );
    return AlertDialog(
      title: Row(children: [
        const Expanded(child: Text('Quick replies')),
        TextButton.icon(onPressed: () => _edit(), icon: const Icon(Icons.add), label: const Text('New')),
      ]),
      content: SizedBox(
        width: 560,
        height: 480,
        child: Column(children: [
          TextField(
            autofocus: true,
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase().replaceAll('/', '')),
            decoration: const InputDecoration(hintText: 'Search or type a shortcut', prefixIcon: Icon(Icons.search), isDense: true),
          ),
          Expanded(
            child: ListView(children: [
              if (own.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text('Yours', style: AppFonts.sans(fontWeight: FontWeight.w700))),
              for (final r in own) tile(r, mine: true),
              Padding(padding: const EdgeInsets.only(top: 10), child: Text('Starter replies (shared)', style: AppFonts.sans(fontWeight: FontWeight.w700))),
              for (final r in starter) tile(r),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _ReplyTimes extends StatefulWidget {
  const _ReplyTimes({required this.api});

  final ApiClient api;

  @override
  State<_ReplyTimes> createState() => _ReplyTimesState();
}

class _ReplyTimesState extends State<_ReplyTimes> {
  String _range = '7d';
  Map<String, dynamic>? _d;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.api.get('/api/messages/reply-times?range=$_range');
    if (mounted) setState(() => _d = (r as Map).cast());
  }

  @override
  Widget build(BuildContext context) {
    final d = _d;
    Widget stat(String label, String value) => Expanded(
          child: Column(children: [
            Text(value, style: AppFonts.sans(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(label, style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
          ]),
        );
    return AlertDialog(
      title: const Text('Reply times'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'today', label: Text('Today')),
              ButtonSegment(value: '7d', label: Text('Last 7 days')),
              ButtonSegment(value: '30d', label: Text('Last 30 days')),
            ],
            selected: {_range},
            onSelectionChanged: (v) {
              _range = v.first;
              _load();
            },
          ),
          const SizedBox(height: 16),
          if (d == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            Row(children: [
              stat('Typical reply', _mins(d['typical_minutes'] as num?)),
              stat('Average reply', _mins(d['average_minutes'] as num?)),
              stat('Within 1 hour', d['within_hour'] == null ? '—' : '${d['within_hour']}%'),
              stat('Replies', '${d['replies']}'),
            ]),
            const SizedBox(height: 14),
            Text('By agent', style: AppFonts.sans(fontWeight: FontWeight.w700)),
            Text('Agent figures are shown to the host and to co-hosts with full access to messages.',
                style: AppFonts.sans(fontSize: 12, color: AppTheme.muted)),
            for (final a in (d['by_agent'] as List).cast<Map>())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(a['agent'] as String),
                trailing: Text('${_mins(a['typical_minutes'] as num?)} typical · ${a['replies']} replies'),
              ),
            if ((d['by_agent'] as List).isEmpty) Text('No replies in this range.', style: AppFonts.sans(color: AppTheme.muted)),
          ],
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}
