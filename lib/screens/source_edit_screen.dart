import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';
import 'folder_picker.dart';

class SourceEditScreen extends StatefulWidget {
  const SourceEditScreen({super.key, required this.state, this.source});
  final AppState state;
  final BackupSource? source;

  @override
  State<SourceEditScreen> createState() => _SourceEditScreenState();
}

class _SourceEditScreenState extends State<SourceEditScreen> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.source?.name ?? '');
  late final _id = TextEditingController(text: widget.source?.id ?? '');
  late final _excludes = TextEditingController(text: widget.source?.excludes.join('\n') ?? '');
  late final _container = TextEditingController(text: widget.source?.hook.container ?? '');
  late final _appContainer = TextEditingController(text: widget.source?.hook.appContainer ?? '');
  late final List<String> _paths = List.of(widget.source?.paths ?? const []);
  late HookType _hook = widget.source?.hook.type ?? HookType.none;
  late bool _idTouched = widget.source != null;

  bool get _isNew => widget.source == null;

  @override
  void dispose() {
    for (final c in [_name, _id, _excludes, _container, _appContainer]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _browse() async {
    final p = await FolderPicker.pick(context, widget.state.agent,
        initialPath: _paths.isNotEmpty ? _paths.last : null);
    if (p != null && !_paths.contains(p)) setState(() => _paths.add(p));
  }

  Future<void> _typePath() async {
    final c = TextEditingController(text: '/mnt/ssd/');
    final p = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add path'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Absolute path on the Pi'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Add')),
        ],
      ),
    );
    c.dispose();
    final v = p?.trim() ?? '';
    if (v.isEmpty || !mounted) return;
    if (!v.startsWith('/')) return showSnack(context, 'Use an absolute path (starting with /)', error: true);
    if (!_paths.contains(v)) setState(() => _paths.add(v));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_paths.isEmpty) return showSnack(context, 'Add at least one folder', error: true);
    final id = _id.text.trim();
    if (widget.state.sources.any((s) => s.id == id && s.id != widget.source?.id)) {
      return showSnack(context, 'Another source already uses the tag "$id"', error: true);
    }
    if (!_isNew && id != widget.source!.id) {
      final ok = await confirm(context,
          title: 'Change tag?',
          content: Text('Snapshots are grouped by tag. Old "${widget.source!.id}" snapshots will no longer be '
              'cleaned up together with new "$id" snapshots.'),
          ok: 'Change');
      if (!ok) return;
    }
    final s = BackupSource(
      id: id,
      name: _name.text.trim(),
      paths: _paths,
      excludes: _excludes.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      hook: SourceHook(
        type: _hook,
        container: _hook == HookType.none ? '' : _container.text.trim(),
        appContainer: _hook == HookType.nextcloud ? _appContainer.text.trim() : '',
      ),
    );
    await widget.state.upsertSource(s, replacingId: widget.source?.id);
    if (mounted) Navigator.pop(context);
  }

  String? _containerValidator(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    return containerPattern.hasMatch(t) ? null : 'Invalid container name';
  }

  @override
  Widget build(BuildContext context) {
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 13);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New source' : 'Edit ${widget.source!.name}'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: Form(
        key: _form,
        child: PageBody(children: [
          SectionCard(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Immich'),
              maxLength: 80,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
              onChanged: (v) {
                if (!_idTouched) _id.text = slugify(v);
              },
            ),
            TextFormField(
              controller: _id,
              decoration: const InputDecoration(
                labelText: 'Tag / id',
                helperText: 'restic tag; old backups are cleaned up per tag (a-z, 0-9, -)',
              ),
              style: mono,
              onChanged: (_) => _idTouched = true,
              validator: (v) => idPattern.hasMatch(v?.trim() ?? '') ? null : '1-40 characters: a-z, 0-9, -',
            ),
          ]),
          SectionCard(
            title: 'Folders on the Pi',
            trailing: IconButton(tooltip: 'Type a path', onPressed: _typePath, icon: const Icon(Icons.keyboard)),
            children: [
              if (_paths.isEmpty) const ListTile(title: Text('No folders yet')),
              for (final p in _paths)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(p, style: mono),
                  trailing: IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _paths.remove(p)),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: OutlinedButton.icon(
                  onPressed: _browse,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Browse the Pi…'),
                ),
              ),
            ],
          ),
          SectionCard(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _excludes,
              decoration: const InputDecoration(
                labelText: 'Exclude patterns',
                helperText: 'One restic --exclude pattern per line, e.g. /mnt/ssd/x/*/cache',
                alignLabelWithHint: true,
              ),
              style: mono,
              minLines: 3,
              maxLines: 10,
            ),
          ]),
          SectionCard(padding: const EdgeInsets.all(16), children: [
            DropdownButtonFormField<HookType>(
              initialValue: _hook,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Database hook (runs before the upload)'),
              items: [
                for (final h in HookType.values) DropdownMenuItem(value: h, child: Text(h.label)),
              ],
              onChanged: (h) => setState(() {
                _hook = h ?? HookType.none;
                if (_hook == HookType.nextcloud) {
                  if (_container.text.isEmpty) _container.text = 'nextcloud_db';
                  if (_appContainer.text.isEmpty) _appContainer.text = 'nextcloud_app';
                }
              }),
            ),
            if (_hook != HookType.none)
              TextFormField(
                controller: _container,
                decoration: InputDecoration(
                    labelText: _hook == HookType.postgres ? 'PostgreSQL container' : 'MariaDB container'),
                style: mono,
                validator: _containerValidator,
              ),
            if (_hook == HookType.nextcloud)
              TextFormField(
                controller: _appContainer,
                decoration: const InputDecoration(labelText: 'Nextcloud app container (for occ)'),
                style: mono,
                validator: _containerValidator,
              ),
            if (_hook != HookType.none) ...[
              const SizedBox(height: 12),
              Notice(
                'The dump is written to the Pi\'s staging folder and included in this source\'s snapshot. '
                '${_hook == HookType.nextcloud ? 'Nextcloud is in maintenance mode during dump + upload. ' : ''}'
                'Hooks are skipped in dry runs.',
                kind: NoticeKind.info,
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}
