import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../utils/platform_detector.dart';
import '../utils/layout_constants.dart';

/// The reader keeps Close focused while the remote scrolls the description.
/// This works even though the text itself has no focusable descendants.
class FullDescriptionDialog extends StatefulWidget {
  const FullDescriptionDialog({super.key, required this.item, required this.description});

  final MediaItem item;
  final String? description;

  @override
  State<FullDescriptionDialog> createState() => _FullDescriptionDialogState();
}

class _FullDescriptionDialogState extends State<FullDescriptionDialog> {
  final _scroll = ScrollController();
  double? _scrollTarget;

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!PlatformDetector.isTV() || (event is! KeyDownEvent && event is! KeyRepeatEvent) || !_scroll.hasClients) {
      return KeyEventResult.ignored;
    }
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown || LogicalKeyboardKey.pageDown => 1,
      LogicalKeyboardKey.arrowUp || LogicalKeyboardKey.pageUp => -1,
      _ => 0,
    };
    if (direction == 0 || _scroll.position.maxScrollExtent == 0) return KeyEventResult.ignored;
    final position = _scroll.position;
    final step = position.viewportDimension * 0.65;
    _scrollTarget = ((_scrollTarget ?? position.pixels) + step * direction).clamp(0, position.maxScrollExtent);
    _scroll.animateTo(_scrollTarget!, duration: const Duration(milliseconds: 120), curve: Curves.easeOut);
    return KeyEventResult.handled;
  }

  String get _title {
    final item = widget.item;
    if (!item.isEpisode) return item.title ?? item.displayTitle;
    return [
      if (item.grandparentTitle?.isNotEmpty == true) item.grandparentTitle!,
      if (item.parentIndex != null && item.index != null) 'S${item.parentIndex} E${item.index}',
      if (item.title?.isNotEmpty == true) item.title!,
    ].join(' · ');
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: _onKey,
    child: AlertDialog(
      title: Text(_title.isEmpty ? widget.item.displayTitle : _title),
      content: SingleChildScrollView(
        controller: _scroll,
        child: Text(
          widget.description?.isNotEmpty == true ? widget.description! : t.discover.noDescription,
          style: PlatformDetector.isTV()
              ? Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontSize: 30 * TvLayoutConstants.scaleOf(context), height: 1.5)
              : null,
        ),
      ),
      actions: [TextButton(autofocus: true, onPressed: () => Navigator.pop(context), child: Text(t.common.close))],
    ),
  );
}
