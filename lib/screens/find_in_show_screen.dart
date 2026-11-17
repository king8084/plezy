import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../providers/multi_server_provider.dart';
import '../services/data_aggregation_service.dart';
import '../services/native_tv_search.dart';
import '../services/settings_service.dart';
import '../services/smart_search/smart_search_client.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart';
import '../utils/platform_detector.dart';
import '../utils/video_player_navigation.dart';
import '../widgets/episode_card.dart';
import '../widgets/overlay_sheet.dart';
import '../widgets/search_input_field.dart';
import 'search_screen.dart';

/// The show page's Find: describe a scene ("phil basketball") and get that
/// show's matching episodes, best first. Results update while typing (meaning
/// and text only); Search also asks the language model. Select plays.
class FindInShowScreen extends StatefulWidget {
  const FindInShowScreen({super.key, required this.show, this.client, @visibleForTesting this.service});

  final MediaItem show;
  final MediaServerClient? client;

  /// Defaults to the app's aggregation service (tests inject one).
  final DataAggregationService? service;

  @override
  State<FindInShowScreen> createState() => _FindInShowScreenState();
}

class _FindInShowScreenState extends State<FindInShowScreen> {
  final _controller = TextEditingController();
  final _fieldFocus = FocusNode(debugLabel: 'find_in_show_field');
  final _firstResultFocus = FocusNode(debugLabel: 'find_in_show_first_result');
  final _tvTextInput = TvTextInputController();

  static const _typingPause = Duration(milliseconds: 350);

  Timer? _debounce;
  AbortController? _abort;
  int _generation = 0;
  String _shownQuery = '';
  String _requestedQuery = '';
  List<SmartSuggestion> _results = const [];
  bool _loading = false;
  bool _failed = false;
  bool _voiceInputActive = false;
  bool _focusResultsWhenLoaded = false;

  DataAggregationService get _service => widget.service ?? context.read<MultiServerProvider>().aggregationService;

  bool get _usesDockedKeyboard =>
      !_voiceInputActive && SearchScreen.keyboardPresentation == TvTextInputPresentation.flutterOverlay;

  /// Apple's native search keyboard, as on the Search screen.
  bool get _usesNativeKeyboard =>
      PlatformDetector.isAppleTV() &&
      !_nativeKeyboardUnavailable &&
      SearchScreen.keyboardPresentation == TvTextInputPresentation.flutterOverlay &&
      SettingsService.instance.read(SettingsService.appleSearchKeyboard);
  bool _nativeKeyboardUnavailable = false;

  Future<void> _openNativeKeyboard() async {
    void setText(String text) {
      if (_controller.text == text) return;
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }

    final shown = await NativeTvSearch.instance.open(
      text: _controller.text,
      placeholder: t.findInShow.fieldHint,
      onChanged: (text) {
        if (mounted) setText(text);
      },
      onEnded: (text, end) {
        if (!mounted) return;
        setText(text);
        if (end == NativeTvSearchEnd.dismissed || text.trim().isEmpty) {
          _fieldFocus.requestFocus();
        } else {
          _submit();
        }
      },
    );
    if (shown || !mounted) return;
    setState(() => _nativeKeyboardUnavailable = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tvTextInput.focusAndOpenTextInput();
      WidgetsBinding.instance.scheduleFrame();
    });
    WidgetsBinding.instance.scheduleFrame();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Arriving focuses the field, which opens the keyboard: Find is for typing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldFocus.requestFocus();
      if (_usesNativeKeyboard) unawaited(_openNativeKeyboard());
    });
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus && _voiceInputActive && mounted) setState(() => _voiceInputActive = false);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _abort?.abort();
    _controller.dispose();
    _fieldFocus.dispose();
    _firstResultFocus.dispose();
    super.dispose();
  }

  void _onChanged() {
    final query = _controller.text.trim();
    // Cursor and selection moves notify too; only a changed request searches.
    if (query == _requestedQuery) return;
    _requestedQuery = query;
    _debounce?.cancel();
    if (query.isEmpty) {
      _abort?.abort();
      setState(() {
        _generation++;
        _shownQuery = '';
        _results = const [];
        _loading = false;
        _failed = false;
      });
      return;
    }
    _debounce = Timer(_typingPause, () => unawaited(_run(query, recall: false)));
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _debounce?.cancel();
    if (_usesDockedKeyboard) _tvTextInput.closeTextInput();
    _focusResultsWhenLoaded = true;
    unawaited(_run(query, recall: true));
  }

  Future<void> _run(String query, {required bool recall}) async {
    _abort?.abort();
    final abort = _abort = AbortController();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await _service.findInShow(widget.show, query, recall: recall, abort: abort);
      if (!mounted || generation != _generation) return;
      setState(() {
        _shownQuery = query;
        _results = results;
        _loading = false;
      });
      if (_focusResultsWhenLoaded && results.isNotEmpty) {
        _focusResultsWhenLoaded = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _firstResultFocus.requestFocus();
        });
      }
    } catch (error) {
      if (!mounted || generation != _generation || abort.isAborted) return;
      appLogger.w('Find in show failed', error: error);
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _startVoiceInput() {
    setState(() => _voiceInputActive = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvTextInput.focusAndOpenTextInput();
    });
  }

  Future<void> _play(MediaItem episode) async {
    await navigateToVideoPlayer(context, metadata: episode, isLaunchCurrent: () => mounted);
  }

  Widget _status(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
    child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
  );

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim();
    final Widget body;
    if (_failed) {
      body = _status(context, t.findInShow.failed);
    } else if (_results.isEmpty && !_loading && query.isNotEmpty && query == _shownQuery) {
      body = _status(context, t.findInShow.noResults);
    } else if (_results.isEmpty && query.isEmpty) {
      body = _status(context, t.findInShow.hint);
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final episode = _results[index].item;
          return EpisodeCard(
            key: ValueKey('find-${episode.id}'),
            episode: episode,
            client: widget.client,
            focusNode: index == 0 ? _firstResultFocus : null,
            onNavigateUp: index == 0 ? _fieldFocus.requestFocus : null,
            onTap: () => unawaited(_play(episode)),
          );
        },
      );
    }

    return OverlaySheetHost(
      canPop: true,
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(
                  t.findInShow.title(title: widget.show.displayTitle),
                  style: Theme.of(context).textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SearchInputField(
                controller: _controller,
                focusNode: _fieldFocus,
                hintText: t.findInShow.fieldHint,
                debugLabel: 'find_in_show',
                tvTextInputController: _tvTextInput,
                tvTextInputPresentation: _voiceInputActive
                    ? TvTextInputPresentation.platform
                    : SearchScreen.keyboardPresentation,
                tvTextInputAutoOpenBehavior: _usesNativeKeyboard
                    ? TvTextInputAutoOpenBehavior.never
                    : TvTextInputAutoOpenBehavior.automatic,
                onVoiceInput:
                    PlatformDetector.isAppleTV() &&
                        !_usesNativeKeyboard &&
                        SearchScreen.keyboardPresentation != TvTextInputPresentation.platform
                    ? _startVoiceInput
                    : null,
                onTvSelectOverride: _usesNativeKeyboard ? () => unawaited(_openNativeKeyboard()) : null,
                voiceInputTooltip: t.search.voiceSearch,
                onNavigateDown: _results.isEmpty ? null : _firstResultFocus.requestFocus,
                onEditingComplete: _submit,
                onBack: () => Navigator.of(context).maybePop(),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
              Expanded(child: body),
            ],
          ),
        ),
      ),
    );
  }
}
