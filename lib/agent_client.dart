import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'models.dart';
import 'storage.dart';

class AgentException implements Exception {
  AgentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class HostKeyMismatchException extends AgentException {
  HostKeyMismatchException(this.expected, this.actual)
      : super('The Pi\'s SSH host key changed!\n'
            'Expected: $expected\nGot:      $actual\n'
            'If you reinstalled the Pi this is expected — reset the host key in Settings. '
            'Otherwise someone may be intercepting the connection.');
  final String expected;
  final String actual;
}

/// Runs `sudo -n /usr/local/bin/pi-backup-agent <args>` over one reused SSH
/// connection. The app never transfers data or opens tunnels.
class AgentClient {
  AgentClient(this._store);

  static const agentPath = '/usr/local/bin/pi-backup-agent';

  final Store _store;
  ConnectionSettings? _settings;
  SSHClient? _client;
  Future<SSHClient>? _connecting;

  void configure(ConnectionSettings s) {
    if (_settings != null && _settings!.sameAs(s)) return;
    close();
    _settings = s;
  }

  void close() {
    final c = _client;
    _client = null;
    if (c != null) unawaited(c.close());
  }

  // ---- connection -----------------------------------------------------------

  Future<SSHClient> _ensure() {
    final c = _client;
    if (c != null && !c.isClosed) return Future.value(c);
    return _connecting ??= _connect().whenComplete(() => _connecting = null);
  }

  Future<SSHClient> _connect() async {
    final s = _settings;
    if (s == null || !s.isComplete) {
      throw AgentException('Set host, user and a password or private key in Settings.');
    }

    List<SSHKeyPair>? identities;
    if (s.privateKey.trim().isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(
            s.privateKey.trim(), s.passphrase.isEmpty ? null : s.passphrase);
      } catch (e) {
        throw AgentException('Could not read the private key: $e');
      }
    }

    final SSHSocket socket;
    try {
      socket = await SSHSocket.connect(s.host.trim(), s.port,
          timeout: const Duration(seconds: 10));
    } catch (e) {
      throw AgentException('Cannot reach ${s.host}:${s.port} — is Tailscale on? ($e)');
    }

    HostKeyMismatchException? mismatch;
    final client = SSHClient(
      socket,
      username: s.username.trim(),
      identities: identities,
      onPasswordRequest: s.password.isEmpty ? null : () => s.password,
      onVerifyHostKey: (String type, Uint8List fingerprint) async {
        // fingerprint = UTF-8 bytes of "SHA256:<base64>"
        final seen = '$type ${utf8.decode(fingerprint)}';
        final known = _store.hostKey(s.hostId);
        if (known == null) {
          await _store.setHostKey(s.hostId, seen);
          return true;
        }
        if (known == seen) return true;
        mismatch = HostKeyMismatchException(known, seen);
        return false;
      },
    );

    try {
      await client.authenticated.timeout(const Duration(seconds: 20));
    } catch (e) {
      unawaited(client.close());
      if (mismatch != null) throw mismatch!;
      if (e is SSHAuthError) {
        throw AgentException('SSH login failed for ${s.username}@${s.host} — check password/key.');
      }
      if (e is TimeoutException) throw AgentException('SSH login timed out.');
      throw AgentException('SSH connection failed: $e');
    }
    _client = client;
    return client;
  }

  // ---- command execution ----------------------------------------------------

  static String shellQuote(String s) =>
      RegExp(r'^[A-Za-z0-9_./:=@%+-]+$').hasMatch(s)
          ? s
          : "'${s.replaceAll("'", "'\\''")}'";

  Future<SSHSession> _open(String cmd) async {
    try {
      return await (await _ensure()).execute(cmd);
    } on AgentException {
      rethrow;
    } catch (_) {
      // Stale connection (phone slept, network changed): reconnect once.
      close();
      return (await _ensure()).execute(cmd);
    }
  }

  Future<({int? code, String out, String err})> _run(
    List<String> args, {
    String? stdin,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final cmd = ['sudo', '-n', agentPath, ...args].map(shellQuote).join(' ');
    final session = await _open(cmd);

    final outF = session.stdout.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));
    final errF = session.stderr.fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d));
    if (stdin != null) session.stdin.add(utf8.encode(stdin));
    await session.stdin.close();

    try {
      await session.done.timeout(timeout);
    } on TimeoutException {
      session.close();
      throw AgentException('The Pi did not answer within ${timeout.inSeconds} s.');
    }
    final out = utf8.decode((await outF).takeBytes(), allowMalformed: true);
    final err = utf8.decode((await errF).takeBytes(), allowMalformed: true);
    return (code: session.exitCode, out: out, err: err);
  }

  String _explain(String err, int? code) {
    final e = err.trim();
    if (e.contains('a password is required') || e.contains('a terminal is required')) {
      return 'sudo asks for a password — run pi/install.sh on the Pi to add the sudoers rule.';
    }
    if (e.contains('command not found') || e.contains('No such file')) {
      return 'pi-backup-agent is not installed on the Pi — run pi/install.sh.';
    }
    if (e.contains('is not allowed to execute') || e.contains('not in the sudoers')) {
      return 'sudo refused to run the agent — check /etc/sudoers.d/pi-backup-agent.';
    }
    return e.isNotEmpty ? e : 'The agent failed (exit code $code).';
  }

  Future<Map<String, dynamic>> _json(
    List<String> args, {
    String? stdin,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final r = await _run(args, stdin: stdin, timeout: timeout);
    final lines = r.out.trim().split('\n').where((l) => l.trim().startsWith('{'));
    if (lines.isEmpty) throw AgentException(_explain(r.err, r.code));
    final Map<String, dynamic> m;
    try {
      m = jsonDecode(lines.last) as Map<String, dynamic>;
    } catch (_) {
      throw AgentException('Unexpected answer from the agent: ${r.out.trim()}');
    }
    if (m['ok'] != true) {
      throw AgentException((m['error'] as String?) ?? 'Unknown agent error');
    }
    return m;
  }

  // ---- agent API --------------------------------------------------------------

  Future<Map<String, dynamic>> info() => _json(['info']);

  Future<List<({String name, String type})>> remotes() async {
    final m = await _json(['remotes']);
    return [
      for (final r in (m['remotes'] as List).cast<Map<String, dynamic>>())
        (name: r['name'] as String, type: (r['type'] as String?) ?? ''),
    ];
  }

  Future<({String path, String? parent, List<String> dirs})> browse(String? path) async {
    final m = await _json(['browse', if (path != null && path.isNotEmpty) path]);
    return (
      path: m['path'] as String,
      parent: m['parent'] as String?,
      dirs: List<String>.from(m['dirs'] as List),
    );
  }

  Future<String> init(Destination d) async {
    final m = await _json(['init', '--remote', d.remote, '--path', d.path],
        timeout: const Duration(minutes: 3));
    return (m['message'] as String?) ?? 'Repository created';
  }

  Future<String> start(Map<String, dynamic> job) async {
    final m = await _json(['start'], stdin: jsonEncode(job));
    return m['runId'] as String;
  }

  Future<Map<String, dynamic>> status() => _json(['status'], timeout: const Duration(seconds: 30));

  Future<void> cancel() => _json(['cancel']);

  Future<String> log([int lines = 500]) async {
    final r = await _run(['log', '$lines']);
    if (r.out.trimLeft().startsWith('{"ok":false')) {
      final m = jsonDecode(r.out.trim()) as Map<String, dynamic>;
      throw AgentException(m['error'] as String);
    }
    if (r.code != 0 && r.out.isEmpty) throw AgentException(_explain(r.err, r.code));
    return r.out;
  }

  Future<List<Map<String, dynamic>>> snapshots(Destination d) async {
    final m = await _json(['snapshots', '--remote', d.remote, '--path', d.path],
        timeout: const Duration(minutes: 3));
    return (m['snapshots'] as List).cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> schedule() => _json(['schedule']);

  Future<Map<String, dynamic>> setSchedule(Map<String, dynamic> body) =>
      _json(['schedule-set'], stdin: jsonEncode(body));
}
