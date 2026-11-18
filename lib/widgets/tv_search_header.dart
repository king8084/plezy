import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/dpad_navigator.dart';
import '../utils/layout_constants.dart';
import 'app_icon.dart';

/// The TV search header in the style of Apple's own search screens: a big
/// query line and one row of keys under it (`123  space  a…z  ⌫  mic`), with
/// the results right below on the page.
///
/// Drawn entirely by Plezy, so it never covers other screens and never fights
/// over focus. The whole key row is one focus target ([focusNode]): Left and
/// Right move between keys, Select types, Down leaves for the results and Up
/// from the results returns to the same key. A physical or companion-remote
/// keyboard types straight into the query.
class TvSearchHeader extends StatefulWidget {
  const TvSearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    this.onDown,
    this.onNavigateLeft,
    this.onBack,
    this.onSubmit,
    this.onDictate,
    this.dictateTooltip,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final VoidCallback? onDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onBack;
  final VoidCallback? onSubmit;

  /// Opens Apple's dictation keyboard (the mic key). Hidden when null.
  final VoidCallback? onDictate;
  final String? dictateTooltip;

  @override
  State<TvSearchHeader> createState() => _TvSearchHeaderState();
}

enum _KeyKind { character, space, delete, toggleDigits, dictate }

class _Key {
  const _Key(this.kind, [this.value = '']);
  final _KeyKind kind;
  final String value;
}

class _TvSearchHeaderState extends State<TvSearchHeader> {
  static const _letters = 'abcdefghijklmnopqrstuvwxyz';
  static const _digits = "1234567890-'&.:!?";

  bool _digitsMode = false;

  @visibleForTesting
  int get debugIndex => _index;

  /// Starts on "a", the first letter.
  int _index = 2;

  List<_Key> get _keys => [
    _Key(_KeyKind.toggleDigits, _digitsMode ? 'ABC' : '123'),
    const _Key(_KeyKind.space, 'SPACE'),
    for (final char in (_digitsMode ? _digits : _letters).split('')) _Key(_KeyKind.character, char),
    const _Key(_KeyKind.delete),
    if (widget.onDictate != null) const _Key(_KeyKind.dictate),
  ];

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_rebuild);
    widget.controller.addListener(_rebuild);
  }

  @override
  void didUpdateWidget(TvSearchHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      oldWidget.focusNode.removeListener(_rebuild);
      widget.focusNode.addListener(_rebuild);
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_rebuild);
      widget.controller.addListener(_rebuild);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_rebuild);
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _setText(String text) {
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _activate(_Key key) {
    final text = widget.controller.text;
    switch (key.kind) {
      case _KeyKind.character:
        _setText(text + key.value);
      case _KeyKind.space:
        if (text.isNotEmpty && !text.endsWith(' ')) _setText('$text ');
      case _KeyKind.delete:
        if (text.isNotEmpty) _setText(text.characters.skipLast(1).toString());
      case _KeyKind.toggleDigits:
        setState(() => _digitsMode = !_digitsMode);
      case _KeyKind.dictate:
        widget.onDictate?.call();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = _keys;
    final index = _index.clamp(0, keys.length - 1);
    if (key == LogicalKeyboardKey.arrowLeft) {
      if (index > 0) {
        setState(() => _index = index - 1);
      } else if (event is KeyDownEvent) {
        widget.onNavigateLeft?.call();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      if (index < keys.length - 1) setState(() => _index = index + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      if (event is KeyDownEvent) widget.onDown?.call();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) return KeyEventResult.handled;
    if (event.isTvSelectEvent) {
      _activate(keys[index]);
      return KeyEventResult.handled;
    }
    if (key.isBackKey) {
      if (event is KeyDownEvent) widget.onBack?.call();
      return KeyEventResult.handled;
    }
    // A real keyboard (or the companion remote) types directly.
    if (key == LogicalKeyboardKey.backspace) {
      _activate(const _Key(_KeyKind.delete));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) widget.onSubmit?.call();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (character != null && character.isNotEmpty && character.codeUnitAt(0) >= 0x20) {
      _setText(widget.controller.text + character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final colors = Theme.of(context).colorScheme;
    final focused = widget.focusNode.hasFocus;
    final text = widget.controller.text;
    final keys = _keys;
    final index = _index.clamp(0, keys.length - 1);
    final muted = colors.onSurface.withValues(alpha: 0.55);

    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: Padding(
        key: const ValueKey('tv_search_header'),
        padding: EdgeInsets.fromLTRB(40 * scale, 28 * scale, 40 * scale, 20 * scale),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                AppIcon(Symbols.search_rounded, size: 40 * scale, color: text.isEmpty ? muted : colors.onSurface),
                SizedBox(width: 16 * scale),
                Expanded(
                  child: Text(
                    text.isEmpty ? widget.placeholder : text,
                    key: const ValueKey('tv_search_query'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 40 * scale,
                      fontWeight: FontWeight.w700,
                      color: text.isEmpty ? muted : colors.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 18 * scale),
            // Apple's layout: the keys spread across the full width (shrunk
            // only if they cannot fit), a hairline under them.
            SizedBox(
              height: 56 * scale,
              child: LayoutBuilder(
                builder: (context, constraints) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: Row(
                      key: const ValueKey('tv_search_keys'),
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (final (i, key) in keys.indexed)
                          _KeyCap(keyData: key, highlighted: focused && i == index, scale: scale, muted: muted),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 14 * scale),
            Container(height: 1, color: colors.onSurface.withValues(alpha: 0.22)),
          ],
        ),
      ),
    );
  }
}

class _KeyCap extends StatelessWidget {
  const _KeyCap({required this.keyData, required this.highlighted, required this.scale, required this.muted});

  final _Key keyData;
  final bool highlighted;
  final double scale;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final foreground = highlighted ? Colors.black : onSurface;
    final Widget label = switch (keyData.kind) {
      _KeyKind.delete => AppIcon(Symbols.backspace_rounded, fill: 1, size: 26 * scale, color: foreground),
      _KeyKind.dictate => AppIcon(Symbols.mic_rounded, fill: 1, size: 26 * scale, color: foreground),
      _KeyKind.space || _KeyKind.toggleDigits => Text(
        keyData.value,
        style: TextStyle(fontSize: 16 * scale, fontWeight: FontWeight.w700, color: foreground, letterSpacing: 0.6),
      ),
      _KeyKind.character => Text(
        keyData.value,
        style: TextStyle(fontSize: 30 * scale, fontWeight: FontWeight.w500, color: foreground),
      ),
    };
    final wide = keyData.kind == _KeyKind.space || keyData.kind == _KeyKind.toggleDigits;
    final boxed = wide && !highlighted;
    return AnimatedScale(
      scale: highlighted ? 1.18 : 1,
      duration: const Duration(milliseconds: 90),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 3 * scale),
        padding: EdgeInsets.symmetric(horizontal: (wide ? 14 : 10) * scale, vertical: 6 * scale),
        constraints: BoxConstraints(minWidth: 40 * scale, minHeight: 48 * scale),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted
              ? Colors.white
              : boxed
              ? onSurface.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10 * scale),
          boxShadow: highlighted
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 12 * scale,
                    offset: Offset(0, 4 * scale),
                  ),
                ]
              : null,
        ),
        child: label,
      ),
    );
  }
}
