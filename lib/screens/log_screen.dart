import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../widgets.dart';

class LogScreen extends StatefulWidget {
  const LogScreen({super.key, required this.state});
  final AppState state;

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final _scroll = ScrollController();
  String _text = '';
  String? _error;
  bool _loading = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _timer?.cancel();
    final atBottom = !_scroll.hasClients || _scroll.position.extentAfter < 40;
    try {
      final t = await widget.state.agent.log(1000);
      if (!mounted) return;
      setState(() {
        _text = t;
        _error = null;
        _loading = false;
      });
      if (atBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
    if (mounted && widget.state.running) {
      _timer = Timer(const Duration(seconds: 3), _load);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Job log'),
        actions: [
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _text));
              showSnack(context, 'Log copied');
            },
          ),
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Padding(padding: const EdgeInsets.all(16), child: Notice(_error!))
              : _text.trim().isEmpty
                  ? const Center(child: Text('The log is empty.'))
                  : Scrollbar(
                      controller: _scroll,
                      child: SingleChildScrollView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          _text,
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.35),
                        ),
                      ),
                    ),
    );
  }
}
