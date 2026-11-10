import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'stay.dart';
import 'stays_controller.dart';

class StaysScreen extends StatefulWidget {
  const StaysScreen({super.key, required this.auth, required this.stays});

  final AuthController auth;
  final StaysController stays;

  @override
  State<StaysScreen> createState() => _StaysScreenState();
}

class _StaysScreenState extends State<StaysScreen> {
  @override
  void initState() {
    super.initState();
    widget.stays.refresh();
  }

  Future<void> _confirmDelete(Stay stay) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete stay?'),
        content: Text('Remove "${stay.title}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.stays.remove(stay);
    }
  }

  void _openForm({Stay? stay}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _StayForm(stays: widget.stays, existing: stay),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stays = widget.stays;
    final auth = widget.auth;

    return AnimatedBuilder(
      animation: stays,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Bleiben'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: PopupMenuButton<String>(
                  icon: const Icon(Icons.account_circle_outlined),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      enabled: false,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.displayName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            auth.email,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'logout',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 8),
                          Text('Sign out'),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (value) async {
                    if (value == 'logout') {
                      stays.clear();
                      await auth.logout();
                    }
                  },
                ),
              ),
            ],
          ),
          body: _buildBody(stays),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openForm(),
            backgroundColor: AppTheme.forest,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add),
            label: const Text('Add stay'),
          ),
        );
      },
    );
  }

  Widget _buildBody(StaysController stays) {
    if (stays.busy && stays.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (stays.error != null && stays.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(stays.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: stays.refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (stays.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hotel_outlined, size: 64, color: AppTheme.moss.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'No stays yet',
              style: GoogleFonts.fraunces(
                fontSize: 22,
                color: AppTheme.ink.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 8),
            const Text('Tap + to add your first stay',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: stays.refresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: stays.items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final stay = stays.items[i];
          return _StayCard(
            stay: stay,
            onEdit: () => _openForm(stay: stay),
            onDelete: () => _confirmDelete(stay),
          );
        },
      ),
    );
  }
}

// ── Stay card ────────────────────────────────────────────────────────────────

class _StayCard extends StatelessWidget {
  const _StayCard({
    required this.stay,
    required this.onEdit,
    required this.onDelete,
  });

  final Stay stay;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    final parts = iso.split('-');
    if (parts.length < 3) return iso;
    return '${parts[2]}/${parts[1]}/${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.forest.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.hotel_outlined, color: AppTheme.forest),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stay.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.location_on_outlined,
                            size: 14, color: Colors.grey),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            stay.location,
                            style: const TextStyle(
                                fontSize: 13, color: Colors.grey),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (stay.checkIn != null || stay.checkOut != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined,
                              size: 13, color: Colors.grey),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${_fmtDate(stay.checkIn)} → ${_fmtDate(stay.checkOut)}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (stay.notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        stay.notes,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.ink.withValues(alpha: 0.6)),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.grey),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add / edit form sheet ─────────────────────────────────────────────────────

class _StayForm extends StatefulWidget {
  const _StayForm({required this.stays, this.existing});

  final StaysController stays;
  final Stay? existing;

  @override
  State<_StayForm> createState() => _StayFormState();
}

class _StayFormState extends State<_StayForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _locationCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _checkInCtrl;
  late final TextEditingController _checkOutCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _locationCtrl = TextEditingController(text: e?.location ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _checkInCtrl = TextEditingController(text: e?.checkIn ?? '');
    _checkOutCtrl = TextEditingController(text: e?.checkOut ?? '');
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    _checkInCtrl.dispose();
    _checkOutCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController ctrl) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      ctrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final stay = Stay(
      id: widget.existing?.id ?? 0,
      title: _titleCtrl.text.trim(),
      location: _locationCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      checkIn: _checkInCtrl.text.trim().isEmpty ? null : _checkInCtrl.text.trim(),
      checkOut: _checkOutCtrl.text.trim().isEmpty ? null : _checkOutCtrl.text.trim(),
    );

    final ok = await widget.stays.save(stay);
    if (ok && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final stays = widget.stays;
    final isEdit = widget.existing != null;

    return AnimatedBuilder(
      animation: stays,
      builder: (context, _) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      isEdit ? 'Edit stay' : 'New stay',
                      style: GoogleFonts.fraunces(
                          fontSize: 24, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleCtrl,
                  decoration: const InputDecoration(labelText: 'Title *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationCtrl,
                  decoration: const InputDecoration(labelText: 'Location *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _checkInCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Check-in',
                          suffixIcon: Icon(Icons.calendar_today_outlined,
                              size: 18),
                        ),
                        onTap: () => _pickDate(_checkInCtrl),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _checkOutCtrl,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Check-out',
                          suffixIcon: Icon(Icons.calendar_today_outlined,
                              size: 18),
                        ),
                        onTap: () => _pickDate(_checkOutCtrl),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                if (stays.error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    stays.error!,
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: stays.busy ? null : _save,
                  child: stays.busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(isEdit ? 'Save changes' : 'Add stay'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

