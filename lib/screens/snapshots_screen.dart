import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../format.dart';
import '../widgets.dart';
import 'snapshot_screen.dart';

class SnapshotsScreen extends StatefulWidget {
  const SnapshotsScreen({super.key, required this.state, required this.visible});
  final AppState state;
  final bool visible;

  @override
  State<SnapshotsScreen> createState() => _SnapshotsScreenState();
}

class _SnapshotsScreenState extends State<SnapshotsScreen> {
  List<Map<String, dynamic>>? _snapshots;
  String? _error;
  bool _loading = false;
  bool _loadedOnce = false;

  @override
  void didUpdateWidget(SnapshotsScreen old) {
    super.didUpdateWidget(old);
    if (widget.visible && !old.visible && !_loadedOnce) _load();
  }

  Future<void> _load() async {
    if (!widget.state.destination.isValid) {
      setState(() => _error = 'Set the destination in Settings first.');
      return;
    }
    setState(() {
      _loading = true;
      _loadedOnce = true;
    });
    try {
      final s = await widget.state.agent.snapshots(widget.state.destination);
      if (!mounted) return;
      setState(() {
        _snapshots = s;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Groups like `restic forget --group-by host,tags` does, newest first.
  Map<String, List<Map<String, dynamic>>> _groups() {
    final g = <String, List<Map<String, dynamic>>>{};
    for (final s in _snapshots ?? const <Map<String, dynamic>>[]) {
      final tags = ((s['tags'] as List?) ?? const []).cast<String>().toList()..sort();
      final key = '${tags.isEmpty ? '(no tag)' : tags.join(', ')} @ ${s['hostname']}';
      (g[key] ??= []).add(s);
    }
    for (final l in g.values) {
      l.sort((a, b) => (b['time'] as String).compareTo(a['time'] as String));
    }
    return Map.fromEntries(g.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.state.retention;
    final groups = _groups();
    final total = _snapshots?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Snapshots'),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: PageBody(onRefresh: _load, children: [
        if (_loading) const LinearProgressIndicator(),
        Text('${widget.state.destination.label} · $total snapshot(s) · '
            '${r.cleanup ? 'keeping last ${r.keepLast} per source' : 'automatic clean-up off'}'),
        if (total > 0)
          Text('Tap a snapshot to browse it and restore files.',
              style: Theme.of(context).textTheme.bodySmall),
        if (_error != null) Notice(_error!),
        if (!_loadedOnce && !_loading)
          Center(
            child: FilledButton.tonalIcon(
                onPressed: _load, icon: const Icon(Icons.cloud_download_outlined), label: const Text('Load snapshots')),
          ),
        if (_snapshots != null && total == 0) const Notice('No snapshots yet.', kind: NoticeKind.info),
        for (final e in groups.entries)
          SectionCard(title: e.key, children: [
            for (final (i, s) in e.value.indexed) _tile(context, s, outside: r.cleanup && i >= r.keepLast),
          ]),
      ]),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> s, {required bool outside}) {
    final summary = s['summary'] as Map<String, dynamic>?;
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(outside ? Icons.auto_delete_outlined : Icons.inventory_2_outlined,
          color: outside ? cs.outline : cs.primary),
      title: Text(fmtTime(s['time'] as String?)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text([
          s['short_id'] as String? ?? '',
          '${((s['paths'] as List?) ?? const []).length} path(s)',
          if (summary != null) '${fmtBytes(summary['total_bytes_processed'] as num?)} total',
          if (summary != null) '+${fmtBytes(summary['data_added'] as num?)}',
        ].join(' · ')),
        if (outside)
          Text('Will be deleted by the next clean-up', style: TextStyle(color: cs.error, fontSize: 12)),
      ]),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SnapshotScreen(state: widget.state, snapshot: s)),
      ),
    );
  }
}
