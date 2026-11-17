import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../focus/focusable_text_field.dart';
import 'app_icon.dart';
import 'pill_input_decoration.dart';

/// The pill search field the search screens put above their results, with the
/// clear affordance that appears once there is text: RIGHT out of the field
/// lands on it, LEFT goes back, and both escape down into the results.
///
/// [onBack] stays null unless the host wants the back key — a pushed route
/// needs it for its own pop.
class SearchInputField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;

  /// Names the clear button's focus node.
  final String debugLabel;

  final TvTextInputController? tvTextInputController;

  /// Which TV keyboard opens: the platform's (full-screen on Apple TV) or
  /// Plezy's docked overlay, which keeps results visible while typing.
  final TvTextInputPresentation tvTextInputPresentation;

  /// When focus alone opens the TV keyboard (Select always does).
  final TvTextInputAutoOpenBehavior tvTextInputAutoOpenBehavior;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onEditingComplete;
  final VoidCallback? onBack;

  /// Shows a microphone button that starts dictation (system keyboard).
  final VoidCallback? onVoiceInput;
  final String? voiceInputTooltip;

  const SearchInputField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.debugLabel,
    this.tvTextInputController,
    this.tvTextInputPresentation = TvTextInputPresentation.automatic,
    this.tvTextInputAutoOpenBehavior = TvTextInputAutoOpenBehavior.automatic,
    this.onNavigateLeft,
    this.onNavigateDown,
    this.onEditingComplete,
    this.onBack,
    this.onVoiceInput,
    this.voiceInputTooltip,
  });

  @override
  State<SearchInputField> createState() => _SearchInputFieldState();
}

class _SearchInputFieldState extends State<SearchInputField> {
  late final FocusNode _clearFocusNode = FocusNode(debugLabel: '${widget.debugLabel}.clear');
  late final FocusNode _voiceFocusNode = FocusNode(debugLabel: '${widget.debugLabel}.voice');

  @override
  void dispose() {
    _clearFocusNode.dispose();
    _voiceFocusNode.dispose();
    super.dispose();
  }

  void _clearSearch() {
    widget.controller.clear();
    widget.focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    final hasVoice = widget.onVoiceInput != null;
    final buttons = (hasText ? 1 : 0) + (hasVoice ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: Stack(
        alignment: Alignment.centerRight,
        children: [
          FocusableTextField(
            controller: widget.controller,
            focusNode: widget.focusNode,
            tvTextInputController: widget.tvTextInputController,
            tvTextInputPresentation: widget.tvTextInputPresentation,
            tvTextInputAutoOpenBehavior: widget.tvTextInputAutoOpenBehavior,
            textInputAction: TextInputAction.search,
            onNavigateLeft: widget.onNavigateLeft,
            onNavigateRight: hasVoice
                ? _voiceFocusNode.requestFocus
                : hasText
                ? _clearFocusNode.requestFocus
                : null,
            onNavigateDown: widget.onNavigateDown,
            onEditingComplete: widget.onEditingComplete,
            onBack: widget.onBack,
            decoration: pillInputDecoration(
              context,
              hintText: widget.hintText,
              prefixIcon: const AppIcon(Symbols.search_rounded, fill: 1),
              suffixIcon: buttons > 0 ? SizedBox(width: 48.0 * buttons) : null,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasVoice)
                FocusableButton(
                  focusNode: _voiceFocusNode,
                  onPressed: widget.onVoiceInput!,
                  onNavigateLeft: widget.focusNode.requestFocus,
                  onNavigateRight: hasText ? _clearFocusNode.requestFocus : null,
                  onNavigateDown: widget.onNavigateDown,
                  autoScroll: false,
                  child: IconButton(
                    icon: const AppIcon(Symbols.mic_rounded, fill: 1),
                    tooltip: widget.voiceInputTooltip,
                    onPressed: widget.onVoiceInput,
                  ),
                ),
              if (hasText)
                FocusableButton(
                  focusNode: _clearFocusNode,
                  onPressed: _clearSearch,
                  onNavigateLeft: hasVoice ? _voiceFocusNode.requestFocus : widget.focusNode.requestFocus,
                  onNavigateDown: widget.onNavigateDown,
                  autoScroll: false,
                  child: IconButton(icon: const AppIcon(Symbols.clear_rounded, fill: 1), onPressed: _clearSearch),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
