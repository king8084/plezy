import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../exceptions/media_server_exceptions.dart';
import '../focus/dpad_navigator.dart';
import '../focus/focusable_text_field.dart';
import '../i18n/strings.g.dart';
import '../utils/layout_constants.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_item_merge.dart';
import '../media/media_person.dart';
import '../media/search_hit.dart';
import '../mixins/debounced_media_search.dart';
import '../mixins/mounted_set_state_mixin.dart';
import '../mixins/refreshable.dart';
import '../mixins/tab_visibility_aware.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../services/data_aggregation_service.dart';
import '../services/settings_service.dart';
import '../services/smart_search/smart_search_client.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../utils/media_server_http_client.dart';
import '../utils/search_relevance.dart';
import '../widgets/desktop_app_bar.dart';
import '../widgets/loading_indicator_box.dart';
import '../utils/dictation_auto_return.dart';
import '../widgets/tv_search_header.dart';
import '../widgets/search_input_field.dart';
import '../widgets/focusable_media_card.dart';
import '../widgets/focusable_tab_chip.dart';
import '../widgets/person_search_row.dart';
import '../utils/focus_utils.dart';
import 'libraries/state_messages.dart';
import 'main_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  /// TV keyboard for the search field: Plezy's docked overlay keeps results
  /// visible and updating while typing (the Apple TV system keyboard covers
  /// the whole screen). Shared by the show page's Find. Tests of the
  /// platform-keyboard flow switch it back.
  static TvTextInputPresentation keyboardPresentation = TvTextInputPresentation.flutterOverlay;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with
        Refreshable,
        ManualRefreshable,
        FullRefreshable,
        SearchInputFocusable,
        FocusableTab,
        TabVisibilityAware,
        MountedSetStateMixin,
        DebouncedMediaSearch<SearchScreen, SearchHit> {
  final _headerKey = GlobalKey<TvSearchHeaderState>();
  final _resultsScroll = ScrollController();
  String? _focusResultsForQuery;
  final _tvTextInputController = TvTextInputController();
  AbortController? _activeSearchAbort;
  ({String query, SearchAggregationResult result})? _pendingSearchOutcome;

  /// Filter over the current results: everything, one media kind, or only
  /// people. Chips and the filtered views derive from [_searchCandidates] and
  /// [_searchPeople] — the pre-rank pools behind the ranked [searchResults] —
  /// so a kind ranked out of the "All" top-N still gets a chip, and selecting
  /// a chip shows everything the servers returned for it.
  _SearchFilter _selectedFilter = const _AllResults();
  List<MediaItem> _searchCandidates = const [];
  List<MediaPerson> _searchPeople = const [];
  List<MediaKind> _candidateKinds = const [];
  List<SearchHit>? _filteredResults;
  late final FocusNode _allChipFocusNode = FocusNode(debugLabel: 'SearchKindChipAll');
  late final FocusNode _peopleChipFocusNode = FocusNode(debugLabel: 'SearchPeopleChip');
  final Map<MediaKind, FocusNode> _kindChipFocusNodes = {};

  HiddenLibrariesProvider? _hiddenLibraries;
  Set<String> _lastSeenHiddenKeys = const {};

  /// Meaning-based suggestions from the household smart-search index, shown
  /// as a section *after* the instant results so focus and the visible list
  /// never move when they arrive. Only for descriptive (3+ word) requests.
  /// Dictation: the 🎤 button switches this one session to the system
  /// keyboard (its remote microphone dictates); leaving the field switches
  /// back to the docked keyboard.
  bool _voiceInputActive = false;

  List<SmartSuggestion> _smartSuggestions = const [];
  bool _smartLoading = false;
  AbortController? _smartAbort;

  @override
  void initState() {
    super.initState();
    FocusUtils.requestFocusAfterBuild(this, searchFocusNode);
    searchFocusNode.addListener(_onSearchFocusChanged);
    unawaited(_bindHiddenLibraries());
  }

  @override
  void dispose() {
    _resultsScroll.dispose();
    _dictation.stop();
    _smartAbort?.abort();
    searchFocusNode.removeListener(_onSearchFocusChanged);
    _hiddenLibraries?.removeListener(_onHiddenLibrariesChanged);
    _allChipFocusNode.dispose();
    _peopleChipFocusNode.dispose();
    for (final node in _kindChipFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Re-run the visible query when a library is hidden or unhidden while
  /// results are on screen. The listener is attached only after the provider
  /// has hydrated, so its initial load notification cannot race the first
  /// query — which awaits that same hydration — into running twice.
  Future<void> _bindHiddenLibraries() async {
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    await hiddenLibraries.ensureInitialized();
    if (!mounted) return;
    _lastSeenHiddenKeys = Set.of(hiddenLibraries.hiddenLibraryKeys);
    _hiddenLibraries = hiddenLibraries..addListener(_onHiddenLibrariesChanged);
  }

  void _onHiddenLibrariesChanged() {
    final hiddenLibraries = _hiddenLibraries;
    if (hiddenLibraries == null || !mounted) return;
    final currentKeys = hiddenLibraries.hiddenLibraryKeys;
    if (currentKeys.length == _lastSeenHiddenKeys.length && currentKeys.containsAll(_lastSeenHiddenKeys)) {
      return;
    }
    _lastSeenHiddenKeys = Set.of(currentKeys);
    final query = searchController.text.trim();
    if (query.isEmpty || !hasSearched) return;
    unawaited(runSearch(query));
  }

  @override
  String get searchDebugLabel => 'Search';

  /// With the household index answering in milliseconds, half the shared
  /// pause keeps typing responsive; plain server search keeps the default.
  @override
  Duration get searchDebounce {
    // A late keystroke callback can outlive the providers (e.g. after
    // dispose): fall back to the shared pause rather than throwing.
    if (!mounted) return super.searchDebounce;
    try {
      return context.read<MultiServerProvider>().aggregationService.smartSearchKnownAvailable
          ? const Duration(milliseconds: 150)
          : super.searchDebounce;
    } on ProviderNotFoundException {
      return super.searchDebounce;
    }
  }

  @override
  Future<List<SearchHit>> performSearchQuery(String query) async {
    final multiServerProvider = Provider.of<MultiServerProvider>(context, listen: false);
    if (!multiServerProvider.hasConnectedServers) {
      throw const _SearchUnavailableException();
    }

    // Hidden-library keys must be hydrated before the first query, or a cold
    // start would filter nothing. Read before any await: the profile subtree
    // can be torn down mid-search.
    final hiddenLibraries = context.read<HiddenLibrariesProvider>();
    await hiddenLibraries.ensureInitialized();
    if (!mounted) return const [];

    final abort = AbortController();
    _activeSearchAbort = abort;
    try {
      final result = await multiServerProvider.aggregationService.searchAcrossServers(
        query,
        hiddenLibraryKeys: hiddenLibraries.hiddenLibraryKeys,
        abort: abort,
        onEarlyHits: (hits) => _showEarlyHits(query, hits),
      );
      abort.throwIfAborted();
      if (result.succeededServerIds.isEmpty && result.failedServerIds.isNotEmpty) {
        throw const _SearchUnavailableException();
      }
      if (result.succeededServerIds.isEmpty && result.cancelledServerIds.isNotEmpty) {
        throw MediaServerHttpException(
          type: MediaServerHttpErrorType.cancelled,
          message: 'Search was cancelled before any server completed',
        );
      }
      _pendingSearchOutcome = (query: query, result: result);
      return result.hits;
    } finally {
      if (identical(_activeSearchAbort, abort)) _activeSearchAbort = null;
    }
  }

  /// The household index's titles, shown while people and the server's own
  /// search are still running; the full answer replaces them.
  void _showEarlyHits(String query, List<SearchHit> hits) {
    if (!mounted) return;
    publishEarlyResults(
      query,
      hits,
      alongside: () {
        _searchCandidates = [
          for (final hit in hits)
            if (hit case MediaSearchHit(:final item)) item,
        ];
        _searchPeople = const [];
        _candidateKinds = _kindsIn(_searchCandidates);
        if (!_hasCandidatesFor(_selectedFilter)) _selectedFilter = const _AllResults();
        _filteredResults = _rankFilteredResults(_selectedFilter, query);
      },
    );
  }

  @override
  void onSearchInvalidated() {
    _activeSearchAbort?.abort();
    _activeSearchAbort = null;
    _pendingSearchOutcome = null;
    _cancelSmartSuggestions();
  }

  static bool _wantsSmartSuggestions(String query) => query.trim().split(RegExp(r'\s+')).length >= 3;

  void _cancelSmartSuggestions() {
    _smartAbort?.abort();
    _smartAbort = null;
    _smartLoading = false;
    _smartSuggestions = const [];
  }

  Future<void> _loadSmartSuggestions(String query) async {
    _cancelSmartSuggestions();
    if (!_wantsSmartSuggestions(query)) return;
    final multiServer = context.read<MultiServerProvider>();
    final hiddenKeys = context.read<HiddenLibrariesProvider>().hiddenLibraryKeys;
    final abort = AbortController();
    _smartAbort = abort;
    setState(() => _smartLoading = true);
    List<SmartSuggestion> suggestions;
    try {
      suggestions = await multiServer.aggregationService.smartSuggestions(
        query,
        hiddenLibraryKeys: hiddenKeys,
        abort: abort,
      );
    } catch (e) {
      appLogger.d('Smart suggestions skipped', error: e);
      suggestions = const [];
    }
    // Ignore answers for a query the user has already moved on from.
    if (!mounted || !identical(_smartAbort, abort)) return;
    final alreadyShown = {
      for (final hit in searchResults.take(5))
        if (hit is MediaSearchHit) hit.item.globalKey,
    };
    setState(() {
      _smartLoading = false;
      _smartSuggestions = [
        for (final suggestion in suggestions)
          if (!alreadyShown.contains(suggestion.item.globalKey)) suggestion,
      ];
    });
  }

  @override
  void onSearchError(Object error) {
    _cancelSmartSuggestions();
    _focusResultsForQuery = null;
    _pendingSearchOutcome = null;
    _resetFilter();
    final message = error is _SearchUnavailableException
        ? t.errors.searchUnavailable
        : t.errors.searchFailed(error: error);
    showErrorSnackBar(context, message);
  }

  @override
  void onSearchCleared() {
    _cancelSmartSuggestions();
    _focusResultsForQuery = null;
    _pendingSearchOutcome = null;
    _resetFilter();
  }

  @override
  void onSearchCompleted(String query, List<SearchHit> results) {
    final outcome = _pendingSearchOutcome;
    _pendingSearchOutcome = null;
    final matched = outcome != null && outcome.query == query ? outcome.result : null;

    // Committed alongside the results the pending setState renders (build has
    // not run yet): the pre-rank pools the filter chips derive from. A selected
    // filter survives a refined query as long as it still has candidates;
    // otherwise it falls back to "All".
    _searchCandidates =
        matched?.candidates ??
        [
          for (final hit in results)
            if (hit case MediaSearchHit(:final item)) item,
        ];
    _searchPeople =
        matched?.people ??
        [
          for (final hit in results)
            if (hit case PersonSearchHit(:final person)) person,
        ];
    _candidateKinds = _kindsIn(_searchCandidates);
    if (!_hasCandidatesFor(_selectedFilter)) _selectedFilter = const _AllResults();
    _filteredResults = _rankFilteredResults(_selectedFilter, query);

    if (matched != null && matched.failedServerIds.isNotEmpty) {
      showAppSnackBar(context, t.messages.searchPartialResults);
    }

    // After this frame's results render: the smart section only appends.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && searchController.text.trim() == query) unawaited(_loadSmartSuggestions(query));
    });

    if (_focusResultsForQuery == null || _focusResultsForQuery != query) return;
    _focusResultsForQuery = null;
    if (results.isEmpty) return;
    if (searchController.text.trim() != query) return; // user kept editing
    FocusUtils.requestFocusAfterBuild(this, firstResultFocusNode);
  }

  bool get _usesDockedKeyboard =>
      !_voiceInputActive && SearchScreen.keyboardPresentation == TvTextInputPresentation.flutterOverlay;

  /// Apple TV: the static search header (big query line, one row of keys),
  /// drawn by Plezy. Dictation swaps in the system keyboard field briefly.
  bool get _usesSearchHeader =>
      PlatformDetector.isAppleTV() &&
      !_voiceInputActive &&
      SearchScreen.keyboardPresentation == TvTextInputPresentation.flutterOverlay;

  /// Down from the keys: into the filters or the first result.
  void _focusResultsFromHeader() {
    if (searchResults.isEmpty) return;
    if (_showFilterChips) {
      _focusFilterChips();
    } else {
      firstResultFocusNode.requestFocus();
    }
  }

  /// Back from anywhere in the results: to the keys, on "a", page at the top.
  void _backToKeyboard() {
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    _headerKey.currentState?.resetToFirstLetter();
    searchFocusNode.requestFocus();
  }

  /// Leaving the Search tab forgets the search: coming back starts empty.
  @override
  void onTabHidden() {
    if (_voiceInputActive) _endVoiceInput();
    _cancelSmartSuggestions();
    if (searchController.text.isNotEmpty) searchController.clear();
    _resetFilter();
    if (_resultsScroll.hasClients) _resultsScroll.jumpTo(0);
    _headerKey.currentState?.resetToFirstLetter();
  }

  @override
  void onTabShown() {}

  Widget _buildSearchHeader(BuildContext context) {
    return TvSearchHeader(
      key: _headerKey,
      controller: searchController,
      focusNode: searchFocusNode,
      placeholder: t.common.search,
      onDown: _focusResultsFromHeader,
      onNavigateLeft: _navigateToSidebar,
      onSubmit: handleSearchSubmit,
      onDictate: _startVoiceInput,
      dictateTooltip: t.search.voiceSearch,
      onBack: () {
        if (searchController.text.isNotEmpty) {
          searchController.clear();
        } else {
          _navigateToSidebar();
        }
      },
    );
  }

  void _onSearchFocusChanged() {
    if (!searchFocusNode.hasFocus && _voiceInputActive && mounted) {
      _dictation.stop();
      setState(() => _voiceInputActive = false);
    }
  }

  late final _dictation = DictationAutoReturn(controller: searchController, onSpoken: _endVoiceInput);

  void _startVoiceInput() {
    setState(() => _voiceInputActive = true);
    _dictation.start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _tvTextInputController.focusAndOpenTextInput();
    });
  }

  /// Spoken words have landed: put Apple's keyboard away and return to the
  /// search bar, with the results already updating underneath.
  void _endVoiceInput() {
    _dictation.stop();
    if (!mounted || !_voiceInputActive) return;
    _tvTextInputController.closeTextInput();
    setState(() => _voiceInputActive = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) searchFocusNode.requestFocus();
    });
  }

  /// OSK "Search" / hardware Enter on TV additionally focuses the results
  /// when the forced search lands.
  @override
  void handleSearchSubmit() {
    final query = searchController.text.trim();
    if (query.isEmpty) return;
    // The docked keyboard stays up until asked: "Search" puts it away so the
    // results can take focus.
    if (_usesDockedKeyboard) _tvTextInputController.closeTextInput();
    if (searchResults.isEmpty || isSearching || query != lastSearchedQuery) {
      _focusResultsForQuery = query;
    }
    super.handleSearchSubmit();
  }

  @override
  void refresh() {
    if (!mounted) return;
    runSearch(searchController.text.trim());
  }

  /// Cmd+R / Ctrl+R re-runs the query currently on screen; `runSearch` no-ops
  /// on an empty field.
  @override
  void manualRefresh() => refresh();

  /// Focus the search input field
  @override
  void focusSearchInput() {
    if (!mounted) return;
    searchFocusNode.requestFocus();
  }

  @override
  void focusActiveTabIfReady() {
    if (!mounted) return;
    searchFocusNode.requestFocus();
  }

  /// Apply a complete query submitted from the Plezy companion remote: set the
  /// text, dismiss any open on-screen keyboard, land focus on the input without
  /// (re)opening the OSK, and run the search now — the first result takes focus
  /// when it lands (via onSearchCompleted). The user already typed the query on
  /// their phone, so the TV keyboard must never be up afterwards.
  @override
  void submitSearchQuery(String query) {
    if (!mounted) return;
    final trimmed = query.trim();
    searchController.text = trimmed; // listener arms the debounce / resets state

    // Focusing the field normally auto-opens the OSK; a remote search must not
    // show it, and must dismiss one the TV user already had open (the phone's
    // Search chip sends tabSearch before the query arrives).
    _tvTextInputController.closeTextInput();
    if (trimmed.isEmpty) return;

    // Land focus on the (visible) input immediately so the D-pad remote is
    // never stranded on the hidden previous tab — while the search is in
    // flight, when it fails, and when it returns nothing.
    _tvTextInputController.focusInputWithoutOpening();

    // Same path as the OSK Search key: jumps straight to already-matching
    // results, or cancels the debounce and runs now; the screen override arms
    // _focusResultsForQuery so results take focus when they land.
    handleSearchSubmit();
  }

  // Public method to fully reload all content (for profile switches)
  @override
  void fullRefresh() {
    if (!mounted) return;
    appLogger.d('SearchScreen.fullRefresh() called - clearing search and reloading');
    // Clearing the field resets the search state through the text listener.
    _focusResultsForQuery = null;
    searchController.clear();
  }

  Future<void> updateItem(MediaItem source) async {
    if (!mounted) return;
    final serverId = source.serverId;
    if (serverId == null) return;

    try {
      final multiServer = context.read<MultiServerProvider>();
      final updated = await multiServer.getClientForServer(ServerId(serverId))?.fetchItem(source.id);
      if (!mounted || updated == null) return;
      // A fresh Jellyfin `fetchItem` carries no library field, and a
      // library-less row would lose its label (#1970); keep the identity
      // and library context the search stamped on the original row.
      final merged = mergeFetchedMediaItem(fetched: updated, fallbackServerId: ServerId(serverId), existing: source);
      // The same row can sit in the ranked "All" list, the filtered view,
      // and the candidate pool; refresh every copy so a later chip switch
      // cannot resurrect the stale row.
      var replaced = _replaceHitByGlobalKey(searchResults, source.globalKey, merged);
      replaced = _replaceByGlobalKey(_searchCandidates, source.globalKey, merged) || replaced;
      final filtered = _filteredResults;
      if (filtered != null) {
        replaced = _replaceHitByGlobalKey(filtered, source.globalKey, merged) || replaced;
      }
      if (replaced) setState(() {});
    } catch (e) {
      appLogger.d('Search item refresh skipped for ${source.globalKey}', error: e);
    }
  }

  void _navigateToSidebar() {
    MainScreenFocusScope.focusSidebarOf(context);
  }

  /// Chip display order. `folder`/`unknown` are never search kinds, and
  /// `clip`/`photo` rows (Plex extras, Jellyfin/Emby home and music videos)
  /// stay reachable under "All" without a chip of their own.
  static const List<MediaKind> _kindFilterOrder = [
    MediaKind.movie,
    MediaKind.show,
    MediaKind.season,
    MediaKind.episode,
    MediaKind.artist,
    MediaKind.album,
    MediaKind.track,
    MediaKind.collection,
    MediaKind.playlist,
  ];

  static List<MediaKind> _kindsIn(List<MediaItem> candidates) {
    if (candidates.isEmpty) return const [];
    final present = {for (final item in candidates) item.kind};
    return [
      for (final kind in _kindFilterOrder)
        if (present.contains(kind)) kind,
    ];
  }

  static bool _replaceByGlobalKey(List<MediaItem> items, String globalKey, MediaItem replacement) {
    final index = items.indexWhere((item) => item.globalKey == globalKey);
    if (index == -1) return false;
    items[index] = replacement;
    return true;
  }

  static bool _replaceHitByGlobalKey(List<SearchHit> hits, String globalKey, MediaItem replacement) {
    final index = hits.indexWhere((hit) => hit is MediaSearchHit && hit.globalKey == globalKey);
    if (index == -1) return false;
    hits[index] = MediaSearchHit(replacement);
    return true;
  }

  /// The list the results sliver renders: the aggregation's ranked list, or
  /// the selected filter's pool re-ranked with the full display budget.
  List<SearchHit> get _visibleResults => _filteredResults ?? searchResults;

  /// Chip order: All, the media kinds present, then People.
  List<_SearchFilter> get _filterOptions => [
    const _AllResults(),
    for (final kind in _candidateKinds) _KindResults(kind),
    if (_searchPeople.isNotEmpty) const _PeopleResults(),
  ];

  /// "All" plus a single other option (one kind, or only people) has nothing
  /// to filter.
  bool get _showFilterChips => _candidateKinds.length + (_searchPeople.isEmpty ? 0 : 1) > 1;

  bool _hasCandidatesFor(_SearchFilter filter) => switch (filter) {
    _AllResults() => true,
    _KindResults(:final kind) => _candidateKinds.contains(kind),
    _PeopleResults() => _searchPeople.isNotEmpty,
  };

  /// The selected filter's pool re-ranked with the full display budget, or
  /// null for "All" (the aggregation's ranked list).
  List<SearchHit>? _rankFilteredResults(_SearchFilter filter, String query) {
    switch (filter) {
      case _AllResults():
        return null;
      case _KindResults(:final kind):
        final ofKind = [
          for (final candidate in _searchCandidates)
            if (candidate.kind == kind) candidate,
        ];
        return [
          for (final item in rankMediaSearchResults(ofKind, query, limit: defaultMediaSearchLimit))
            MediaSearchHit(item),
        ];
      case _PeopleResults():
        return [
          for (final person in rankPeopleSearchResults(_searchPeople, query, limit: defaultMediaSearchLimit))
            PersonSearchHit(person),
        ];
    }
  }

  void _selectFilter(_SearchFilter filter) {
    if (filter == _selectedFilter) return;
    setState(() {
      _selectedFilter = filter;
      _filteredResults = _rankFilteredResults(filter, lastSearchedQuery);
    });
  }

  void _resetFilter() {
    _selectedFilter = const _AllResults();
    _searchCandidates = const [];
    _searchPeople = const [];
    _candidateKinds = const [];
    _filteredResults = null;
  }

  FocusNode _chipFocusNode(_SearchFilter filter) => switch (filter) {
    _AllResults() => _allChipFocusNode,
    _KindResults(:final kind) => _kindChipFocusNodes.putIfAbsent(
      kind,
      () => FocusNode(debugLabel: 'SearchKindChip_${kind.id}'),
    ),
    _PeopleResults() => _peopleChipFocusNode,
  };

  /// D-pad landing point for the chip row: the chip that is currently active.
  void _focusFilterChips() => _chipFocusNode(_selectedFilter).requestFocus();

  void _focusFirstResult() {
    if (_visibleResults.isNotEmpty) firstResultFocusNode.requestFocus();
  }

  String _filterLabel(_SearchFilter filter) => switch (filter) {
    _AllResults() => t.libraries.groupings.all,
    _KindResults(:final kind) => _kindFilterLabel(kind),
    _PeopleResults() => t.search.people,
  };

  String _kindFilterLabel(MediaKind kind) => switch (kind) {
    MediaKind.movie => t.libraries.groupings.movies,
    MediaKind.show => t.libraries.groupings.shows,
    MediaKind.season => t.libraries.groupings.seasons,
    MediaKind.episode => t.libraries.groupings.episodes,
    MediaKind.artist => t.libraries.groupings.artists,
    MediaKind.album => t.libraries.groupings.albums,
    MediaKind.track => t.libraries.groupings.tracks,
    MediaKind.collection => t.libraries.tabs.collections,
    MediaKind.playlist => t.libraries.tabs.playlists,
    // Unreachable: excluded from _kindFilterOrder.
    MediaKind.clip || MediaKind.photo || MediaKind.folder || MediaKind.unknown => kind.id,
  };

  Widget _buildFilterChips() {
    // Chips trap RIGHT to keep focus inside the strip (see
    // FocusableChipStateMixin), so left/right neighbors are wired explicitly,
    // like every other tab-chip strip.
    final filters = _filterOptions;
    return SliverToBoxAdapter(
      child: Padding(
        // The search field's own bottom padding provides the gap above; the
        // results sliver below shrinks its top padding to match (16/16 visual
        // rhythm around the strip instead of the default 24/24).
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TabChipStrip(
          children: [
            for (final (index, filter) in filters.indexed) ...[
              if (index > 0) const SizedBox(width: 8),
              FocusableTabChip(
                label: _filterLabel(filter),
                isSelected: _selectedFilter == filter,
                focusNode: _chipFocusNode(filter),
                onSelect: () => _selectFilter(filter),
                onNavigateLeft: index == 0
                    ? _navigateToSidebar
                    : () => _chipFocusNode(filters[index - 1]).requestFocus(),
                onNavigateRight: index < filters.length - 1
                    ? () => _chipFocusNode(filters[index + 1]).requestFocus()
                    : null,
                onNavigateUp: focusSearchInput,
                onNavigateDown: _focusFirstResult,
                onBack: _navigateToSidebar,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "23 results" under the filter row: what the list below holds.
  Widget _buildResultCount(BuildContext context) {
    final count = _visibleResults.length;
    final scale = TvLayoutConstants.scaleOf(context);
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24 * scale, 4 * scale, 24 * scale, 0),
        child: Text(
          t.search.resultCount(n: count),
          key: const ValueKey('search_result_count'),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontSize: 18 * scale,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
          ),
        ),
      ),
    );
  }

  /// Apple TV results: an always-visible scrollbar, and Back from any result
  /// or filter returns to the keys on "a".
  Widget _tvResults(BuildContext context, Widget results) {
    final scale = TvLayoutConstants.scaleOf(context);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is KeyUpEvent || !event.logicalKey.isBackKey || searchFocusNode.hasFocus) {
          return KeyEventResult.ignored;
        }
        if (event is KeyDownEvent) _backToKeyboard();
        return KeyEventResult.handled;
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: RawScrollbar(
          controller: _resultsScroll,
          thumbVisibility: searchResults.isNotEmpty,
          thickness: 8 * scale,
          radius: Radius.circular(4 * scale),
          thumbColor: Colors.white.withValues(alpha: 0.7),
          trackVisibility: searchResults.isNotEmpty,
          trackColor: Colors.white.withValues(alpha: 0.12),
          trackBorderColor: Colors.transparent,
          crossAxisMargin: 6 * scale,
          mainAxisMargin: 8 * scale,
          child: results,
        ),
      ),
    );
  }

  Widget _buildResultsList(BuildContext context) {
    final multiServer = context.watch<MultiServerProvider>();
    final libraries = context.watch<LibrariesProvider>();
    final showServerName = multiServer.totalServerCount > 1;
    final showChips = _showFilterChips;
    final visible = _visibleResults;
    return buildResultsSliver(
      childCount: visible.length,
      // Half the default top padding when the chip strip sits directly above:
      // the strip already separates results from the search field.
      padding: showChips ? const EdgeInsets.fromLTRB(16, 8, 16, 16) : const EdgeInsets.all(16),
      (context, index) {
        final isFirst = index == 0;
        final onNavigateUp = isFirst ? (showChips ? _focusFilterChips : focusSearchInput) : null;
        return switch (visible[index]) {
          MediaSearchHit(:final item) => FocusableMediaCard(
            key: Key(item.globalKey),
            item: item,
            viewModeOverride: ViewMode.list,
            disableScale: true,
            focusNode: isFirst ? firstResultFocusNode : null,
            onRefresh: updateItem,
            onListRefresh: refresh,
            onNavigateLeft: _navigateToSidebar,
            onNavigateUp: onNavigateUp,
            showServerName: showServerName,
            libraryName: libraries.libraryLabelFor(item),
          ),
          PersonSearchHit(:final person) => PersonSearchRow(
            key: Key(person.globalKey),
            person: person,
            focusNode: isFirst ? firstResultFocusNode : null,
            showServerName: showServerName,
            onNavigateLeft: _navigateToSidebar,
            onNavigateUp: onNavigateUp,
          ),
        };
      },
    );
  }

  List<Widget> _buildSmartSuggestions(BuildContext context) {
    if (_selectedFilter is! _AllResults) return const [];
    if (!_smartLoading && _smartSuggestions.isEmpty) return const [];
    final confirmed = [
      for (final suggestion in _smartSuggestions)
        if (suggestion.match == SmartSearchMatch.confirmed) suggestion.item,
    ];
    final possible = [
      for (final suggestion in _smartSuggestions)
        if (suggestion.match != SmartSearchMatch.confirmed) suggestion.item,
    ];
    return [
      if (_smartLoading) _smartHeader(context, t.search.findingSmartMatches),
      if (confirmed.isNotEmpty) ...[_smartHeader(context, t.search.smartMatches), _buildSmartList(context, confirmed)],
      if (possible.isNotEmpty) ...[_smartHeader(context, t.search.possibleMatches), _buildSmartList(context, possible)],
    ];
  }

  Widget _smartHeader(BuildContext context, String label) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(label, style: Theme.of(context).textTheme.titleSmall),
    ),
  );

  Widget _buildSmartList(BuildContext context, List<MediaItem> items) {
    final multiServer = context.watch<MultiServerProvider>();
    final libraries = context.watch<LibrariesProvider>();
    final showServerName = multiServer.totalServerCount > 1;
    return buildResultsSliver(
      childCount: items.length,
      (context, index) => FocusableMediaCard(
        key: Key('smart-${items[index].globalKey}'),
        item: items[index],
        viewModeOverride: ViewMode.list,
        disableScale: true,
        onRefresh: updateItem,
        onListRefresh: refresh,
        onNavigateLeft: _navigateToSidebar,
        showServerName: showServerName,
        libraryName: libraries.libraryLabelFor(items[index]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final nativeHeader = _usesSearchHeader;
    final results = CustomScrollView(
      controller: _resultsScroll,
      primary: false,
      slivers: [
        if (!nativeHeader) DesktopSliverAppBar(title: Text(t.common.search), floating: true),
        if (!nativeHeader)
          SliverToBoxAdapter(
            child: SearchInputField(
              controller: searchController,
              focusNode: searchFocusNode,
              debugLabel: searchDebugLabel,
              hintText: t.search.hint,
              tvTextInputController: _tvTextInputController,
              tvTextInputPresentation: _voiceInputActive
                  ? TvTextInputPresentation.platform
                  : SearchScreen.keyboardPresentation,
              // The docked keyboard opens on Select, not merely on arriving at
              // the tab, so landing on Search never hides the screen.
              tvTextInputAutoOpenBehavior: _usesDockedKeyboard
                  ? TvTextInputAutoOpenBehavior.never
                  : TvTextInputAutoOpenBehavior.automatic,
              // Dictation needs the system keyboard; only offered where the
              // docked keyboard replaced it (Apple TV).
              onVoiceInput:
                  PlatformDetector.isAppleTV() && SearchScreen.keyboardPresentation != TvTextInputPresentation.platform
                  ? _startVoiceInput
                  : null,
              voiceInputTooltip: t.search.voiceSearch,
              onNavigateLeft: _navigateToSidebar,
              onNavigateDown: searchResults.isNotEmpty && !isSearching
                  ? (_showFilterChips ? _focusFilterChips : firstResultFocusNode.requestFocus)
                  : null,
              onEditingComplete: PlatformDetector.isTV() ? handleSearchSubmit : null,
              onBack: () {
                if (searchController.text.isNotEmpty) {
                  searchController.clear();
                } else {
                  _navigateToSidebar();
                }
              },
            ),
          ),
        // Results already on screen stay while the next keystroke's search
        // runs (and early index hits arrive); the spinner is only for a
        // first search with nothing to show yet.
        if (isSearching && searchResults.isEmpty)
          LoadingIndicatorBox.sliver
        else if (!hasSearched && nativeHeader)
          // Apple's keyboard above is the whole invitation; nothing else.
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (!hasSearched)
          SliverFillRemaining(
            child: StateMessageWidget(
              message: t.search.searchYourMedia,
              subtitle: t.search.enterTitleActorOrKeyword,
              icon: Symbols.search_rounded,
              iconSize: 80,
            ),
          )
        else if (lastSearchFailed)
          SliverFillRemaining(
            child: StateMessageWidget(message: t.explore.searchFailed, icon: Symbols.error_rounded, iconSize: 80),
          )
        else if (searchResults.isEmpty && !_smartLoading && _smartSuggestions.isEmpty)
          SliverFillRemaining(
            child: StateMessageWidget(
              message: t.messages.noResultsFound,
              subtitle: t.search.tryDifferentTerm,
              icon: Symbols.search_off_rounded,
              iconSize: 80,
            ),
          )
        else ...[
          if (_showFilterChips) _buildFilterChips(),
          if (nativeHeader) _buildResultCount(context),
          _buildResultsList(context),
          ..._buildSmartSuggestions(context),
        ],
      ],
    );
    return Scaffold(
      body: SafeArea(
        child: nativeHeader
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildSearchHeader(context),
                  Expanded(child: _tvResults(context, results)),
                ],
              )
            : results,
      ),
    );
  }
}

final class _SearchUnavailableException implements Exception {
  const _SearchUnavailableException();
}

/// One chip of the search results filter strip.
sealed class _SearchFilter {
  const _SearchFilter();
}

final class _AllResults extends _SearchFilter {
  const _AllResults();
}

final class _KindResults extends _SearchFilter {
  final MediaKind kind;

  const _KindResults(this.kind);

  @override
  bool operator ==(Object other) => other is _KindResults && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

final class _PeopleResults extends _SearchFilter {
  const _PeopleResults();
}
