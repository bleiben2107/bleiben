import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart';
import '../bookings/bookings_api.dart';

/// Channel Manager — R1 iCal sync (MVP plan §2.7): connected calendars,
/// connect/map/disconnect, export links, sync history/errors and conflicts.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key, required this.api, required this.bookings, required this.membership});

  final ApiClient api;
  final BookingsApi bookings;
  final Membership membership;

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

String _when(String? iso) {
  if (iso == null) return 'never';
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${prettyDate(ymd(t))}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  Map<String, dynamic>? _data;
  List<Map>? _conflicts;
  String? _error;
  bool _busy = false;

  bool get _canWrite => widget.membership.can('channels.write');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/api/channels');
      final c = await widget.api.get('/api/channels/conflicts/list?status=all');
      if (!mounted) return;
      setState(() {
        _data = (r as Map).cast();
        _conflicts = (c as List).cast<Map>();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showSnack(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
      _load();
    }
  }

  Future<void> _connect([Map? existing]) async {
    final rooms = ((_data?['exports'] as List?) ?? const []).cast<Map>();
    if (rooms.isEmpty) return showSnack(context, 'Add a property with rooms first.');
    final r = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ConnectDialog(channels: (_data!['channels'] as Map).cast(), rooms: rooms, existing: existing),
    );
    if (r == null) return;
    await _run(() async {
      final res = existing == null
          ? await widget.api.post('/api/channels', r) as Map
          : await widget.api.patch('/api/channels/${existing['id']}', r) as Map;
      if (!mounted) return;
      final first = res['first_sync'] as Map?;
      showSnack(
        context,
        existing != null
            ? 'Calendar updated'
            : first?['ok'] == true
                ? 'Connected · ${first!['added']} imported, ${first['skipped_echo']} already in Bleiben${(first['conflicts'] as num) > 0 ? ', ${first['conflicts']} conflict(s) to review' : ''}'
                : 'Connected, but the first sync failed: ${first?['error']}',
      );
    });
  }

  Future<void> _sync(Map c) => _run(() async {
        final r = await widget.api.post('/api/channels/${c['id']}/sync', {}) as Map;
        if (mounted) {
          showSnack(context, r['ok'] == true ? 'Synced · ${r['added']} new, ${r['updated']} changed, ${r['removed']} removed' : 'Sync failed: ${r['error']}');
        }
      });

  Future<void> _disconnect(Map c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Disconnect ${c['name']}?'),
        content: const Text('Syncing stops and future dates imported from this calendar are released in Bleiben. Remove our export link in the other site too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), style: TextButton.styleFrom(foregroundColor: AppTheme.danger), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.api.delete('/api/channels/${c['id']}');
      if (mounted) showSnack(context, 'Disconnected · future imported stays released');
    });
  }

  Future<void> _history(Map c) async {
    final runs = (await widget.api.get('/api/channels/${c['id']}/history') as List).cast<Map>();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Sync history · ${c['name']}'),
        content: SizedBox(
          width: 520,
          height: 400,
          child: runs.isEmpty
              ? const Text('No syncs yet.')
              : ListView(children: [
                  for (final r in runs)
                    ListTile(
                      dense: true,
                      leading: Icon(r['status'] == 'ok' ? Icons.check_circle : Icons.error_outline, color: r['status'] == 'ok' ? AppTheme.success : AppTheme.danger),
                      title: Text(r['status'] == 'ok'
                          ? '${r['events']} events · ${r['added']} new · ${r['updated']} changed · ${r['removed']} removed${(r['conflicts'] as num) > 0 ? ' · ${r['conflicts']} conflict(s)' : ''}'
                          : '${r['error']}'),
                      subtitle: Text('${_when(r['at'] as String)} · ${r['duration_ms']} ms'),
                    ),
                ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _resolve(Map c) async {
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolve conflict'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sort it out with the guests first (move one stay, or cancel on one site), then note what you did.'),
            const SizedBox(height: 10),
            TextField(key: const Key('resolve-note'), controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'How was it resolved?')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          TextButton(key: const Key('resolve-save'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark resolved')),
        ],
      ),
    );
    if (ok == true) await _run(() => widget.api.post('/api/channels/conflicts/${c['id']}/resolve', {'note': note.text}));
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    if (d == null) return Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator());
    final conns = (d['connections'] as List).cast<Map>();
    final exports = (d['exports'] as List).cast<Map>();
    final open = (_conflicts ?? const []).where((c) => c['status'] == 'open').toList();
    return DefaultTabController(
      length: 3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(wide ? 32 : 12, 18, wide ? 32 : 12, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Channel Manager', style: AppFonts.sans(fontSize: 24, fontWeight: FontWeight.w600)),
                Text('Sync Airbnb, Booking.com and other calendars with iCal links. iCal isn\'t instant — calendars refresh every ${d['sync_every_minutes']} minutes.',
                    style: AppFonts.sans(color: AppTheme.muted)),
              ]),
            ),
            if (_canWrite)
              SizedBox(
                width: 200,
                child: ElevatedButton.icon(key: const Key('connect-calendar'), onPressed: _busy ? null : () => _connect(), icon: const Icon(Icons.add_link), label: const Text('Connect calendar')),
              ),
          ]),
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Connected (${conns.length})'),
            const Tab(text: 'Export links'),
            Tab(text: 'Conflicts${open.isEmpty ? '' : ' (${open.length})'}'),
          ]),
          Expanded(
            child: TabBarView(children: [
              _connections(conns),
              _exports(exports),
              _conflictList(),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _connections(List<Map> conns) {
    if (conns.isEmpty) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'No calendars connected yet.\n\n1. In Airbnb (Calendar → Availability → Connect calendars) or Booking.com (Calendar → Sync calendars), copy the export link.\n'
            '2. Click Connect calendar, paste it and pick the room.\n3. Paste our export link for that room back into the other site.',
            style: AppFonts.sans(color: AppTheme.muted, height: 1.5),
          ),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.only(top: 12), children: [
      for (final c in conns)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(c['status'] == 'error' ? Icons.sync_problem : Icons.sync, color: c['status'] == 'error' ? AppTheme.danger : AppTheme.forest),
                const SizedBox(width: 8),
                Expanded(child: Text('${c['name']}', style: AppFonts.sans(fontSize: 16, fontWeight: FontWeight.w700))),
                StatusPill(c['status'] == 'error' ? 'cancelled' : 'confirmed', label: c['status'] == 'error' ? 'Error' : 'Syncing'),
              ]),
              const SizedBox(height: 4),
              Text('${c['channel_label']} → ${c['property']} · ${c['room']} · ${c['url_masked']}', style: AppFonts.sans(color: AppTheme.muted, fontSize: 13.5)),
              Text('Last synced ${_when(c['last_sync_at'] as String?)} · last success ${_when(c['last_success_at'] as String?)}', style: AppFonts.sans(fontSize: 13)),
              if (c['last_error'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${c['last_error']} · retrying ${_when(c['next_sync_at'] as String?).replaceAll(' ago', '')}', style: AppFonts.sans(color: AppTheme.danger, fontSize: 13)),
                ),
              Wrap(spacing: 4, children: [
                if (_canWrite) TextButton.icon(onPressed: _busy ? null : () => _sync(c), icon: const Icon(Icons.refresh, size: 18), label: Text(c['status'] == 'error' ? 'Retry now' : 'Sync now')),
                TextButton(onPressed: () => _history(c), child: const Text('History')),
                if (_canWrite) TextButton(onPressed: () => _connect(c), child: const Text('Edit mapping')),
                if (_canWrite) TextButton(onPressed: () => _disconnect(c), style: TextButton.styleFrom(foregroundColor: AppTheme.danger), child: const Text('Disconnect')),
              ]),
            ]),
          ),
        ),
    ]);
  }

  Widget _exports(List<Map> exports) => ListView(padding: const EdgeInsets.only(top: 12), children: [
        Text('Paste a room\'s link into Airbnb / Booking.com so they close dates when the room is sold out or blocked in Bleiben. Keep links private.',
            style: AppFonts.sans(color: AppTheme.muted)),
        const SizedBox(height: 8),
        if (exports.isEmpty) Text('No rooms yet.', style: AppFonts.sans(color: AppTheme.muted)),
        for (final e in exports)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('${e['property']} · ${e['room']}'),
              subtitle: SelectableText('${e['url']}', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Copy link',
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: '${e['url']}'));
                    if (mounted) showSnack(context, 'Link copied');
                  },
                  icon: const Icon(Icons.copy),
                ),
                if (_canWrite)
                  IconButton(
                    tooltip: 'Reset link (the old one stops working)',
                    onPressed: () => _run(() => widget.api.post('/api/channels/exports/${e['room_id']}/regenerate', {})),
                    icon: const Icon(Icons.autorenew),
                  ),
              ]),
            ),
          ),
      ]);

  Widget _conflictList() {
    final list = _conflicts ?? const [];
    if (list.isEmpty) return Center(child: Text('No conflicts. Overlapping stays from synced calendars appear here.', style: AppFonts.sans(color: AppTheme.muted)));
    return ListView(padding: const EdgeInsets.only(top: 12), children: [
      for (final c in list)
        Card(
          margin: const EdgeInsets.only(bottom: 10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(c['status'] == 'open' ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: c['status'] == 'open' ? AppTheme.warningInk : AppTheme.success),
                const SizedBox(width: 8),
                Expanded(child: Text('${c['property']} · ${c['room']} · ${(c['dates'] as List).map((x) => prettyDate('$x')).join(', ')}', style: AppFonts.sans(fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 4),
              if (c['booking'] != null)
                Text('${c['channel_label']}: ${(c['booking'] as Map)['guest']} (${(c['booking'] as Map)['code']}) · ${prettyDate((c['booking'] as Map)['check_in'] as String)} → ${prettyDate((c['booking'] as Map)['check_out'] as String)}'),
              for (final o in (c['overlapping'] as List).cast<Map>())
                Text('Already booked: ${o['guest']} (${o['code']}) · ${bookingSources[o['source']] ?? o['source']} · ${prettyDate(o['check_in'] as String)} → ${prettyDate(o['check_out'] as String)}'),
              if (c['status'] != 'open') Text('Resolved by ${c['resolved_by']}: ${c['resolution']}', style: AppFonts.sans(color: AppTheme.muted)),
              if (c['status'] == 'open')
                Wrap(spacing: 4, children: [
                  if (c['booking'] != null)
                    TextButton(
                      onPressed: () => showBookingDetail(context, api: widget.bookings, bookingId: ((c['booking'] as Map)['id'] as num).toInt(), membership: widget.membership).then((_) => _load()),
                      child: const Text('Open imported stay'),
                    ),
                  if (_canWrite) TextButton(key: Key('resolve-${c['id']}'), onPressed: () => _resolve(c), child: const Text('Mark resolved')),
                ]),
            ]),
          ),
        ),
    ]);
  }
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.channels, required this.rooms, this.existing});

  final Map<String, dynamic> channels;
  final List<Map> rooms;
  final Map? existing;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  late String _channel = (widget.existing?['channel'] as String?) ?? 'airbnb';
  late int _room = ((widget.existing?['room_id'] ?? widget.rooms.first['room_id']) as num).toInt();
  late final _name = TextEditingController(text: (widget.existing?['name'] as String?) ?? '');
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final editing = widget.existing != null;
    return AlertDialog(
      title: Text(editing ? 'Edit calendar' : 'Connect a calendar'),
      content: SizedBox(
        width: 480,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _channel,
            decoration: const InputDecoration(labelText: 'Channel'),
            items: [for (final e in widget.channels.entries) DropdownMenuItem(value: e.key, child: Text('${e.value}'))],
            onChanged: (v) => setState(() => _channel = v ?? 'airbnb'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            key: const Key('channel-room'),
            initialValue: _room,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Bleiben room'),
            items: [for (final r in widget.rooms) DropdownMenuItem(value: (r['room_id'] as num).toInt(), child: Text('${r['property']} · ${r['room']}'))],
            onChanged: (v) => setState(() => _room = v ?? _room),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('channel-url'),
            controller: _url,
            decoration: InputDecoration(labelText: editing ? 'New iCal link (leave empty to keep)' : 'iCal export link (https://…ics)'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Name (optional)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
          key: const Key('channel-save'),
          onPressed: () {
            if (!editing && _url.text.trim().isEmpty) return;
            Navigator.pop(context, {
              'channel': _channel,
              'room_id': _room,
              if (_url.text.trim().isNotEmpty) 'url': _url.text.trim(),
              if (_name.text.trim().isNotEmpty) 'name': _name.text.trim(),
            });
          },
          child: Text(editing ? 'Save' : 'Connect'),
        ),
      ],
    );
  }
}
