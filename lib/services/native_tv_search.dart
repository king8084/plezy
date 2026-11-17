import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Apple's own tvOS search keyboard docked into Plezy's Search page
/// (tvos/Runner/NativeSearchPlugin.swift), the way Neptune and Apple's apps
/// show it: the big query line and the one-row keyboard at the top, results
/// underneath, hold the Siri Remote's mic to dictate.
///
/// The keyboard is a native child view placed in the rectangle passed to
/// [dock]. Focus moves between it and Flutter: Down from the keyboard calls
/// `onDown` (focus the first result); [focus] gives the keyboard focus back.
class NativeTvSearch {
  NativeTvSearch._();

  static final NativeTvSearch instance = NativeTvSearch._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('plezy/native_search');

  ValueChanged<String>? _onChanged;
  VoidCallback? _onDown;
  ValueChanged<String>? _onSubmit;
  bool _handlerInstalled = false;
  bool _docked = false;

  bool get isDocked => _docked;

  /// Shows the keyboard in [rect] (logical pixels, which are tvOS points).
  /// False when it cannot be shown; callers then use Plezy's own keyboard.
  Future<bool> dock({
    required Rect rect,
    required String text,
    required String placeholder,
    required ValueChanged<String> onChanged,
    required VoidCallback onDown,
    required ValueChanged<String> onSubmit,
  }) async {
    if (!_handlerInstalled) {
      channel.setMethodCallHandler(_handle);
      _handlerInstalled = true;
    }
    _onChanged = onChanged;
    _onDown = onDown;
    _onSubmit = onSubmit;
    try {
      final docked =
          await channel.invokeMethod<bool>('dock', {
            'x': rect.left,
            'y': rect.top,
            'width': rect.width,
            'height': rect.height,
            'text': text,
            'placeholder': placeholder,
          }) ??
          false;
      _docked = docked;
      return docked;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      appLogger.w('Apple search keyboard unavailable', error: error);
      return false;
    }
  }

  /// Gives the keyboard the remote's focus (typing).
  Future<void> focus() => _invoke('focus');

  /// Keeps the keyboard visible but lets Plezy's own views take focus.
  Future<void> blur() => _invoke('blur');

  Future<void> setText(String text) => _invoke('setText', {'text': text});

  /// Hides the keyboard while Plezy draws over its area (the expanded
  /// sidebar, sheets); a native view always sits above Flutter's drawing.
  Future<void> setVisible(bool visible) => _invoke('setVisible', {'visible': visible});

  Future<void> undock() async {
    if (!_docked) return;
    _docked = false;
    _onChanged = null;
    _onDown = null;
    _onSubmit = null;
    await _invoke('undock');
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    if (!_docked && method != 'undock') return;
    try {
      await channel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      _docked = false;
    } on PlatformException catch (error) {
      appLogger.w('Apple search keyboard: $method failed', error: error);
    }
  }

  Future<void> _handle(MethodCall call) async {
    final text = call.arguments is String ? call.arguments as String : '';
    switch (call.method) {
      case 'changed':
        _onChanged?.call(text);
      case 'down':
        _onDown?.call();
      case 'submit':
        _onSubmit?.call(text);
    }
  }
}
