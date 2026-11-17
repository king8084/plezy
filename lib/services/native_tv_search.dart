import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// How Apple's native search keyboard was left.
enum NativeTvSearchEnd {
  /// The keyboard's Search key.
  submitted,

  /// Down from the keyboard toward the results.
  movedDown,

  /// Menu/Back (or closed by Plezy).
  dismissed,
}

/// Apple's own tvOS search keyboard (a UISearchController in a
/// UISearchContainerViewController, tvos/Runner/NativeSearchPlugin.swift):
/// one row of letters at the top of the screen, hold the Siri Remote's mic to
/// dictate. Plezy's results stay visible underneath; every change streams back
/// through [open]'s `onChanged`.
class NativeTvSearch {
  NativeTvSearch._();

  static final NativeTvSearch instance = NativeTvSearch._();

  @visibleForTesting
  static const MethodChannel channel = MethodChannel('plezy/native_search');

  ValueChanged<String>? _onChanged;
  void Function(String text, NativeTvSearchEnd end)? _onEnded;
  bool _handlerInstalled = false;
  bool _active = false;

  bool get isActive => _active;

  /// Shows the keyboard with [text]. False when it cannot be shown (no native
  /// side, or already open); callers then fall back to Plezy's keyboard.
  Future<bool> open({
    required String text,
    required String placeholder,
    required ValueChanged<String> onChanged,
    required void Function(String text, NativeTvSearchEnd end) onEnded,
  }) async {
    if (_active) return false;
    if (!_handlerInstalled) {
      channel.setMethodCallHandler(_handle);
      _handlerInstalled = true;
    }
    _onChanged = onChanged;
    _onEnded = onEnded;
    try {
      final shown = await channel.invokeMethod<bool>('open', {'text': text, 'placeholder': placeholder}) ?? false;
      _active = shown;
      return shown;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (error) {
      appLogger.w('Native search keyboard unavailable', error: error);
      return false;
    }
  }

  Future<void> close() async {
    if (!_active) return;
    try {
      await channel.invokeMethod<void>('close');
    } on MissingPluginException {
      _active = false;
    } on PlatformException {
      _active = false;
    }
  }

  Future<void> _handle(MethodCall call) async {
    switch (call.method) {
      case 'changed':
        _onChanged?.call(call.arguments is String ? call.arguments as String : '');
      case 'ended':
        final arguments = call.arguments is Map ? call.arguments as Map : const {};
        final text = arguments['text'] is String ? arguments['text'] as String : '';
        final end = switch (arguments['event']) {
          'submit' => NativeTvSearchEnd.submitted,
          'down' => NativeTvSearchEnd.movedDown,
          _ => NativeTvSearchEnd.dismissed,
        };
        _active = false;
        final onEnded = _onEnded;
        _onChanged = null;
        _onEnded = null;
        onEnded?.call(text, end);
    }
  }
}
