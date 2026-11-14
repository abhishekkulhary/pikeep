import 'package:material_ui/material_ui.dart';

String fmtBytes(num? bytes) {
  if (bytes == null) return '–';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 || v >= 100 ? 0 : 1)} ${units[i]}';
}

String fmtDuration(num? seconds) {
  if (seconds == null) return '–';
  final s = seconds.round();
  if (s < 60) return '$s s';
  if (s < 3600) return '${s ~/ 60} min ${s % 60} s';
  return '${s ~/ 3600} h ${(s % 3600) ~/ 60} min';
}

String _two(int n) => n.toString().padLeft(2, '0');

/// ISO-8601 (UTC or with offset) → local "2026-11-14 15:52".
String fmtTime(String? iso) {
  if (iso == null) return '–';
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return iso;
  return '${t.year}-${_two(t.month)}-${_two(t.day)} ${_two(t.hour)}:${_two(t.minute)}';
}

String fmtAgo(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// Icon + colour for job and step statuses used by the agent.
({IconData icon, Color color}) statusVisual(BuildContext context, String? status) {
  final cs = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final ok = dark ? Colors.green.shade300 : Colors.green.shade700;
  final warn = dark ? Colors.amber.shade300 : Colors.amber.shade900;
  return switch (status) {
    'done' || 'success' => (icon: Icons.check_circle, color: ok),
    'warning' => (icon: Icons.warning_amber_rounded, color: warn),
    'failed' => (icon: Icons.error, color: cs.error),
    'cancelled' => (icon: Icons.cancel, color: cs.outline),
    'skipped' => (icon: Icons.remove_circle_outline, color: cs.outline),
    'running' => (icon: Icons.sync, color: cs.primary),
    _ => (icon: Icons.radio_button_unchecked, color: cs.outline),
  };
}
