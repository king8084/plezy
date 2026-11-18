import 'dart:async';

import 'package:flutter/widgets.dart';

/// Apple TV dictation needs Apple's own keyboard on screen; apps cannot start
/// it themselves. This brings the user straight back once they have spoken:
/// dictated words arrive in one piece (typing adds one character at a time),
/// so after such an insertion and a short quiet spell [onSpoken] runs, and the
/// screen closes the keyboard and returns to its own search bar.
class DictationAutoReturn {
  DictationAutoReturn({required this.controller, required this.onSpoken, this.quiet = const Duration(seconds: 1)});

  final TextEditingController controller;
  final VoidCallback onSpoken;
  final Duration quiet;

  Timer? _timer;
  String _last = '';
  bool _watching = false;

  bool get isWatching => _watching;

  void start() {
    if (_watching) return;
    _watching = true;
    _last = controller.text;
    controller.addListener(_onChanged);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (!_watching) return;
    _watching = false;
    controller.removeListener(_onChanged);
  }

  void _onChanged() {
    final text = controller.text;
    if (text == _last) return;
    final added = text.length - _last.length;
    _last = text;
    _timer?.cancel();
    // A one-character change is the user typing on Apple's keyboard: stay.
    if (added < 2) return;
    _timer = Timer(quiet, () {
      if (!_watching) return;
      stop();
      onSpoken();
    });
  }
}
