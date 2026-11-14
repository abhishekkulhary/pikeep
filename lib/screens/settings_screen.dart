import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../models.dart';
import '../widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.state});
  final AppState state;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  AppState get state => widget.state;

  final _connForm = GlobalKey<FormState>();
  late final _host = TextEditingController();
  late final _port = TextEditingController();
  late final _user = TextEditingController();
  late final _password = TextEditingController();
  late final _key = TextEditingController();
  late final _passphrase = TextEditingController();
  late final _repoPath = TextEditingController();
  late final _keep = TextEditingController();
  bool _showPassword = false;
  bool _testing = false;
  bool _loadingRemotes = false;
  List<({String name, String type})>? _remotes;
  String? _remotesError;
  bool _filled = false;

  @override
  void initState() {
    super.initState();
    state.addListener(_fillOnce);
    _fillOnce();
  }

  /// Settings load asynchronously at start-up; fill the fields once they arrive.
  void _fillOnce() {
    final c = state.connection;
    if (_filled && _host.text.isNotEmpty) return;
    _host.text = c.host;
    _port.text = '${c.port}';
    _user.text = c.username;
    _password.text = c.password;
    _key.text = c.privateKey;
    _passphrase.text = c.passphrase;
    _repoPath.text = state.destination.path;
    _keep.text = '${state.retention.keepLast}';
    _filled = c.isComplete;
  }

  @override
  void dispose() {
    state.removeListener(_fillOnce);
    for (final c in [_host, _port, _user, _password, _key, _passphrase, _repoPath, _keep]) {
      c.dispose();
    }
    super.dispose();
  }

  ConnectionSettings _connFromFields() => ConnectionSettings(
        host: _host.text.trim(),
        port: int.tryParse(_port.text.trim()) ?? 22,
        username: _user.text.trim(),
        password: _password.text,
        privateKey: _key.text.trim().isEmpty ? '' : '${_key.text.trim()}\n',
        passphrase: _passphrase.text,
      );

  Future<void> _saveAndTest() async {
    if (!_connForm.currentState!.validate()) return;
    _filled = true;
    setState(() => _testing = true);
    await state.saveConnection(_connFromFields());
    final ok = await state.connect();
    if (ok) await state.refreshStatus();
    if (!mounted) return;
    setState(() => _testing = false);
    showSnack(context, ok ? 'Connected to ${state.info?['hostname']}' : state.connError ?? 'Failed', error: !ok);
    if (ok && _remotes == null) await _loadRemotes();
  }

  Future<void> _loadRemotes() async {
    setState(() => _loadingRemotes = true);
    try {
      final r = await state.agent.remotes();
      if (mounted) {
        setState(() {
          _remotes = r;
          _remotesError = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _remotesError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingRemotes = false);
    }
  }

  Future<void> _saveRepoPath() async {
    final p = _repoPath.text.trim();
    if (!isValidRepoPath(p)) {
      showSnack(context, 'Use letters, digits, . _ / - (no ..)', error: true);
      return;
    }
    await state.setDestination(Destination(remote: state.destination.remote, path: p));
  }

  Future<void> _initRepo() async {
    final d = state.destination;
    final ok = await confirm(context,
        title: 'Initialize repository?',
        content: Text('Creates a new encrypted restic repository at ${d.label} using the password file on the Pi.\n\n'
            'Only needed once. Keep a copy of the restic password off the Pi (password manager) — '
            'without it the backups cannot be restored.'),
        ok: 'Initialize');
    if (!ok || !mounted) return;
    try {
      final msg = await state.agent.init(d);
      if (mounted) showSnack(context, msg.split('\n').first);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    }
  }

  Future<void> _forgetHostKey() async {
    final ok = await confirm(context,
        title: 'Reset host key?',
        content: const Text('The next connection will trust whatever key the server presents. '
            'Only do this if you know the Pi\'s SSH key changed (e.g. after reinstalling).'),
        ok: 'Reset',
        destructive: true);
    if (ok) await state.forgetHostKey();
  }

  void _setKeep(int v) {
    final k = v.clamp(Retention.minKeep, Retention.maxKeep);
    _keep.text = '$k';
    state.setRetention(Retention(keepLast: k, cleanup: state.retention.cleanup));
  }

  @override
  Widget build(BuildContext context) {
    final mono = const TextStyle(fontFamily: 'monospace', fontSize: 12);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => PageBody(children: [
          _connectionCard(mono),
          _destinationCard(),
          _retentionCard(),
          if (state.info != null) _aboutCard(),
        ]),
      ),
    );
  }

  Widget _connectionCard(TextStyle mono) {
    final hostKey = state.storedHostKey;
    return Form(
      key: _connForm,
      child: SectionCard(title: 'SSH connection', padding: const EdgeInsets.fromLTRB(0, 8, 0, 16), children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextFormField(
                  controller: _host,
                  decoration: const InputDecoration(labelText: 'Host', hintText: 'raspberrypi.local or a Tailscale name'),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: TextFormField(
                  controller: _port,
                  decoration: const InputDecoration(labelText: 'Port'),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    final p = int.tryParse(v?.trim() ?? '');
                    return p == null || p < 1 || p > 65535 ? 'Invalid' : null;
                  },
                ),
              ),
            ]),
            TextFormField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'User'),
              autocorrect: false,
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password (optional if a key is set)',
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              validator: (v) => (v?.isEmpty ?? true) && _key.text.trim().isEmpty
                  ? 'Enter a password or a private key'
                  : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _key,
              decoration: const InputDecoration(
                labelText: 'Private key (optional)',
                hintText: '-----BEGIN OPENSSH PRIVATE KEY-----',
                alignLabelWithHint: true,
              ),
              style: mono,
              minLines: 2,
              maxLines: 6,
              autocorrect: false,
            ),
            TextFormField(
              controller: _passphrase,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Key passphrase (optional)'),
            ),
            const SizedBox(height: 4),
            Text('Password, key and passphrase are stored in the system keychain.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _testing ? null : _saveAndTest,
                  icon: _testing
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering),
                  label: const Text('Save & test connection'),
                ),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.fingerprint),
          title: const Text('Trusted host key'),
          subtitle: Text(hostKey ?? 'None yet — stored on first connect', style: mono),
          trailing: hostKey == null
              ? null
              : TextButton(onPressed: _forgetHostKey, child: const Text('Reset')),
        ),
      ]),
    );
  }

  Widget _destinationCard() {
    final d = state.destination;
    final names = {...?_remotes?.map((r) => r.name), if (d.remote.isNotEmpty) d.remote}.toList()..sort();
    return SectionCard(title: 'Destination', padding: const EdgeInsets.fromLTRB(16, 8, 16, 16), children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(names.join(',') + d.remote),
            initialValue: d.remote.isEmpty ? null : d.remote,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'rclone remote'),
            items: [
              for (final n in names)
                DropdownMenuItem(
                  value: n,
                  child: Text([n, ?_remotes?.where((r) => r.name == n).firstOrNull?.type]
                      .where((s) => s.isNotEmpty)
                      .join('  ·  ')),
                ),
            ],
            onChanged: (v) {
              if (v != null) state.setDestination(Destination(remote: v, path: d.path));
            },
          ),
        ),
        IconButton(
          tooltip: 'Load remotes from the Pi',
          onPressed: _loadingRemotes ? null : _loadRemotes,
          icon: _loadingRemotes
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.sync),
        ),
      ]),
      if (_remotesError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Notice(_remotesError!)),
      Focus(
        onFocusChange: (f) {
          if (!f) _saveRepoPath();
        },
        child: TextField(
          controller: _repoPath,
          decoration: const InputDecoration(
            labelText: 'Repository path on the remote',
            helperText: 'Saved when you leave the field',
          ),
          autocorrect: false,
          onSubmitted: (_) => _saveRepoPath(),
        ),
      ),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: state.connState == ConnState.connected && d.isValid ? _initRepo : null,
          icon: const Icon(Icons.add_box_outlined),
          label: const Text('Initialize repository (first time only)'),
        ),
      ),
    ]);
  }

  Widget _retentionCard() {
    final r = state.retention;
    return SectionCard(title: 'Keep & clean up', children: [
      SwitchListTile(
        value: r.cleanup,
        onChanged: (v) => state.setRetention(Retention(keepLast: r.keepLast, cleanup: v)),
        title: const Text('Automatically delete older backups'),
        subtitle: const Text('After each backup, remove snapshots beyond the number below and free the space'),
      ),
      ListTile(
        enabled: r.cleanup,
        title: const Text('Backups to keep per source'),
        subtitle: Text('Latest ${r.keepLast} snapshot(s) of each source are kept'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            onPressed: r.cleanup && r.keepLast > Retention.minKeep ? () => _setKeep(r.keepLast - 1) : null,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 44,
            child: TextField(
              controller: _keep,
              enabled: r.cleanup,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true),
              onSubmitted: (v) => _setKeep(int.tryParse(v) ?? r.keepLast),
            ),
          ),
          IconButton(
            onPressed: r.cleanup && r.keepLast < Retention.maxKeep ? () => _setKeep(r.keepLast + 1) : null,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ]),
      ),
      if (r.cleanup && r.keepLast == 1)
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Notice('With only 1 backup kept, a damaged or incomplete snapshot leaves no fallback.',
              kind: NoticeKind.warning),
        ),
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('Clean-up only touches sources whose backup succeeded in that run, '
            'so a failed backup never deletes your older good copies.'),
      ),
    ]);
  }

  Widget _aboutCard() {
    final i = state.info!;
    String s(String k) => '${i[k] ?? '–'}';
    return SectionCard(title: 'Pi', children: [
      ListTile(dense: true, title: const Text('Agent'), trailing: Text(s('agentVersion'))),
      ListTile(dense: true, title: const Text('Host'), trailing: Text('${s('hostname')} (${s('kernel')})')),
      ListTile(dense: true, title: const Text('restic'), trailing: Text(s('restic').split(' ').take(2).join(' '))),
      ListTile(dense: true, title: const Text('rclone'), trailing: Text(s('rclone'))),
      ListTile(
          dense: true,
          title: const Text('Allowed roots'),
          trailing: Text(((i['allowedRoots'] as List?) ?? const []).join(', '))),
    ]);
  }
}
