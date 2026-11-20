part of '../media_detail_screen.dart';

extension _MediaDetailSeerrRecommendations on _MediaDetailScreenState {
  void _syncSeerrRecommendationsSource() {
    if (!PlatformDetector.isTV() || widget.isOffline) return;
    final source = context.watch<CatalogSourcesProvider?>()?.seerrSource;
    final permissions = context.watch<SeerrAccountProvider?>()?.permissions;
    if (identical(source, _seerrRecommendationsSource) && permissions == _seerrRecommendationsPermissions) return;
    _seerrRecommendationsSource = source;
    _seerrRecommendationsPermissions = permissions;
    _seerrRecommendationsGeneration++;
    _seerrRecommendationsHub = null;
    // Full library metadata and on-deck keep their existing priority. Seerr
    // is supplemental and never gates the show's reveal or the Play action.
    if (!_isLoadingMetadata) {
      unawaited(_loadSeerrRecommendations());
      unawaited(_loadSimklRecommendations());
    }
  }

  Future<void> _loadSeerrRecommendations() async {
    if (!PlatformDetector.isTV() || widget.isOffline || !_canUseDetail) return;
    final source = _seerrRecommendationsSource;
    final item = _metadata;
    if (source == null || (!item.isMovie && !item.isShow) || !source.canRequest(item.kind)) return;
    final client = _getMediaClientForMetadata(context);
    if (client == null) return;
    final generation = ++_seerrRecommendationsGeneration;
    bool isCurrent() =>
        _canUseDetail &&
        generation == _seerrRecommendationsGeneration &&
        identical(source, _seerrRecommendationsSource) &&
        source.canRequest(item.kind);
    try {
      final ids = await client.fetchExternalIds(item.id);
      if (!isCurrent() || ids.tmdb == null) return;
      final recommendations = await source.fetchRequestableRecommendations(item.kind, ids.tmdb!);
      if (!isCurrent()) return;
      setStateIfMounted(() {
        _seerrRecommendationsHub = recommendations.isEmpty
            ? null
            : MediaHub(
                id: 'detail_seerr_recommendations',
                identifier: 'detail.seerr.recommendations',
                title: t.discover.moreLikeThisRequest,
                type: item.isMovie ? 'movie' : 'show',
                // Captioned like the other "More like this" rows (star, IMDb
                // score, boxed vote count, year); only this row, not Seerr
                // cards elsewhere.
                items: [
                  for (final recommendation in recommendations)
                    RecommendationCardData(
                      recommendation,
                      RecommendationAvailability.unknown,
                    ).attach(recommendation.toMediaItem()),
                ],
                size: recommendations.length,
              );
      });
    } catch (error) {
      // Seerr going offline must leave the local library, episodes and cast
      // fully usable. A later account rebind or return from Request retries.
      appLogger.w('Seerr recommendations shelf unavailable', error: error);
    }
  }
}
