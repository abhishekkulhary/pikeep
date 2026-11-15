import 'dart:async';

import 'package:flutter/foundation.dart';

import 'agent_client.dart';
import 'models.dart';
import 'storage.dart';

enum ConnState { idle, connecting, connected, error }

class AppState extends ChangeNotifier {
  AppState(this.store) : agent = AgentClient(store);

  final Store store;
  final AgentClient agent;

  // persisted
  ConnectionSettings connection = const ConnectionSettings();
  List<BackupSource> sources = List.of(BackupSource.defaults);
  Set<String> selected = {'immich', 'nextcloud'};
  Destination destination = const Destination(remote: 'onedrive', path: 'pi-backup');
  Retention retention = const Retention();
  bool _retentionFromUser = false;
  bool _destinationFromUser = false;
  bool verify = false;

  // per run
  bool dryRun = false;

  // live
  ConnState connState = ConnState.idle;
  String? connError;
  Map<String, dynamic>? info;
  Map<String, dynamic>? status;
  String? statusError;
  bool busy = false;
  Timer? _poll;

  // automatic backups (systemd timer on the Pi)
  Map<String, dynamic>? scheduleInfo;
  String? scheduleError;
  Schedule get schedule => Schedule.fromJson(scheduleInfo?['schedule'] as Map<String, dynamic>?);
  bool get scheduleActive => scheduleInfo?['active'] == true;
  String? get scheduleNextRun => scheduleInfo?['nextRun'] as String?;
  Map<String, dynamic> get scheduleState =>
      (scheduleInfo?['state'] as Map<String, dynamic>?) ?? const {};

  bool get running => status?['running'] == true;

  /// Asks the shell to switch tabs (e.g. to Backup after starting a restore).
  final tabRequest = ValueNotifier<int?>(null);

  Map<String, dynamic> get health => (status?['health'] as Map<String, dynamic>?) ?? const {};
  bool get diskMounted => health['mounted'] != false && info?['mounted'] != false;
  bool get alertsOn => health['alerts'] == true;

  /// Kind of the current/last job: "backup" or "restore".
  String get jobKind => (jobState?['kind'] as String?) ?? 'backup';

  /// Finish time of the last real (non-dry-run) backup that completed.
  DateTime? get lastGoodBackup {
    for (final h in history) {
      final kind = (h['kind'] as String?) ?? 'backup';
      if (kind == 'backup' && h['dryRun'] != true && (h['status'] == 'success' || h['status'] == 'warning')) {
        return DateTime.tryParse((h['finishedAt'] ?? h['startedAt'] ?? '') as String);
      }
    }
    return null;
  }

  /// How long without a completed backup counts as overdue: twice the schedule's
  /// interval, or 8 days without a schedule.
  Duration get overdueAfter => switch (scheduleActive ? schedule.frequency : null) {
        ScheduleFrequency.daily => const Duration(days: 2),
        ScheduleFrequency.every2days => const Duration(days: 4),
        ScheduleFrequency.weekly => const Duration(days: 14),
        ScheduleFrequency.monthly => const Duration(days: 62),
        null => const Duration(days: 8),
      };

  bool get backupOverdue {
    final last = lastGoodBackup;
    if (last == null) return history.isNotEmpty || scheduleActive;
    return DateTime.now().difference(last) > overdueAfter;
  }
  Map<String, dynamic>? get jobState => status?['state'] as Map<String, dynamic>?;
  Map<String, dynamic>? get progress => status?['progress'] as Map<String, dynamic>?;
  List<Map<String, dynamic>> get history =>
      ((status?['history'] as List?) ?? const []).cast<Map<String, dynamic>>();
  String? get storedHostKey => store.hostKey(connection.hostId);

  Future<void> load() async {
    connection = await store.loadConnection();
    sources = store.loadSources() ?? List.of(BackupSource.defaults);
    selected = store.loadSelected() ?? sources.map((s) => s.id).toSet();
    final d = store.loadDestination();
    if (d != null) {
      destination = d;
      _destinationFromUser = true;
    }
    final r = store.loadRetention();
    if (r != null) {
      retention = r;
      _retentionFromUser = true;
    }
    verify = store.verifyAfterBackup;
    agent.configure(connection);
    notifyListeners();
    if (connection.isComplete) unawaited(refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    agent.close();
    super.dispose();
  }

  // ---- connection ---------------------------------------------------------

  Future<void> refresh() async {
    await connect();
    if (connState == ConnState.connected) {
      await refreshStatus();
      await loadSchedule();
    }
  }

  Future<bool> connect() async {
    connState = ConnState.connecting;
    connError = null;
    notifyListeners();
    try {
      info = await agent.info();
      connState = ConnState.connected;
      final defaults = info?['defaults'] as Map<String, dynamic>?;
      if (defaults != null) {
        if (!_destinationFromUser) {
          destination = Destination(
            remote: (defaults['remote'] as String?) ?? destination.remote,
            path: (defaults['path'] as String?) ?? destination.path,
          );
        }
        if (!_retentionFromUser && defaults['keepLast'] is int) {
          retention = Retention(keepLast: defaults['keepLast'] as int, cleanup: retention.cleanup);
        }
      }
      return true;
    } catch (e) {
      connState = ConnState.error;
      connError = e.toString();
      return false;
    } finally {
      notifyListeners();
    }
  }

  Future<void> saveConnection(ConnectionSettings s) async {
    connection = s;
    await store.saveConnection(s);
    agent.configure(s);
    notifyListeners();
  }

  Future<void> forgetHostKey() async {
    await store.forgetHostKey(connection.hostId);
    agent.close();
    notifyListeners();
  }

  // ---- status / polling -----------------------------------------------------

  Future<void> refreshStatus() async {
    _poll?.cancel();
    try {
      status = await agent.status();
      statusError = null;
      if (connState != ConnState.connected) {
        connState = ConnState.connected;
        connError = null;
      }
    } catch (e) {
      statusError = e.toString();
    }
    notifyListeners();
    // Poll every 3 s while a job runs; stop when it finishes.
    if (running) _poll = Timer(const Duration(seconds: 3), refreshStatus);
  }

  void pausePolling() => _poll?.cancel();

  // ---- start / cancel -------------------------------------------------------

  List<BackupSource> get selectedSources =>
      sources.where((s) => selected.contains(s.id)).toList();

  Map<String, dynamic> buildJob({bool? dry}) => {
        'destination': destination.toJson(),
        'sources': selectedSources.map((s) => s.toJson()).toList(),
        'options': {
          'dryRun': dry ?? dryRun,
          'check': verify,
          'cleanup': retention.cleanup,
          'keepLast': retention.keepLast,
        },
      };

  /// Returns null on success, otherwise an error message.
  Future<String?> startBackup() async {
    if (selectedSources.isEmpty) return 'Select at least one source.';
    if (!destination.isValid) return 'Set a valid destination in Settings.';
    busy = true;
    notifyListeners();
    try {
      await agent.start(buildJob());
      await refreshStatus();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> cancelBackup() async {
    busy = true;
    notifyListeners();
    try {
      await agent.cancel();
      await refreshStatus();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  // ---- sources ----------------------------------------------------------------

  Future<void> upsertSource(BackupSource s, {String? replacingId}) async {
    final idx = sources.indexWhere((x) => x.id == (replacingId ?? s.id));
    if (idx >= 0) {
      sources[idx] = s;
    } else {
      sources.add(s);
    }
    if (replacingId != null && replacingId != s.id && selected.remove(replacingId)) {
      selected.add(s.id);
    } else if (idx < 0) {
      selected.add(s.id);
    }
    await _saveSources();
  }

  Future<void> deleteSource(String id) async {
    sources.removeWhere((s) => s.id == id);
    selected.remove(id);
    await _saveSources();
  }

  Future<void> restoreDefaultSources() async {
    for (final d in BackupSource.defaults) {
      if (!sources.any((s) => s.id == d.id)) {
        sources.add(d);
        selected.add(d.id);
      }
    }
    await _saveSources();
  }

  Future<void> setSelected(String id, bool on) async {
    on ? selected.add(id) : selected.remove(id);
    notifyListeners();
    await store.saveSelected(selected);
  }

  Future<void> _saveSources() async {
    notifyListeners();
    await store.saveSources(sources);
    await store.saveSelected(selected);
  }

  // ---- settings ---------------------------------------------------------------

  Future<void> setDestination(Destination d) async {
    destination = d;
    _destinationFromUser = true;
    notifyListeners();
    await store.saveDestination(d);
  }

  Future<void> setRetention(Retention r) async {
    retention = r;
    _retentionFromUser = true;
    notifyListeners();
    await store.saveRetention(r);
  }

  Future<void> setVerify(bool v) async {
    verify = v;
    notifyListeners();
    await store.setVerifyAfterBackup(v);
  }

  void setDryRun(bool v) {
    dryRun = v;
    notifyListeners();
  }

  // ---- restore and safety ---------------------------------------------------------

  /// Returns null on success, otherwise an error message.
  Future<String?> startRestore(String snapshotId, {required List<String> paths, required bool inPlace}) async {
    busy = true;
    notifyListeners();
    try {
      await agent.restore(destination, snapshotId, paths: paths, inPlace: inPlace);
      await refreshStatus();
      tabRequest.value = 0;
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<String?> acceptShrink(String sourceId) async {
    try {
      await agent.acceptShrink(destination, sourceId);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  // ---- automatic backups ------------------------------------------------------

  Future<void> loadSchedule() async {
    try {
      scheduleInfo = await agent.schedule();
      scheduleError = null;
    } catch (e) {
      scheduleError = e.toString();
    }
    notifyListeners();
  }

  /// Saves the schedule on the Pi. With [useCurrentSelection] the stored job is
  /// replaced by the currently ticked sources, destination and retention.
  /// Returns null on success, otherwise an error message.
  Future<String?> saveSchedule(Schedule s, {required bool useCurrentSelection}) async {
    if (useCurrentSelection) {
      if (selectedSources.isEmpty) return 'Tick at least one source on the Backup tab.';
      if (!destination.isValid) return 'Set a valid destination in Settings.';
    }
    try {
      scheduleInfo = await agent.setSchedule(
          s.toJson(job: useCurrentSelection ? buildJob(dry: false) : null));
      scheduleError = null;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    }
  }
}
