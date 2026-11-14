import 'package:material_ui/material_ui.dart';

import '../app_state.dart';
import '../format.dart';
import '../models.dart';
import '../widgets.dart';

/// Edit the automatic backup schedule. The Pi runs it with a systemd timer,
/// so it works while the app is closed.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, required this.state});
  final AppState state;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  AppState get state => widget.state;
  late Schedule _s = state.schedule.enabled || state.scheduleInfo?['schedule'] != null
      ? state.schedule
      : const Schedule(enabled: true);
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    if (state.scheduleInfo == null) {
      state.loadSchedule().then((_) {
        if (mounted && state.scheduleInfo?['schedule'] != null) setState(() => _s = state.schedule);
      });
    }
  }

  Schedule _copy({bool? enabled, ScheduleFrequency? frequency, String? time, String? weekday, int? day}) =>
      Schedule(
        enabled: enabled ?? _s.enabled,
        frequency: frequency ?? _s.frequency,
        time: time ?? _s.time,
        weekday: weekday ?? _s.weekday,
        dayOfMonth: day ?? _s.dayOfMonth,
        sourceIds: _s.sourceIds,
      );

  Future<void> _pickTime() async {
    final parts = _s.time.split(':');
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1])),
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    String two(int n) => n.toString().padLeft(2, '0');
    setState(() => _s = _copy(time: '${two(t.hour)}:${two(t.minute)}'));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // When turning the schedule off, keep the stored job as it is.
    final err = await state.saveSchedule(_s, useCurrentSelection: _s.enabled);
    if (!mounted) return;
    setState(() => _saving = false);
    if (err != null) {
      showSnack(context, err, error: true);
    } else {
      showSnack(context, _s.enabled ? 'Schedule saved on the Pi' : 'Automatic backups turned off');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Automatic backups'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: state,
        builder: (context, _) => PageBody(children: [
          if (state.scheduleError != null) Notice(state.scheduleError!),
          SectionCard(children: [
            SwitchListTile(
              value: _s.enabled,
              onChanged: (v) => setState(() => _s = _copy(enabled: v)),
              title: const Text('Back up automatically'),
              subtitle: const Text('The Pi starts the backup on its own — the app can be closed'),
            ),
          ]),
          if (_s.enabled) ...[
            _whenCard(context),
            _whatCard(context),
          ],
          _statusCard(context),
        ]),
      ),
    );
  }

  Widget _whenCard(BuildContext context) {
    return SectionCard(title: 'When', children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in ScheduleFrequency.values)
            ChoiceChip(
              label: Text(f.label),
              selected: _s.frequency == f,
              onSelected: (_) => setState(() => _s = _copy(frequency: f)),
            ),
        ]),
      ),
      if (_s.frequency == ScheduleFrequency.weekly)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in weekdays)
              ChoiceChip(
                label: Text(d),
                selected: _s.weekday == d,
                onSelected: (_) => setState(() => _s = _copy(weekday: d)),
              ),
          ]),
        ),
      if (_s.frequency == ScheduleFrequency.monthly)
        ListTile(
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Day of the month'),
          subtitle: const Text('1–28, so every month has it'),
          trailing: DropdownButton<int>(
            value: _s.dayOfMonth,
            items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('$d'))],
            onChanged: (d) => setState(() => _s = _copy(day: d)),
          ),
        ),
      ListTile(
        leading: const Icon(Icons.schedule),
        title: const Text('Time'),
        subtitle: const Text('In the Pi\'s local time'),
        trailing: OutlinedButton(onPressed: _pickTime, child: Text(_s.time)),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text(
          '${_s.summary}. If the Pi is off at that time, the backup runs when it is back on.'
          '${_s.frequency == ScheduleFrequency.every2days ? ' A start is skipped if the last scheduled one was less than 36 h earlier.' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ]);
  }

  Widget _whatCard(BuildContext context) {
    final current = state.selectedSources.map((s) => s.id).toList();
    final stored = state.schedule.sourceIds;
    final differs = stored.isNotEmpty && (stored.toSet().difference(current.toSet()).isNotEmpty ||
        current.toSet().difference(stored.toSet()).isNotEmpty);
    final r = state.retention;
    return SectionCard(title: 'What', children: [
      for (final s in state.selectedSources)
        ListTile(dense: true, leading: const Icon(Icons.folder_copy_outlined), title: Text(s.name)),
      if (state.selectedSources.isEmpty)
        const ListTile(title: Text('No sources ticked on the Backup tab')),
      ListTile(
        dense: true,
        leading: const Icon(Icons.cloud_upload_outlined),
        title: Text(state.destination.label),
      ),
      ListTile(
        dense: true,
        leading: Icon(r.cleanup ? Icons.auto_delete_outlined : Icons.all_inclusive),
        title: Text(r.cleanup ? 'Keep the last ${r.keepLast} backup(s) per source' : 'Keep all backups'),
        subtitle: state.verify ? const Text('Then verify 5% of the stored data') : null,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Notice(
          differs
              ? 'The schedule on the Pi currently backs up: ${stored.join(', ')}. Saving replaces it with the sources above.'
              : 'Saving stores the sources ticked on the Backup tab and the settings above on the Pi. '
                  'Change them later and save the schedule again to update it.',
          kind: differs ? NoticeKind.warning : NoticeKind.info,
        ),
      ),
    ]);
  }

  Widget _statusCard(BuildContext context) {
    final st = state.scheduleState;
    final err = st['lastError'] as String?;
    return SectionCard(title: 'On the Pi', children: [
      ListTile(
        dense: true,
        leading: StatusIcon(state.scheduleActive ? 'done' : 'skipped'),
        title: Text(state.scheduleActive ? state.schedule.summary : 'Not scheduled'),
        subtitle: state.scheduleNextRun == null ? null : Text('Next run: ${fmtTime(state.scheduleNextRun)}'),
      ),
      if (st['lastStart'] != null)
        ListTile(
          dense: true,
          leading: const Icon(Icons.history),
          title: Text('Last scheduled start: ${fmtTime(st['lastStart'] as String?)}'),
        ),
      if (err != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Notice('Last scheduled start failed (${fmtTime(st['lastAttempt'] as String?)}): $err'),
        ),
    ]);
  }
}
