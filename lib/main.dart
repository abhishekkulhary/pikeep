import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app_state.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/snapshots_screen.dart';
import 'screens/sources_screen.dart';
import 'storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState(await Store.open());
  runApp(PiBackupApp(state: state));
  await state.load();
}

class PiBackupApp extends StatelessWidget {
  const PiBackupApp({super.key, required this.state});
  final AppState state;

  ThemeData _theme(Brightness b) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF00796B), brightness: b),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      );

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'PiKeep',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        home: RootShell(state: state),
      );
}

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.state});
  final AppState state;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _tab = 0;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (widget.state.connection.isComplete) unawaited(widget.state.refreshStatus());
      },
      onPause: widget.state.pausePolling,
    );
    widget.state.tabRequest.addListener(_onTabRequest);
  }

  void _onTabRequest() {
    final t = widget.state.tabRequest.value;
    if (t == null || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    _go(t);
    widget.state.tabRequest.value = null;
  }

  @override
  void dispose() {
    widget.state.tabRequest.removeListener(_onTabRequest);
    _lifecycle.dispose();
    super.dispose();
  }

  void _go(int i) => setState(() => _tab = i);

  static const _destinations = [
    (icon: Icons.backup_outlined, selected: Icons.backup, label: 'Backup'),
    (icon: Icons.folder_copy_outlined, selected: Icons.folder_copy, label: 'Sources'),
    (icon: Icons.history_outlined, selected: Icons.history, label: 'Snapshots'),
    (icon: Icons.settings_outlined, selected: Icons.settings, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(state: widget.state, openSettings: () => _go(3)),
      SourcesScreen(state: widget.state),
      SnapshotsScreen(state: widget.state, visible: _tab == 2),
      SettingsScreen(state: widget.state),
    ];
    final body = IndexedStack(index: _tab, children: pages);

    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 720) {
        return Scaffold(
          body: Row(children: [
            NavigationRail(
              selectedIndex: _tab,
              onDestinationSelected: _go,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: body),
          ]),
        );
      }
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _go,
          destinations: [
            for (final d in _destinations)
              NavigationDestination(
                icon: Icon(d.icon),
                selectedIcon: Icon(d.selected),
                label: d.label,
              ),
          ],
        ),
      );
    });
  }
}
