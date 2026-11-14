@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pikeep/app_state.dart';
import 'package:pikeep/main.dart';
import 'package:pikeep/models.dart';
import 'package:pikeep/screens/schedule_screen.dart';
import 'package:pikeep/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The screenshots on the website, rendered from the real widgets with made-up
/// data — no real host names, paths or sizes ever reach the public site.
///
///   flutter test test/screenshots --update-goldens
///   ./tool/sync_site_images.sh
///
/// Excluded from CI (`-x golden`): they depend on the host's font rasteriser
/// and the clock ("12 min ago").
Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) throw StateError('Run with `flutter test` (FLUTTER_ROOT is not set).');
  final fonts = '$root/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(File('$fonts/$f').readAsBytes().then(ByteData.sublistView));
    }
    await loader.load();
  }

  await load('Roboto', ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']);
  await load('MaterialIcons', ['MaterialIcons-Regular.otf']);
}

DateTime _nextSunday3am() {
  final now = DateTime.now();
  var d = DateTime(now.year, now.month, now.day, 3);
  while (d.weekday != DateTime.sunday || !d.isAfter(now)) {
    d = d.add(const Duration(days: 1));
  }
  return d;
}

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, dynamic> _step(String id, String name, String kind, String status,
        [String message = '', Map<String, dynamic>? result]) =>
    {'id': id, 'name': name, 'kind': kind, 'status': status, 'message': message, 'result': result};

Future<AppState> _demoState({required bool running}) async {
  SharedPreferences.setMockInitialValues({});
  final state = AppState(await Store.open())
    ..connection = const ConnectionSettings(host: 'pi.example.ts.net', username: 'pi', password: 'x')
    ..connState = ConnState.connected
    ..info = {
      'ok': true,
      'agentVersion': '1.0.0',
      'hostname': 'raspberrypi',
      'restic': 'restic 0.18.0',
      'requiredMount': '/mnt/ssd',
      'mounted': true,
      'passwordFile': true,
      'rcloneConfig': true,
    }
    ..scheduleInfo = {
      'ok': true,
      'active': true,
      'nextRun': _nextSunday3am().toUtc().toIso8601String(),
      'schedule': {
        'enabled': true,
        'frequency': 'weekly',
        'time': '03:00',
        'weekday': 'Sun',
        'dayOfMonth': 1,
        'job': {
          'sources': [
            {'id': 'immich'},
            {'id': 'nextcloud'},
          ],
        },
      },
      'state': {'lastStart': _ago(const Duration(days: 5))},
    };

  final history = [
    {
      'startedAt': _ago(const Duration(days: 7, minutes: 40)),
      'status': 'success',
      'trigger': 'scheduled',
      'sources': ['immich', 'nextcloud'],
      'dataAdded': 1840000000,
      'message': 'Backup completed',
    },
    {
      'startedAt': _ago(const Duration(days: 9, hours: 3)),
      'status': 'success',
      'dryRun': true,
      'sources': ['immich', 'nextcloud'],
      'dataAdded': 0,
      'message': 'Dry run completed',
    },
  ];

  final result = {
    'dataAdded': 1840000000,
    'filesNew': 412,
    'filesChanged': 37,
    'filesUnmodified': 45120,
    'duration': 1265,
    'snapshotId': 'a4c19f02e7b3',
  };

  state.status = running
      ? {
          'running': true,
          'state': {
            'status': 'running',
            'trigger': 'scheduled',
            'dryRun': false,
            'startedAt': _ago(const Duration(minutes: 12)),
            'currentStep': 0,
            'steps': [
              _step('immich', 'Immich', 'backup', 'running', 'Uploading'),
              _step('nextcloud', 'Nextcloud', 'backup', 'pending'),
              _step('cleanup', 'Clean up old backups (keep last 2)', 'cleanup', 'pending'),
            ],
          },
          'progress': {
            'step': 0,
            'stepName': 'Immich',
            'indeterminate': false,
            'percent': 62.4,
            'bytesDone': 41200000000,
            'totalBytes': 66000000000,
            'filesDone': 28411,
            'totalFiles': 45570,
            'eta': 1840,
            'currentFile': '/mnt/ssd/immich/library/upload/2026/08/IMG_4821.HEIC',
            'errorCount': 0,
          },
          'history': history,
        }
      : {
          'running': false,
          'state': {
            'status': 'success',
            'trigger': 'scheduled',
            'dryRun': false,
            'message': 'Backup completed',
            'startedAt': _ago(const Duration(days: 7, minutes: 40)),
            'finishedAt': _ago(const Duration(days: 7, minutes: 12)),
            'steps': [
              _step('immich', 'Immich', 'backup', 'done', 'Snapshot saved', result),
              _step('nextcloud', 'Nextcloud', 'backup', 'done', 'Snapshot saved', {
                ...result,
                'dataAdded': 96000000,
                'filesNew': 58,
                'filesChanged': 12,
                'filesUnmodified': 18233,
                'duration': 402,
                'snapshotId': '7e02bb91c4d0',
              }),
              _step('cleanup', 'Clean up old backups (keep last 2)', 'cleanup', 'done',
                  'Kept the last 2 backup(s) per source'),
            ],
          },
          'history': history,
        };
  return state;
}

void main() {
  setUpAll(_loadFonts);

  Future<void> frame(WidgetTester tester, Size size) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1.0;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  }

  // Spinners never settle, so pump a fixed amount instead of pumpAndSettle.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('desktop: scheduled backup in progress', (tester) async {
    await frame(tester, const Size(1280, 800));
    await tester.pumpWidget(PiBackupApp(state: await _demoState(running: true)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/desktop_running.png'));
  });

  testWidgets('phone: last run and schedule', (tester) async {
    await frame(tester, const Size(390, 844));
    await tester.pumpWidget(PiBackupApp(state: await _demoState(running: false)));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -588));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/phone_home.png'));
  });

  testWidgets('schedule screen', (tester) async {
    await frame(tester, const Size(800, 900));
    final state = await _demoState(running: false);
    await tester.pumpWidget(PiBackupApp(state: state));
    await settle(tester);
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.push(MaterialPageRoute<void>(builder: (_) => ScheduleScreen(state: state)));
    await settle(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/schedule.png'));
  });
}
