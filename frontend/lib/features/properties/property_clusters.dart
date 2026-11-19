part of 'properties_screen.dart';

// ── Clusters ─────────────────────────────────────────────────────────────────

/// Properties → Clusters: group listings that share a place (e.g. a 4BR
/// cottage sold whole, or as two 2BR floors) under one parent listing.
class _ClustersView extends StatefulWidget {
  const _ClustersView({required this.controller, required this.canWrite, required this.onOpenProperty});

  final PropertiesController controller;
  final bool canWrite;
  final void Function(int propertyId) onOpenProperty;

  @override
  State<_ClustersView> createState() => _ClustersViewState();
}

class _ClustersViewState extends State<_ClustersView> {
  List<PropertyCluster>? _clusters;
  Map<int, PropertySummary> _props = const {};
  String? _error;
  final Set<int> _open = {};

  PropertiesController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([c.clusters(), c.all()]);
      if (!mounted) return;
      setState(() {
        _clusters = r[0] as List<PropertyCluster>;
        _props = {for (final p in r[1] as List<PropertySummary>) p.id: p};
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _edit([PropertyCluster? cluster]) async {
    if (_props.length < 2) return _snack(context, 'You need at least two properties to make a cluster.');
    final taken = {
      for (final x in _clusters ?? const <PropertyCluster>[])
        if (x.id != cluster?.id) ...x.propertyIds,
    };
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _ClusterDialog(controller: c, cluster: cluster, properties: _props.values.toList(), taken: taken),
    );
    if (saved == true) {
      if (mounted) _snack(context, cluster == null ? 'Cluster created' : 'Cluster updated');
      _load();
    }
  }

  Future<void> _delete(PropertyCluster cluster) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove cluster "${cluster.name}"?'),
        content: const Text('Only the grouping is removed. The properties, their bookings and calendars stay as they are.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Remove cluster'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final error = await c.deleteCluster(cluster.id);
    if (!mounted) return;
    _snack(context, error ?? 'Cluster removed');
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _clusters;
    final header = Row(children: [
      Expanded(
        child: Text('Group listings of the same place: one parent listing and its child listings (e.g. whole villa + its floors).',
            style: AppFonts.sans(color: HomeColors.muted)),
      ),
      if (widget.canWrite)
        ElevatedButton.icon(
          key: const Key('new-cluster'),
          onPressed: () => _edit(),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('New cluster'),
        ),
    ]);
    if (_error != null) {
      return Column(children: [header, _Empty(icon: Icons.cloud_off_rounded, text: _error!, action: TextButton(onPressed: _load, child: const Text('Try again')))]);
    }
    if (list == null) return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
    TextStyle h = AppFonts.sans(fontSize: 12.5, color: HomeColors.muted, fontWeight: FontWeight.w600);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      const SizedBox(height: 14),
      if (list.isEmpty)
        const _Empty(icon: Icons.account_tree_outlined, text: 'No clusters yet. Create one to group listings of the same property.')
      else
        _panel(
          padding: EdgeInsets.zero,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                const SizedBox(width: 32),
                Expanded(flex: 6, child: Text('Cluster name', style: h)),
                Expanded(flex: 2, child: Text('Cluster ID', style: h)),
                Expanded(flex: 2, child: Text('Listings', style: h)),
                const SizedBox(width: 48),
              ]),
            ),
            for (final x in list) ...[
              const Divider(height: 1),
              InkWell(
                key: Key('cluster-${x.id}'),
                onTap: () => setState(() => _open.contains(x.id) ? _open.remove(x.id) : _open.add(x.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(_open.contains(x.id) ? Icons.remove_circle_outline : Icons.add_circle_outline, size: 20, color: HomeColors.muted),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: x.name, style: AppFonts.sans(fontWeight: FontWeight.w600)),
                        TextSpan(text: '  (${x.propertyIds.length} properties)', style: AppFonts.sans(color: HomeColors.muted, fontSize: 13)),
                      ])),
                    ),
                    Expanded(flex: 2, child: Text('${x.id}')),
                    Expanded(flex: 2, child: Text('${x.propertyIds.length}')),
                    SizedBox(
                      width: 48,
                      child: widget.canWrite
                          ? PopupMenuButton<String>(
                              tooltip: 'Manage ${x.name}',
                              onSelected: (v) => v == 'edit' ? _edit(x) : _delete(x),
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'edit', child: Text('Edit cluster')),
                                PopupMenuItem(value: 'delete', child: Text('Remove cluster')),
                              ],
                            )
                          : null,
                    ),
                  ]),
                ),
              ),
              if (_open.contains(x.id))
                Container(
                  color: HomeColors.mist,
                  padding: const EdgeInsets.fromLTRB(48, 10, 16, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('LISTINGS IN THIS CLUSTER', style: AppFonts.sans(fontSize: 11.5, color: HomeColors.muted, fontWeight: FontWeight.w700, letterSpacing: .5)),
                    const SizedBox(height: 6),
                    for (final id in [x.parentId, ...x.propertyIds.where((id) => id != x.parentId)])
                      _clusterListing(id, parent: id == x.parentId),
                  ]),
                ),
            ],
          ]),
        ),
    ]);
  }

  Widget _clusterListing(int id, {required bool parent}) {
    final p = _props[id];
    return Padding(
      padding: EdgeInsets.only(left: parent ? 0 : 28, top: 4, bottom: 4),
      child: InkWell(
        onTap: p == null ? null : () => widget.onOpenProperty(id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white, border: Border.all(color: HomeColors.line), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            if (!parent) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.subdirectory_arrow_right_rounded, size: 18, color: HomeColors.muted)),
            CircleAvatar(
              radius: 14,
              backgroundColor: parent ? const Color(0xFFE8452C) : AppTheme.forest,
              child: Text((p?.displayTitle ?? '?').characters.first.toUpperCase(), style: AppFonts.sans(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p?.displayTitle ?? 'Property #$id (removed)', overflow: TextOverflow.ellipsis, style: AppFonts.sans(fontWeight: FontWeight.w600)),
                if (p != null)
                  Text('${p.serialId} · ${p.roomCount} room type${p.roomCount == 1 ? '' : 's'}', style: AppFonts.sans(fontSize: 12, color: HomeColors.muted)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: parent ? const Color(0xFFFDE8E4) : AppTheme.successSoft, borderRadius: BorderRadius.circular(6)),
              child: Text(parent ? 'PARENT' : 'CHILD',
                  style: AppFonts.sans(fontSize: 11, fontWeight: FontWeight.w700, color: parent ? const Color(0xFFC0392B) : AppTheme.forest)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ClusterDialog extends StatefulWidget {
  const _ClusterDialog({required this.controller, this.cluster, required this.properties, required this.taken});

  final PropertiesController controller;
  final PropertyCluster? cluster;
  final List<PropertySummary> properties;

  /// Properties already in another cluster.
  final Set<int> taken;

  @override
  State<_ClusterDialog> createState() => _ClusterDialogState();
}

class _ClusterDialogState extends State<_ClusterDialog> {
  late final _name = TextEditingController(text: widget.cluster?.name ?? '');
  late final Set<int> _ids = {...?widget.cluster?.propertyIds};
  late int? _parent = widget.cluster?.parentId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) return setState(() => _error = 'Give the cluster a name');
    if (_ids.length < 2) return setState(() => _error = 'Pick at least two properties');
    final parent = _parent != null && _ids.contains(_parent) ? _parent! : _ids.first;
    setState(() => (_saving = true, _error = null));
    final error = await widget.controller.saveCluster(
      id: widget.cluster?.id,
      name: _name.text.trim(),
      parentId: parent,
      propertyIds: [parent, ..._ids.where((id) => id != parent)],
    );
    if (!mounted) return;
    if (error != null) return setState(() => (_saving = false, _error = error));
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final props = widget.properties;
    return AlertDialog(
      title: Text(widget.cluster == null ? 'New cluster' : 'Edit cluster'),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            key: const Key('cluster-name'),
            controller: _name,
            autofocus: true,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Cluster name *', hintText: 'e.g. Snowberry Cottage Manali'),
          ),
          Text('Pick the listings, then mark the parent (the whole-place listing).', style: AppFonts.sans(fontSize: 13, color: HomeColors.muted)),
          const SizedBox(height: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 340),
              child: ListView(shrinkWrap: true, children: [
                for (final p in props)
                  Row(children: [
                    Checkbox(
                      key: Key('cluster-pick-${p.id}'),
                      value: _ids.contains(p.id),
                      onChanged: widget.taken.contains(p.id)
                          ? null
                          : (v) => setState(() {
                                v == true ? _ids.add(p.id) : _ids.remove(p.id);
                                if (_parent == null && v == true) _parent = p.id;
                                if (_parent == p.id && v != true) _parent = _ids.isEmpty ? null : _ids.first;
                              }),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.displayTitle, overflow: TextOverflow.ellipsis),
                        Text(widget.taken.contains(p.id) ? 'Already in another cluster' : p.serialId,
                            style: AppFonts.sans(fontSize: 12, color: HomeColors.muted)),
                      ]),
                    ),
                    if (_ids.contains(p.id))
                      ChoiceChip(
                        key: Key('cluster-parent-${p.id}'),
                        label: Text(_parent == p.id ? 'Parent' : 'Make parent'),
                        selected: _parent == p.id,
                        onSelected: (_) => setState(() => _parent = p.id),
                      ),
                  ]),
              ]),
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: AppFonts.sans(color: AppTheme.danger))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          key: const Key('save-cluster'),
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(minimumSize: const Size(110, 44)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
