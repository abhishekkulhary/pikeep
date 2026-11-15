import 'package:flutter_test/flutter_test.dart';
import 'package:pikeep/app_state.dart';
import 'package:pikeep/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

String _daysAgo(int d) => DateTime.now().toUtc().subtract(Duration(days: d)).toIso8601String();

Future<AppState> _state({required List<Map<String, dynamic>> history, String? frequency}) async {
  SharedPreferences.setMockInitialValues({});
  final s = AppState(await Store.open());
  s.status = {'running': false, 'history': history};
  if (frequency != null) {
    s.scheduleInfo = {
      'active': true,
      'schedule': {'enabled': true, 'frequency': frequency, 'time': '03:00'},
    };
  }
  return s;
}

void main() {
  test('last good backup ignores dry runs, restores and failures', () async {
    final s = await _state(history: [
      {'kind': 'restore', 'status': 'success', 'finishedAt': _daysAgo(0)},
      {'kind': 'backup', 'status': 'success', 'dryRun': true, 'finishedAt': _daysAgo(1)},
      {'kind': 'backup', 'status': 'failed', 'finishedAt': _daysAgo(2)},
      {'kind': 'backup', 'status': 'warning', 'finishedAt': _daysAgo(3)},
    ]);
    expect(DateTime.now().difference(s.lastGoodBackup!).inDays, 3);
  });

  test('a daily schedule is overdue after two days without a completed backup', () async {
    expect((await _state(history: [{'status': 'success', 'finishedAt': _daysAgo(1)}], frequency: 'daily')).backupOverdue,
        isFalse);
    expect((await _state(history: [{'status': 'success', 'finishedAt': _daysAgo(3)}], frequency: 'daily')).backupOverdue,
        isTrue);
    expect((await _state(history: [{'status': 'success', 'finishedAt': _daysAgo(3)}], frequency: 'weekly')).backupOverdue,
        isFalse);
  });

  test('a scheduled setup with nothing completed yet is overdue; a fresh install is not', () async {
    expect((await _state(history: [{'status': 'failed', 'finishedAt': _daysAgo(1)}], frequency: 'daily')).backupOverdue,
        isTrue);
    expect((await _state(history: [])).backupOverdue, isFalse);
  });

  test('the disk counts as mounted unless the Pi says otherwise', () async {
    final s = await _state(history: []);
    expect(s.diskMounted, isTrue);
    s.status = {...s.status!, 'health': {'mounted': false}};
    expect(s.diskMounted, isFalse);
  });
}
