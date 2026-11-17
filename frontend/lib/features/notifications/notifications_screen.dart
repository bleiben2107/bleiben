import 'package:flutter/material.dart';

import '../../core/network/api_client.dart';
import '../../core/theme/app_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../auth/auth_models.dart';
import '../bookings/booking_dialogs.dart';
import '../bookings/bookings_api.dart';

/// Inbox → Notifications (MVP plan §2.6 R1): booking/payment/cancellation
/// alerts with their email/SMS delivery status.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.api, required this.bookings, required this.membership, this.onChanged});

  final ApiClient api;
  final BookingsApi bookings;
  final Membership membership;
  final VoidCallback? onChanged;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

const _deliveryLabels = {'email': 'Guest email', 'sms': 'Guest SMS', 'owner_email': 'Team email'};

IconData _kindIcon(String k) => switch (k) {
      'booking_confirmed' => Icons.event_available,
      'booking_created' => Icons.add_task,
      'booking_cancelled' => Icons.event_busy,
      'payment_received' => Icons.payments_outlined,
      'payment_failed' => Icons.money_off,
      'sync_conflict' => Icons.warning_amber_rounded,
      'sync_error' => Icons.sync_problem,
      _ => Icons.notifications_none,
    };

String _when(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  return '${prettyDate(ymd(t))}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _filter = 'all';
  String _kind = 'all';
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final q = {
      if (_filter == 'unread') 'unread': 'true',
      if (_filter == 'failed') 'failed': 'true',
      if (_kind != 'all') 'kind': _kind,
    };
    try {
      final r = await widget.api.get('/api/notifications?${q.entries.map((e) => '${e.key}=${e.value}').join('&')}');
      if (mounted) setState(() => _data = (r as Map).cast());
    } catch (e) {
      if (mounted) setState(() => _error = errorText(e));
    }
  }

  Future<void> _markAll() async {
    await widget.api.post('/api/notifications/read-all', {});
    widget.onChanged?.call();
    _load();
  }

  Future<void> _open(Map n) async {
    if (n['read'] != true) {
      await widget.api.post('/api/notifications/${n['id']}/read', {});
      widget.onChanged?.call();
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(n['title'] as String),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n['body'] as String),
            const SizedBox(height: 6),
            Text('${n['kind_label']} · ${_when(n['created_at'] as String)}', style: AppFonts.sans(fontSize: 12.5, color: AppTheme.muted)),
            const Divider(height: 22),
            Text('Delivery', style: AppFonts.sans(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (n['muted'] == true) Text('Turned off in Settings → Notifications, so nothing was sent.', style: AppFonts.sans(color: AppTheme.muted)),
            if ((n['deliveries'] as List).isEmpty && n['muted'] != true) Text('In-app only.', style: AppFonts.sans(color: AppTheme.muted)),
            for (final d in (n['deliveries'] as List).cast<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Icon(
                    d['status'] == 'sent' ? Icons.check_circle : d['status'] == 'failed' ? Icons.error_outline : Icons.remove_circle_outline,
                    size: 16,
                    color: d['status'] == 'sent' ? AppTheme.success : d['status'] == 'failed' ? AppTheme.danger : AppTheme.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${_deliveryLabels[d['channel']] ?? d['channel']} · ${d['to'] ?? '—'} · ${switch (d['status']) {
                        'sent' => 'sent',
                        'failed' => 'failed — ${d['error'] ?? ''}',
                        'logged' => 'logged (no provider set up)',
                        _ => 'skipped',
                      }}',
                    ),
                  ),
                ]),
              ),
          ]),
        ),
        actions: [
          if (n['booking_id'] != null && widget.membership.can('bookings.read'))
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                showBookingDetail(context, api: widget.bookings, bookingId: (n['booking_id'] as num).toInt(), membership: widget.membership);
              },
              child: Text('Open ${n['booking_code']}'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final items = ((d?['items'] as List?) ?? const []).cast<Map>();
    final kinds = ((d?['kinds'] as Map?) ?? const {}).cast<String, String>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'all', label: Text('All')),
            ButtonSegment(value: 'unread', label: Text('Unread')),
            ButtonSegment(value: 'failed', label: Text('Delivery failed')),
          ],
          selected: {_filter},
          onSelectionChanged: (v) {
            _filter = v.first;
            _load();
          },
        ),
        DropdownButton<String>(
          value: kinds.containsKey(_kind) ? _kind : 'all',
          underline: const SizedBox.shrink(),
          items: [const DropdownMenuItem(value: 'all', child: Text('All types')), for (final e in kinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) {
            _kind = v ?? 'all';
            _load();
          },
        ),
        TextButton.icon(key: const Key('mark-all-read'), onPressed: _markAll, icon: const Icon(Icons.done_all, size: 18), label: const Text('Mark all read')),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: d == null
            ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
            : items.isEmpty
                ? Center(child: Text(_filter == 'unread' ? "You're all caught up." : 'No notifications yet. Booking and payment alerts appear here.', style: AppFonts.sans(color: AppTheme.muted)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = items[i];
                        final failed = (n['deliveries'] as List).cast<Map>().any((x) => x['status'] == 'failed');
                        final unread = n['read'] != true;
                        return ListTile(
                          key: Key('notification-${n['id']}'),
                          onTap: () => _open(n),
                          leading: CircleAvatar(backgroundColor: AppTheme.sage, child: Icon(_kindIcon(n['kind'] as String), color: AppTheme.forest, size: 20)),
                          title: Text(n['title'] as String, style: AppFonts.sans(fontWeight: unread ? FontWeight.w700 : FontWeight.w500)),
                          subtitle: Text('${n['body']}\n${_when(n['created_at'] as String)}', maxLines: 3, overflow: TextOverflow.ellipsis),
                          isThreeLine: true,
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (failed) const Tooltip(message: 'A message failed to send', child: Icon(Icons.error_outline, color: AppTheme.danger, size: 18)),
                            if (unread) Container(margin: const EdgeInsets.only(left: 6), width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.clay, shape: BoxShape.circle)),
                          ]),
                        );
                      },
                    ),
                  ),
      ),
    ]);
  }
}
