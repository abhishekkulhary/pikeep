import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../widgets.dart';
import 'log_screen.dart';
import 'schedule_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state, required this.openSettings});
  final AppState state;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PiKeep'),
        actions: [
          IconButton(
            tooltip: 'Job log',
            icon: const Icon(Icons.article_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => LogScreen(state: state))),
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: state.refresh),
        ],
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) {
          final job = state.jobState;
          return PageBody(onRefresh: state.refresh, children: [
            _ConnectionCard(state: state, openSettings: openSettings),
            if (state.statusError != null && state.connState == ConnState.connected)
              Notice(state.statusError!),
            if (state.running)
              _ProgressCard(state: state)
            else if (state.connState == ConnState.connected)
              _StartCard(state: state, openSettings: openSettings),
            if (state.connState == ConnState.connected) _ScheduleCard(state: state),
            if (job != null && !state.running) _LastRunCard(job: job, stale: state.status?['stale'] == true),
            if (state.history.isNotEmpty) _HistoryCard(history: state.history),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.state, required this.openSettings});
  final AppState state;
  final VoidCallback openSettings;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final info = state.info;
    final c = state.connection;

    if (!c.isComplete) {
      return SectionCard(title: 'Not set up yet', children: [
        const ListTile(
          leading: Icon(Icons.lan_outlined),
          title: Text('Enter the Pi\'s SSH host, user and password or key.'),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: FilledButton.tonalIcon(
              onPressed: openSettings, icon: const Icon(Icons.settings), label: const Text('Open settings')),
        ),
      ]);
    }

    final (Color dot, String label) = switch (state.connState) {
      ConnState.connected => (Colors.green, 'Connected'),
      ConnState.connecting => (cs.primary, 'Connecting…'),
      ConnState.error => (cs.error, 'Not connected'),
      ConnState.idle => (cs.outline, 'Idle'),
    };

    return SectionCard(children: [
      ListTile(
        leading: Icon(Icons.dns_outlined, color: cs.primary),
        title: Text(info?['hostname'] as String? ?? c.host),
        subtitle: Text('${c.username}@${c.host}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          if (state.connState == ConnState.connecting)
            const SizedBox.square(dimension: 12, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Icon(Icons.circle, size: 12, color: dot),
          const SizedBox(width: 6),
          Text(label),
        ]),
      ),
      if (info != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            _chip(context, 'agent ${info['agentVersion']}'),
            if ((info['restic'] as String? ?? '').isNotEmpty)
              _chip(context, (info['restic'] as String).split(' ').take(2).join(' ')),
            _chip(context, '${info['requiredMount']} ${info['mounted'] == true ? 'mounted' : 'NOT mounted'}',
                warn: info['mounted'] != true),
            if (info['passwordFile'] != true) _chip(context, 'restic password file missing', warn: true),
            if (info['rcloneConfig'] != true) _chip(context, 'rclone config missing', warn: true),
          ]),
        ),
      if (state.connError != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Notice(state.connError!,
              action: TextButton(onPressed: state.refresh, child: const Text('Retry'))),
        ),
    ]);
  }

  Widget _chip(BuildContext context, String text, {bool warn = false}) {
    final cs = Theme.of(context).colorScheme;
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
      backgroundColor: warn ? cs.errorContainer : null,
      labelStyle: TextStyle(color: warn ? cs.onErrorContainer : null, fontSize: 12),
      side: BorderSide.none,
    );
  }
}

// ---------------------------------------------------------------------------

class _StartCard extends StatelessWidget {
  const _StartCard({required this.state, required this.openSettings});
  final AppState state;
  final VoidCallback openSettings;

  String _hookLabel(SourceHook h) => switch (h.type) {
        HookType.none => '',
        HookType.postgres => ' · PostgreSQL dump',
        HookType.mariadb => ' · MariaDB dump',
        HookType.nextcloud => ' · maintenance mode + DB dump',
      };

  Future<void> _start(BuildContext context) async {
    final srcs = state.selectedSources;
    final r = state.retention;
    final ok = await confirm(
      context,
      title: state.dryRun ? 'Start dry run?' : 'Start backup?',
      ok: state.dryRun ? 'Start dry run' : 'Start backup',
      content: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('To ${state.destination.label}'),
        const SizedBox(height: 8),
        for (final s in srcs) Text('• ${s.name}${_hookLabel(s.hook)}'),
        const SizedBox(height: 8),
        if (state.dryRun)
          const Text('Dry run: nothing is uploaded or deleted, database hooks are skipped.')
        else ...[
          if (srcs.any((s) => s.hook.type == HookType.nextcloud))
            const Text('Nextcloud is in maintenance mode while it is backed up.'),
          Text(r.cleanup
              ? 'Afterwards only the last ${r.keepLast} backup(s) per source are kept; older ones are deleted from OneDrive.'
              : 'Automatic clean-up is off — old backups are kept.'),
        ],
        if (state.verify) const Text('Then 5% of the stored data is verified.'),
        const SizedBox(height: 8),
        const Text('The Pi does all the work; you can close the app.'),
      ]),
    );
    if (!ok || !context.mounted) return;
    final err = await state.startBackup();
    if (err != null && context.mounted) showSnack(context, err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final r = state.retention;
    final canStart = state.selectedSources.isNotEmpty && state.destination.isValid && !state.busy;
    return SectionCard(title: 'Back up', children: [
      ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(state.destination.isValid ? state.destination.label : 'No destination set'),
        subtitle: const Text('restic repository (rclone remote : path)'),
        onTap: openSettings,
      ),
      const Divider(height: 8),
      if (state.sources.isEmpty)
        const ListTile(title: Text('No sources — add some on the Sources tab.')),
      for (final s in state.sources)
        CheckboxListTile(
          value: state.selected.contains(s.id),
          onChanged: (v) => state.setSelected(s.id, v ?? false),
          title: Text(s.name),
          subtitle: Text('${s.paths.length} folder(s)${_hookLabel(s.hook)}'),
        ),
      const Divider(height: 8),
      SwitchListTile(
        value: state.dryRun,
        onChanged: state.setDryRun,
        title: const Text('Dry run'),
        subtitle: const Text('Show what would be uploaded, change nothing'),
      ),
      SwitchListTile(
        value: state.verify,
        onChanged: state.setVerify,
        title: const Text('Verify afterwards'),
        subtitle: const Text('Read back a random 5% of the stored data'),
      ),
      ListTile(
        leading: Icon(r.cleanup ? Icons.auto_delete_outlined : Icons.all_inclusive),
        title: Text(r.cleanup ? 'Keeps the last ${r.keepLast} backup(s) per source' : 'Automatic clean-up is off'),
        subtitle: Text(r.cleanup ? 'Older backups are deleted automatically' : 'All backups are kept'),
        trailing: const Icon(Icons.chevron_right),
        onTap: openSettings,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: FilledButton.icon(
          onPressed: canStart ? () => _start(context) : null,
          icon: state.busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Icon(state.dryRun ? Icons.science_outlined : Icons.play_arrow),
          label: Text(state.dryRun ? 'Start dry run' : 'Start backup'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({required this.state});
  final AppState state;

  Future<void> _cancel(BuildContext context) async {
    final ok = await confirm(context,
        title: 'Cancel the backup?',
        content: const Text('The running step is stopped. Snapshots that already finished are kept, '
            'and Nextcloud maintenance mode is switched off.'),
        ok: 'Cancel backup',
        destructive: true);
    if (!ok || !context.mounted) return;
    final err = await state.cancelBackup();
    if (err != null && context.mounted) showSnack(context, err, error: true);
  }

  @override
  Widget build(BuildContext context) {
    final job = state.jobState ?? const {};
    final p = state.progress;
    final steps = ((job['steps'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final idx = (p?['step'] as int?) ?? (job['currentStep'] as int?);
    final step = idx != null && idx < steps.length ? steps[idx] : null;
    final percent = (p?['percent'] as num?)?.toDouble();
    final indeterminate = p == null || p['indeterminate'] == true || percent == null;
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: job['dryRun'] == true ? 'Dry run in progress' : 'Backup in progress',
      trailing: Text(fmtAgo(job['startedAt'] as String?), style: text.bodySmall),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step?['name'] as String? ?? (job['message'] as String? ?? 'Starting…'), style: text.titleSmall),
            if ((step?['message'] as String? ?? '').isNotEmpty)
              Text(step!['message'] as String, style: text.bodySmall),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(minHeight: 8, value: indeterminate ? null : (percent / 100).clamp(0, 1)),
            ),
            const SizedBox(height: 8),
            if (!indeterminate)
              Wrap(spacing: 16, runSpacing: 4, children: [
                Text('${percent.toStringAsFixed(1)} %', style: text.labelLarge),
                Text('${fmtBytes(p['bytesDone'] as num?)} of ${fmtBytes(p['totalBytes'] as num?)}'),
                Text('${p['filesDone']} / ${p['totalFiles']} files'),
                if (p['eta'] != null) Text('≈ ${fmtDuration(p['eta'] as num?)} left'),
                if ((p['errorCount'] as num? ?? 0) > 0)
                  Text('${p['errorCount']} unreadable', style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ]),
            if (p?['currentFile'] != null) ...[
              const SizedBox(height: 4),
              Text(p!['currentFile'] as String,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
            ],
          ]),
        ),
        const Divider(),
        _StepList(steps: steps),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: OutlinedButton.icon(
            onPressed: state.busy ? null : () => _cancel(context),
            icon: const Icon(Icons.stop),
            label: const Text('Cancel backup'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
              minimumSize: const Size.fromHeight(44),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepList extends StatelessWidget {
  const _StepList({required this.steps});
  final List<Map<String, dynamic>> steps;

  String? _resultLine(Map<String, dynamic>? r) {
    if (r == null) return null;
    final parts = <String>[
      '${fmtBytes(r['dataAdded'] as num?)} new data',
      '${r['filesNew']} new · ${r['filesChanged']} changed · ${r['filesUnmodified']} unchanged files',
      fmtDuration(r['duration'] as num?),
      if (r['snapshotId'] != null) 'snapshot ${(r['snapshotId'] as String).substring(0, 8)}',
    ];
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final small = Theme.of(context).textTheme.bodySmall;
    return Column(children: [
      for (final s in steps)
        ListTile(
          dense: true,
          leading: StatusIcon(s['status'] as String?),
          title: Text(s['name'] as String? ?? s['id'] as String),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if ((s['message'] as String? ?? '').isNotEmpty) Text(s['message'] as String),
            if (_resultLine(s['result'] as Map<String, dynamic>?) case final line?) Text(line, style: small),
          ]),
        ),
    ]);
  }
}

// ---------------------------------------------------------------------------

class _LastRunCard extends StatelessWidget {
  const _LastRunCard({required this.job, required this.stale});
  final Map<String, dynamic> job;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String?;
    final steps = ((job['steps'] as List?) ?? const []).cast<Map<String, dynamic>>();
    return SectionCard(
      title: job['dryRun'] == true ? 'Last dry run' : 'Last run',
      trailing: Text(fmtTime(job['finishedAt'] as String? ?? job['startedAt'] as String?),
          style: Theme.of(context).textTheme.bodySmall),
      children: [
        ListTile(
          leading: StatusIcon(status, size: 28),
          title: Text(job['message'] as String? ?? status ?? ''),
          subtitle: stale ? const Text('Detected after the job died without reporting back.') : null,
        ),
        const Divider(height: 8),
        _StepList(steps: steps),
      ],
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.history});
  final List<Map<String, dynamic>> history;

  @override
  Widget build(BuildContext context) {
    return SectionCard(title: 'Recent runs', children: [
      for (final h in history.take(10))
        ListTile(
          dense: true,
          leading: StatusIcon(h['status'] as String?),
          title: Text('${fmtTime(h['startedAt'] as String?)}'
              '${h['dryRun'] == true ? '  · dry run' : ''}'
              '${h['trigger'] == 'scheduled' ? '  · scheduled' : ''}'),
          subtitle: Text([
            ((h['sources'] as List?) ?? const []).join(', '),
            if ((h['dataAdded'] as num? ?? 0) > 0) '+${fmtBytes(h['dataAdded'] as num?)}',
            h['message'] as String? ?? '',
          ].where((s) => s.isNotEmpty).join(' · ')),
        ),
    ]);
  }
}

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final active = state.scheduleActive;
    final err = state.scheduleState['lastError'] as String?;
    return SectionCard(children: [
      ListTile(
        leading: Icon(active ? Icons.event_repeat : Icons.event_busy_outlined,
            color: active ? Theme.of(context).colorScheme.primary : null),
        title: Text(active ? 'Automatic: ${state.schedule.summary}' : 'Automatic backups are off'),
        subtitle: Text(active
            ? [
                if (state.scheduleNextRun != null) 'Next run ${fmtTime(state.scheduleNextRun)}',
                state.schedule.sourceIds.join(', '),
              ].where((s) => s.isNotEmpty).join(' · ')
            : 'Daily, every 2nd day, weekly or monthly — runs on the Pi'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => ScheduleScreen(state: state))),
      ),
      if (state.scheduleError != null)
        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: Notice(state.scheduleError!)),
      if (err != null && active)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Notice('Last scheduled start failed: $err', kind: NoticeKind.warning),
        ),
    ]);
  }
}
