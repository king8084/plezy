import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../services/native_tv_search.dart';

/// Reserves the top of a search page for Apple's docked search keyboard
/// (see [NativeTvSearch]) and keeps it in step with the page:
///
/// * docked only while this page is the visible tab and the current route,
///   removed as soon as it is not (another tab, a pushed detail page);
/// * the keyboard types while [focusNode] has focus, and lets go when focus
///   moves to the results or the sidebar;
/// * text flows both ways with [controller].
///
/// If the keyboard cannot be shown, [onUnavailable] lets the page fall back
/// to Plezy's own keyboard.
class NativeSearchDock extends StatefulWidget {
  const NativeSearchDock({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.height,
    required this.onDown,
    required this.onSubmit,
    required this.onUnavailable,
    this.onNavigateLeft,
    this.onBack,
  });

  final TextEditingController controller;

  /// Focus stand-in for the native keyboard: focusing it gives the keyboard
  /// the remote; the page's "up from results" already targets it.
  final FocusNode focusNode;
  final String placeholder;
  final double height;

  /// Down from the keyboard: move focus into the results.
  final VoidCallback onDown;
  final ValueChanged<String> onSubmit;
  final VoidCallback onUnavailable;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onBack;

  @override
  State<NativeSearchDock> createState() => _NativeSearchDockState();
}

class _NativeSearchDockState extends State<NativeSearchDock> {
  final _boxKey = GlobalKey(debugLabel: 'native_search_dock');
  bool _docked = false;
  bool _docking = false;
  bool _applyingNativeText = false;
  bool _shown = true;
  Rect? _rect;

  NativeTvSearch get _native => NativeTvSearch.instance;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
    FocusManager.instance.addListener(_onPrimaryFocusChanged);
  }

  @override
  void didUpdateWidget(NativeSearchDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (!identical(oldWidget.focusNode, widget.focusNode)) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    FocusManager.instance.removeListener(_onPrimaryFocusChanged);
    if (_docked) unawaited(_native.undock());
    super.dispose();
  }

  void _onTextChanged() {
    if (_docked && !_applyingNativeText) unawaited(_native.setText(widget.controller.text));
  }

  void _onFocusChanged() {
    if (!_docked) return;
    unawaited(widget.focusNode.hasFocus ? _native.focus() : _native.blur());
  }

  /// Focus outside this page (the expanded sidebar, a sheet) hides the
  /// keyboard so it never covers what Plezy draws there.
  void _onPrimaryFocusChanged() {
    if (!_docked || !mounted) return;
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return;
    final inPage = Scaffold.maybeOf(focused) == Scaffold.maybeOf(context);
    if (inPage == _shown) return;
    _shown = inPage;
    unawaited(_native.setVisible(inPage));
  }

  void _applyNativeText(String text) {
    if (!mounted || widget.controller.text == text) return;
    _applyingNativeText = true;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _applyingNativeText = false;
  }

  bool get _visible {
    if (!mounted) return false;
    final route = ModalRoute.of(context);
    return TickerMode.valuesOf(context).enabled && (route?.isCurrent ?? true);
  }

  Future<void> _sync() async {
    if (!mounted || _docking) return;
    if (!_visible) {
      if (_docked) {
        _docked = false;
        _rect = null;
        await _native.undock();
      }
      return;
    }
    final box = _boxKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize || !box.attached) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (_docked && rect == _rect) return;
    _docking = true;
    final shown = await _native.dock(
      rect: rect,
      text: widget.controller.text,
      placeholder: widget.placeholder,
      onChanged: _applyNativeText,
      onDown: () {
        if (mounted) widget.onDown();
      },
      onSubmit: (text) {
        if (!mounted) return;
        _applyNativeText(text);
        widget.onSubmit(text);
      },
    );
    _docking = false;
    if (!mounted) return;
    if (!shown) {
      widget.onUnavailable();
      return;
    }
    _docked = true;
    _rect = rect;
    _shown = true;
    if (widget.focusNode.hasFocus) unawaited(_native.focus());
    // The page may have moved while the call was in flight.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_sync()));
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    // Presses the keyboard could not use itself (nothing further left, Back)
    // reach Flutter here.
    if (key == LogicalKeyboardKey.arrowLeft && widget.onNavigateLeft != null) {
      widget.onNavigateLeft!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      widget.onDown();
      return KeyEventResult.handled;
    }
    if (key.isBackKey && widget.onBack != null && event is KeyDownEvent) {
      widget.onBack!();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_sync()));
    return Focus(
      focusNode: widget.focusNode,
      onKeyEvent: _onKey,
      child: SizedBox(key: _boxKey, height: widget.height, width: double.infinity),
    );
  }
}
