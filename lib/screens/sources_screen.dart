import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';
import 'source_edit_screen.dart';

class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key, required this.state});
  final AppState state;

  Future<void> _edit(BuildContext context, [BackupSource? s]) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SourceEditScreen(state: state, source: s)),
      );

  Future<void> _delete(BuildContext context, BackupSource s) async {
    final ok = await confirm(context,
        title: 'Delete "${s.name}"?',
        content: const Text('Only the app\'s source definition is removed. '
            'Existing snapshots on OneDrive are not touched.'),
        ok: 'Delete',
        destructive: true);
    if (ok) await state.deleteSource(s.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sources'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => state.restoreDefaultSources(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'defaults', child: Text('Add Immich + Nextcloud defaults')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => PageBody(children: [
          if (state.sources.isEmpty)
            const Notice('No sources yet. Add one, or use the menu to restore the Immich and Nextcloud defaults.',
                kind: NoticeKind.info),
          for (final s in state.sources)
            Card(
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _edit(context, s),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.name, style: Theme.of(context).textTheme.titleMedium),
                        Text('tag: ${s.id}${s.hook.type == HookType.none ? '' : ' · ${s.hook.type.label}'}',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 6),
                        for (final p in s.paths)
                          Text(p, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        if (s.excludes.isNotEmpty)
                          Text('${s.excludes.length} exclude pattern(s)',
                              style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, s),
                    ),
                  ]),
                ),
              ),
            ),
          const SizedBox(height: 64),
        ]),
      ),
    );
  }
}
