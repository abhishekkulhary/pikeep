import 'package:material_ui/material_ui.dart';

import '../agent_client.dart';
import '../app_state.dart';
import '../format.dart';
import '../widgets.dart';
import 'restore_guide_screen.dart';

/// Browse one snapshot on OneDrive and restore all of it or a selection.
class SnapshotScreen extends StatefulWidget {
  const SnapshotScreen({super.key, required this.state, required this.snapshot});
  final AppState state;
  final Map<String, dynamic> snapshot;

  @override
  State<SnapshotScreen> createState() => _SnapshotScreenState();
}

class _SnapshotScreenState extends State<SnapshotScreen> {
  AppState get state => widget.state;
  String get _id => widget.snapshot['id'] as String;

  String? _dir; // null = the snapshot's top level (the paths it was made of)
  List<Map<String, dynamic>> _entries = const [];
  bool _truncated = false;
  final Set<String> _selected = {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open(null);
  }

  Future<void> _open(String? dir) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final m = await state.agent.snapshotLs(state.destination, _id, dir: dir);
      if (!mounted) return;
      setState(() {
        _dir = dir;
        _entries = ((m['entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
        _truncated = m['truncated'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is AgentException ? e.message : e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// One level up, or back to the top once above the backed-up paths.
  String? get _parent {
    final dir = _dir;
    if (dir == null) return null;
    final roots = ((widget.snapshot['paths'] as List?) ?? const []).cast<String>();
    if (roots.contains(dir)) return '';
    final i = dir.lastIndexOf('/');
    return i <= 0 ? '' : dir.substring(0, i);
  }

  Future<void> _restore({required bool whole}) async {
    final paths = whole ? <String>[] : (_selected.toList()..sort());
    final choice = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _RestoreSheet(
        snapshot: widget.snapshot,
        paths: paths,
        restoreRoot: '${(state.info?['requiredMount'] as String?)?.isNotEmpty == true ? state.info!['requiredMount'] : '/mnt/ssd'}/restore',
      ),
    );
    if (choice == null || !mounted) return;
    final err = await state.startRestore(_id, paths: paths, inPlace: choice);
    if (err != null && mounted) showSnack(context, err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.snapshot;
    final tags = ((s['tags'] as List?) ?? const []).join(', ');
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(tags.isEmpty ? 'Snapshot' : tags),
        actions: [
          IconButton(
            tooltip: 'Restore guide',
            icon: const Icon(Icons.help_outline),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const RestoreGuideScreen())),
          ),
        ],
      ),
      body: Column(children: [
        Material(
          color: cs.surfaceContainerLow,
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(fmtTime(s['time'] as String?)),
            subtitle: Text('${s['short_id'] ?? _id.substring(0, 8)} · ${s['hostname'] ?? ''}'),
          ),
        ),
        if (_dir != null)
          Material(
            color: cs.surfaceContainerLow,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.arrow_upward),
              title: Text(_dir!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              onTap: _loading ? null : () => _open(_parent == '' ? null : _parent),
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        Expanded(
          child: _error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Notice(_error!))
              : ListView(children: [
                  if (_truncated)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Notice('Only the first 5000 entries are shown.', kind: NoticeKind.warning),
                    ),
                  if (!_loading && _entries.isEmpty) const ListTile(title: Text('Empty folder')),
                  for (final e in _entries) _entryTile(e, text),
                ]),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: state.busy || state.running ? null : () => _restore(whole: true),
                icon: const Icon(Icons.settings_backup_restore),
                label: const Text('Whole snapshot'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _selected.isEmpty || state.busy || state.running ? null : () => _restore(whole: false),
                icon: const Icon(Icons.restore),
                label: Text(_selected.isEmpty ? 'Select items' : 'Restore ${_selected.length}'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _entryTile(Map<String, dynamic> e, TextTheme text) {
    final path = e['path'] as String;
    final isDir = e['type'] == 'dir';
    // Selecting a folder covers everything inside it.
    final coveredByParent = _selected.any((p) => p != path && path.startsWith('$p/'));
    return CheckboxListTile(
      controlAffinity: ListTileControlAffinity.leading,
      value: coveredByParent || _selected.contains(path),
      onChanged: coveredByParent
          ? null
          : (v) => setState(() => v == true ? _selected.add(path) : _selected.remove(path)),
      secondary: isDir
          ? IconButton(
              tooltip: 'Open',
              icon: const Icon(Icons.chevron_right),
              onPressed: _loading ? null : () => _open(path),
            )
          : null,
      title: Row(children: [
        Icon(isDir ? Icons.folder_outlined : Icons.insert_drive_file_outlined, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(e['name'] as String? ?? path, overflow: TextOverflow.ellipsis)),
      ]),
      subtitle: Text(
        [
          if (_dir == null) path,
          if (!isDir && e['size'] != null) fmtBytes(e['size'] as num),
          if (e['mtime'] != null) fmtTime(e['mtime'] as String),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: text.bodySmall,
      ),
    );
  }
}

/// Where to restore to. Returns true for "original location", false for a
/// separate folder, null if cancelled.
class _RestoreSheet extends StatefulWidget {
  const _RestoreSheet({required this.snapshot, required this.paths, required this.restoreRoot});
  final Map<String, dynamic> snapshot;
  final List<String> paths;
  final String restoreRoot;

  @override
  State<_RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends State<_RestoreSheet> {
  bool _inPlace = false;
  bool _understood = false;

  @override
  Widget build(BuildContext context) {
    final what = widget.paths.isEmpty
        ? 'the whole snapshot from ${fmtTime(widget.snapshot['time'] as String?)}'
        : '${widget.paths.length} selected item(s)';
    final hasDb = ((widget.snapshot['paths'] as List?) ?? const [])
        .any((p) => (p as String).endsWith('-db.sql'));
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text('Restore $what', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          RadioGroup<bool>(
            groupValue: _inPlace,
            onChanged: (v) => setState(() {
              _inPlace = v ?? false;
              _understood = false;
            }),
            child: Column(children: [
              RadioListTile<bool>(
                value: false,
                title: const Text('Separate folder (safe)'),
                subtitle: Text('Into a new folder under ${widget.restoreRoot}. Nothing existing is touched; '
                    'copy back what you need.'),
              ),
              RadioListTile<bool>(
                value: true,
                title: const Text('Original location'),
                subtitle: const Text('Writes the files back where they came from and overwrites what is '
                    'there now. For a replaced disk or a broken service.'),
              ),
            ]),
          ),
          if (_inPlace) ...[
            const SizedBox(height: 8),
            const Notice(
              'Stop the app that owns these files first (docker compose down), or it may write over them '
              'while they are restored. Files that exist now but not in the snapshot are left alone.',
              kind: NoticeKind.warning,
            ),
            CheckboxListTile(
              value: _understood,
              onChanged: (v) => setState(() => _understood = v ?? false),
              title: const Text('I understand that current files will be overwritten'),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
          if (hasDb) ...[
            const SizedBox(height: 8),
            Notice(
              'This snapshot includes a database dump. Files are restored; loading the database is a '
              'separate step — see the restore guide.',
              kind: NoticeKind.info,
              action: TextButton(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const RestoreGuideScreen())),
                child: const Text('Guide'),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _inPlace && !_understood ? null : () => Navigator.pop(context, _inPlace),
            style: _inPlace
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                    minimumSize: const Size.fromHeight(48))
                : FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            icon: const Icon(Icons.restore),
            label: Text(_inPlace ? 'Restore and overwrite' : 'Restore to a separate folder'),
          ),
          const SizedBox(height: 8),
          const Text('The restore runs on the Pi like a backup: you can close the app and follow it on the '
              'Backup tab.', textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}
