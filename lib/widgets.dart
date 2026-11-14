import 'package:material_ui/material_ui.dart';

import 'format.dart';

/// Centers content and caps its width on desktop.
class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.children, this.onRefresh});
  final List<Widget> children;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final list = ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        for (final c in children)
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: Padding(padding: const EdgeInsets.only(bottom: 12), child: c),
            ),
          ),
      ],
    );
    return onRefresh == null ? list : RefreshIndicator(onRefresh: onRefresh!, child: list);
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, this.title, this.trailing, required this.children, this.padding});
  final String? title;
  final Widget? trailing;
  final List<Widget> children;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(title!,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  ?trailing,
                ]),
              ),
            ...children,
          ]),
        ),
      );
}

class StatusIcon extends StatelessWidget {
  const StatusIcon(this.status, {super.key, this.size = 22});
  final String? status;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (status == 'running') {
      return SizedBox.square(
        dimension: size,
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: const CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final v = statusVisual(context, status);
    return Icon(v.icon, color: v.color, size: size);
  }
}

/// Inline message box for errors / warnings / hints.
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.kind = NoticeKind.error, this.action});
  final String text;
  final NoticeKind kind;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg, icon) = switch (kind) {
      NoticeKind.error => (cs.errorContainer, cs.onErrorContainer, Icons.error_outline),
      NoticeKind.warning => (cs.tertiaryContainer, cs.onTertiaryContainer, Icons.warning_amber_rounded),
      NoticeKind.info => (cs.secondaryContainer, cs.onSecondaryContainer, Icons.info_outline),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: fg, size: 20),
        const SizedBox(width: 10),
        Expanded(child: SelectableText(text, style: TextStyle(color: fg))),
        if (action != null) ...[const SizedBox(width: 8), action!],
      ]),
    );
  }
}

enum NoticeKind { error, warning, info }

Future<bool> confirm(BuildContext context,
    {required String title, required Widget content, String ok = 'OK', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: content),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                  foregroundColor: Theme.of(ctx).colorScheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

void showSnack(BuildContext context, String msg, {bool error = false}) {
  final cs = Theme.of(context).colorScheme;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? cs.error : null,
      behavior: SnackBarBehavior.floating,
    ));
}
