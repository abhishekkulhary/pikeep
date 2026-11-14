@Tags(['golden'])
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Renders the app icon with Flutter itself, so it can be regenerated without
/// any design tool:
///
///   flutter test test/tools/generate_icon_test.dart --update-goldens
///   dart run flutter_launcher_icons
///
/// icon.png is full-bleed (iOS and Android apply their own mask);
/// icon-macos.png has the rounded tile and margin macOS expects.
const _from = Color(0xFF14B8A6); // teal — the site's first accent
const _to = Color(0xFF0EA5E9); // sky — the site's second accent

Widget _icon({required bool macos}) {
  final tile = DecoratedBox(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_from, _to],
      ),
      borderRadius: BorderRadius.circular(macos ? 185 : 0),
    ),
    child: const Center(
      child: Icon(Icons.cloud_upload_rounded, size: 600, color: Colors.white),
    ),
  );
  return Directionality(
    textDirection: TextDirection.ltr,
    child: ColoredBox(
      color: const Color(0x00000000),
      child: Padding(padding: EdgeInsets.all(macos ? 100 : 0), child: tile),
    ),
  );
}

void main() {
  setUpAll(() async {
    final root = Platform.environment['FLUTTER_ROOT'];
    if (root == null) throw StateError('Run with `flutter test` (FLUTTER_ROOT is not set).');
    final loader = FontLoader('MaterialIcons')
      ..addFont(File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf')
          .readAsBytes()
          .then(ByteData.sublistView));
    await loader.load();
  });

  for (final macos in [false, true]) {
    testWidgets('app icon${macos ? ' (macOS)' : ''}', (tester) async {
      tester.view
        ..physicalSize = const Size(1024, 1024)
        ..devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(child: _icon(macos: macos)));
      await expectLater(
        find.byType(RepaintBoundary).first,
        matchesGoldenFile('../../assets/icon/${macos ? 'icon-macos' : 'icon'}.png'),
      );
    });
  }
}
