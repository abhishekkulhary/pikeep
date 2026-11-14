import 'package:flutter_test/flutter_test.dart';
import 'package:pikeep/agent_client.dart';
import 'package:pikeep/models.dart';

void main() {
  test('shellQuote leaves safe words alone and quotes the rest', () {
    expect(AgentClient.shellQuote('status'), 'status');
    expect(AgentClient.shellQuote('/mnt/ssd/immich'), '/mnt/ssd/immich');
    expect(AgentClient.shellQuote('/mnt/ssd/my photos'), "'/mnt/ssd/my photos'");
    expect(AgentClient.shellQuote("it's; rm -rf /"), "'it'\\''s; rm -rf /'");
    expect(AgentClient.shellQuote(r'$(reboot)'), r"'$(reboot)'");
  });

  test('validation patterns match the agent', () {
    expect(idPattern.hasMatch('immich'), isTrue);
    expect(idPattern.hasMatch('Immich'), isFalse);
    expect(remotePattern.hasMatch('onedrive'), isTrue);
    expect(remotePattern.hasMatch('one:drive'), isFalse);
    expect(isValidRepoPath('pi-backup/main'), isTrue);
    expect(isValidRepoPath('a/../b'), isFalse);
    expect(slugify('My Photos!'), 'my-photos');
  });

  test('sources round-trip through JSON', () {
    for (final s in BackupSource.defaults) {
      final back = BackupSource.fromJson(s.toJson());
      expect(back.toJson(), s.toJson());
    }
  });

  test('schedule JSON matches the agent', () {
    const s = Schedule(enabled: true, frequency: ScheduleFrequency.every2days, time: '02:15');
    expect(s.toJson(), {'enabled': true, 'frequency': 'every2days', 'time': '02:15', 'weekday': 'Sun', 'dayOfMonth': 1});
    expect(s.toJson(job: {'x': 1})['job'], {'x': 1});
    final back = Schedule.fromJson({
      ...s.toJson(),
      'job': {'sources': [{'id': 'immich'}]},
    });
    expect(back.frequency, ScheduleFrequency.every2days);
    expect(back.sourceIds, ['immich']);
    expect(const Schedule(frequency: ScheduleFrequency.monthly, dayOfMonth: 5).summary, 'Monthly on day 5 at 03:00');
  });
}
