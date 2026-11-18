import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../providers/multi_server_provider.dart';
import '../services/data_aggregation_service.dart';
import '../services/smart_search/smart_search_client.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart';
import '../utils/platform_detector.dart';
import '../utils/video_player_navigation.dart';
import '../widgets/episode_card.dart';
import '../widgets/overlay_sheet.dart';
import '../utils/dictation_auto_return.dart';
import '../widgets/tv_search_header.dart';
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

  /// Apple TV: the same static search header as the Search screen.
  bool get _usesSearchHeader =>
      PlatformDetector.isAppleTV() &&
      !_voiceInputActive &&
      SearchScreen.keyboardPresentation == TvTextInputPresentation.flutterOverlay;

  Widget _buildSearchHeader(BuildContext context) {
    return TvSearchHeader(
      controller: _controller,
      focusNode: _fieldFocus,
      placeholder: t.findInShow.fieldHint,
      onDown: () {
        if (_results.isNotEmpty) _firstResultFocus.requestFocus();
      },
      onSubmit: _submit,
      onDictate: _startVoiceInput,
      dictateTooltip: t.search.voiceSearch,
      onBack: () => Navigator.of(context).maybePop(),
    );
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    // Arriving focuses the field, which opens the keyboard: Find is for typing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fieldFocus.requestFocus();
    });
    _fieldFocus.addListener(() {
      if (!_fieldFocus.hasFocus && _voiceInputActive && mounted) {
        _dictation.stop();
        setState(() => _voiceInputActive = false);
      }
    });
  }

  @override
  void dispose() {
    _dictation.stop();
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

  late final _dictation = DictationAutoReturn(controller: _controller, onSpoken: _endVoiceInput);

  void _startVoiceInput() {
    setState(() => _voiceInputActive = true);
    _dictation.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvTextInput.focusAndOpenTextInput();
    });
  }

  /// Spoken words have landed: put Apple's keyboard away and return to the
  /// search bar.
  void _endVoiceInput() {
    _dictation.stop();
    if (!mounted || !_voiceInputActive) return;
    _tvTextInput.closeTextInput();
    setState(() => _voiceInputActive = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
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
              if (_usesSearchHeader)
                _buildSearchHeader(context)
              else
                SearchInputField(
                  controller: _controller,
                  focusNode: _fieldFocus,
                  hintText: t.findInShow.fieldHint,
                  debugLabel: 'find_in_show',
                  tvTextInputController: _tvTextInput,
                  tvTextInputPresentation: _voiceInputActive
                      ? TvTextInputPresentation.platform
                      : SearchScreen.keyboardPresentation,
                  onVoiceInput:
                      PlatformDetector.isAppleTV() &&
                          SearchScreen.keyboardPresentation != TvTextInputPresentation.platform
                      ? _startVoiceInput
                      : null,
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
