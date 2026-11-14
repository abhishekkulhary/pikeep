import 'package:material_ui/material_ui.dart';

import '../agent_client.dart';
import '../widgets.dart';

/// Browses directories on the Pi (only under the agent's ALLOWED_ROOTS) and
/// returns the chosen absolute path.
class FolderPicker extends StatefulWidget {
  const FolderPicker({super.key, required this.agent, this.initialPath});
  final AgentClient agent;
  final String? initialPath;

  static Future<String?> pick(BuildContext context, AgentClient agent, {String? initialPath}) =>
      Navigator.push<String>(
        context,
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => FolderPicker(agent: agent, initialPath: initialPath),
        ),
      );

  @override
  State<FolderPicker> createState() => _FolderPickerState();
}

class _FolderPickerState extends State<FolderPicker> {
  String? _path;
  String? _parent;
  List<String> _dirs = const [];
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _open(widget.initialPath);
  }

  Future<void> _open(String? path) async {
    setState(() => _loading = true);
    try {
      final r = await widget.agent.browse(path);
      if (!mounted) return;
      setState(() {
        _path = r.path;
        _parent = r.parent;
        _dirs = r.dirs;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // An invalid initial path: fall back to the first allowed root.
      if (path != null && path == widget.initialPath && _path == null) return _open(null);
      setState(() {
        _error = e is AgentException ? e.message : e.toString();
        _loading = false;
      });
    }
  }

  String _child(String name) => _path!.endsWith('/') ? '$_path$name' : '$_path/$name';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_path ?? 'Choose a folder', overflow: TextOverflow.ellipsis),
        actions: [
          if (_path != null)
            TextButton(onPressed: () => Navigator.pop(context, _path), child: const Text('Select')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Notice(_error!)),
              if (_parent != null)
                ListTile(
                  leading: const Icon(Icons.arrow_upward),
                  title: const Text('..'),
                  subtitle: Text(_parent!),
                  onTap: () => _open(_parent),
                ),
              if (_dirs.isEmpty && _error == null)
                const ListTile(title: Text('No sub-folders')),
              for (final d in _dirs)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(d),
                  trailing: IconButton(
                    tooltip: 'Select $d',
                    icon: const Icon(Icons.check),
                    onPressed: () => Navigator.pop(context, _child(d)),
                  ),
                  onTap: () => _open(_child(d)),
                ),
            ]),
      bottomNavigationBar: _path == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, _path),
                  icon: const Icon(Icons.check),
                  label: Text('Use $_path', overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
              ),
            ),
    );
  }
}
