part of '../media_detail_screen.dart';

extension _MediaDetailSimklRecommendations on _MediaDetailScreenState {
  void _syncSimklRecommendationsSource() {
    if (!PlatformDetector.isTV() || widget.isOffline) return;
    final source = context.watch<CatalogSourcesProvider?>()?.simklSource;
    if (identical(source, _simklRecommendationsSource)) return;
    _simklRecommendationsSource = source;
    _simklRecommendationsGeneration++;
    _simklRecommendationsHub = null;
    if (!_isLoadingMetadata) unawaited(_loadSimklRecommendations());
  }

  Future<void> _loadSimklRecommendations() async {
    if (!PlatformDetector.isTV() || widget.isOffline || !_canUseDetail) return;
    final source = _simklRecommendationsSource;
    final item = _metadata;
    if (source == null || (!item.isShow && !item.isMovie)) return;
    final client = _getMediaClientForMetadata(context);
    final matcher = context.read<CatalogLibraryMatcher?>();
    if (client == null || matcher == null) return;
    final seerr = _seerrRecommendationsSource;
    final generation = ++_simklRecommendationsGeneration;
    bool isCurrent() =>
        _canUseDetail &&
        generation == _simklRecommendationsGeneration &&
        identical(source, _simklRecommendationsSource) &&
        identical(seerr, _seerrRecommendationsSource);
    try {
      final ids = await client.fetchExternalIds(item.id);
      if (!isCurrent()) return;
      final recommendations = await source.fetchTitleRecommendations(item.kind, ids);
      if (!isCurrent()) return;
      await for (final items in resolveDetailRecommendations(
        recommendations,
        match: matcher.match,
        seerr: seerr,
        isCurrent: isCurrent,
      )) {
        if (!isCurrent()) return;
        setStateIfMounted(() {
          _simklRecommendationsHub = items.isEmpty
              ? null
              : MediaHub(
                  id: 'detail_simkl_recommendations',
                  identifier: 'detail.simkl.recommendations',
                  title: t.discover.moreLikeThisSimkl,
                  type: item.isMovie ? 'movie' : 'show',
                  items: items,
                  size: items.length,
                );
        });
      }
    } catch (error) {
      appLogger.d('Simkl recommendations shelf unavailable', error: error);
    }
  }
}
