// Plain data classes shared by the app. JSON shapes match pi/pi-backup-agent.

enum HookType { none, postgres, mariadb, nextcloud }

extension HookTypeLabel on HookType {
  String get label => switch (this) {
        HookType.none => 'None',
        HookType.postgres => 'PostgreSQL dump',
        HookType.mariadb => 'MariaDB dump',
        HookType.nextcloud => 'Nextcloud (maintenance mode + MariaDB dump)',
      };
}

final idPattern = RegExp(r'^[a-z0-9-]{1,40}$');
final remotePattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final repoPathPattern = RegExp(r'^[A-Za-z0-9._/-]{1,200}$');
final containerPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_.-]{0,127}$');

bool isValidRepoPath(String p) =>
    repoPathPattern.hasMatch(p) && !RegExp(r'(^|/)\.\.(/|$)').hasMatch(p);

String slugify(String s) {
  final slug = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.length > 40 ? slug.substring(0, 40) : slug;
}

class SourceHook {
  const SourceHook({
    this.type = HookType.none,
    this.container = '',
    this.appContainer = '',
  });

  final HookType type;
  final String container;
  final String appContainer;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        if (container.isNotEmpty) 'container': container,
        if (appContainer.isNotEmpty) 'appContainer': appContainer,
      };

  factory SourceHook.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const SourceHook();
    return SourceHook(
      type: HookType.values.firstWhere(
        (t) => t.name == j['type'],
        orElse: () => HookType.none,
      ),
      container: (j['container'] as String?) ?? '',
      appContainer: (j['appContainer'] as String?) ?? '',
    );
  }
}

class BackupSource {
  const BackupSource({
    required this.id,
    required this.name,
    required this.paths,
    this.excludes = const [],
    this.hook = const SourceHook(),
  });

  final String id;
  final String name;
  final List<String> paths;
  final List<String> excludes;
  final SourceHook hook;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'paths': paths,
        'excludes': excludes,
        'hook': hook.toJson(),
      };

  factory BackupSource.fromJson(Map<String, dynamic> j) => BackupSource(
        id: j['id'] as String,
        name: j['name'] as String,
        paths: List<String>.from(j['paths'] as List),
        excludes: List<String>.from((j['excludes'] as List?) ?? const []),
        hook: SourceHook.fromJson(j['hook'] as Map<String, dynamic>?),
      );

  static const immich = BackupSource(
    id: 'immich',
    name: 'Immich',
    paths: ['/mnt/ssd/immich/library', '/mnt/ssd/immich/app'],
    excludes: [
      '/mnt/ssd/immich/library/thumbs',
      '/mnt/ssd/immich/library/encoded-video',
    ],
    hook: SourceHook(type: HookType.postgres, container: 'immich_postgres'),
  );

  static const nextcloud = BackupSource(
    id: 'nextcloud',
    name: 'Nextcloud',
    paths: [
      '/mnt/ssd/nextcloud/data',
      '/mnt/ssd/nextcloud/html/config',
      '/mnt/ssd/nextcloud/html/custom_apps',
      '/mnt/ssd/nextcloud/html/themes',
      '/mnt/ssd/nextcloud/app',
    ],
    excludes: [
      '/mnt/ssd/nextcloud/data/appdata_*/preview',
      '/mnt/ssd/nextcloud/data/*/uploads',
      '/mnt/ssd/nextcloud/data/*/cache',
      '/mnt/ssd/nextcloud/data/nextcloud.log*',
      '/mnt/ssd/nextcloud/data/updater-*',
    ],
    hook: SourceHook(
      type: HookType.nextcloud,
      container: 'nextcloud_db',
      appContainer: 'nextcloud_app',
    ),
  );

  static const defaults = [immich, nextcloud];
}

class ConnectionSettings {
  const ConnectionSettings({
    this.host = '',
    this.port = 22,
    this.username = 'pi',
    this.password = '',
    this.privateKey = '',
    this.passphrase = '',
  });

  final String host;
  final int port;
  final String username;
  final String password;
  final String privateKey;
  final String passphrase;

  bool get isComplete =>
      host.trim().isNotEmpty &&
      username.trim().isNotEmpty &&
      (password.isNotEmpty || privateKey.trim().isNotEmpty);

  /// Key for the trust-on-first-use host key store.
  String get hostId => '${host.trim().toLowerCase()}:$port';

  bool sameAs(ConnectionSettings o) =>
      host == o.host &&
      port == o.port &&
      username == o.username &&
      password == o.password &&
      privateKey == o.privateKey &&
      passphrase == o.passphrase;
}

class Destination {
  const Destination({this.remote = '', this.path = ''});
  final String remote;
  final String path;

  bool get isValid => remotePattern.hasMatch(remote) && isValidRepoPath(path);
  String get label => '$remote:$path';

  Map<String, dynamic> toJson() => {'remote': remote, 'path': path};
}

/// How many snapshots per source survive the automatic clean-up.
class Retention {
  const Retention({this.keepLast = 2, this.cleanup = true});
  final int keepLast;
  final bool cleanup;

  static const minKeep = 1;
  static const maxKeep = 100;
}

enum ScheduleFrequency { daily, every2days, weekly, monthly }

extension ScheduleFrequencyLabel on ScheduleFrequency {
  String get label => switch (this) {
        ScheduleFrequency.daily => 'Daily',
        ScheduleFrequency.every2days => 'Every 2nd day',
        ScheduleFrequency.weekly => 'Weekly',
        ScheduleFrequency.monthly => 'Monthly',
      };
}

const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const weekdayNames = {
  'Mon': 'Monday',
  'Tue': 'Tuesday',
  'Wed': 'Wednesday',
  'Thu': 'Thursday',
  'Fri': 'Friday',
  'Sat': 'Saturday',
  'Sun': 'Sunday',
};

/// Automatic backups, run by a systemd timer on the Pi (times are Pi local time).
class Schedule {
  const Schedule({
    this.enabled = false,
    this.frequency = ScheduleFrequency.weekly,
    this.time = '03:00',
    this.weekday = 'Sun',
    this.dayOfMonth = 1,
    this.sourceIds = const [],
  });

  final bool enabled;
  final ScheduleFrequency frequency;
  final String time; // HH:MM, 24 h
  final String weekday; // Mon..Sun
  final int dayOfMonth; // 1..28
  final List<String> sourceIds; // sources in the stored job (read-only info)

  factory Schedule.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const Schedule();
    final job = j['job'] as Map<String, dynamic>?;
    return Schedule(
      enabled: j['enabled'] == true,
      frequency: ScheduleFrequency.values.firstWhere((f) => f.name == j['frequency'],
          orElse: () => ScheduleFrequency.weekly),
      time: (j['time'] as String?) ?? '03:00',
      weekday: (j['weekday'] as String?) ?? 'Sun',
      dayOfMonth: (j['dayOfMonth'] as int?) ?? 1,
      sourceIds: [
        for (final s in ((job?['sources'] as List?) ?? const []).cast<Map<String, dynamic>>())
          s['id'] as String,
      ],
    );
  }

  /// Body for `schedule-set`; [job] is omitted to keep the stored one.
  Map<String, dynamic> toJson({Map<String, dynamic>? job}) => {
        'enabled': enabled,
        'frequency': frequency.name,
        'time': time,
        'weekday': weekday,
        'dayOfMonth': dayOfMonth,
        'job': ?job,
      };

  String get summary {
    final at = 'at $time';
    return switch (frequency) {
      ScheduleFrequency.daily => 'Every day $at',
      ScheduleFrequency.every2days => 'Every second day $at',
      ScheduleFrequency.weekly => 'Every ${weekdayNames[weekday] ?? weekday} $at',
      ScheduleFrequency.monthly => 'Monthly on day $dayOfMonth $at',
    };
  }
}
