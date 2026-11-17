import '../../media/media_item.dart';
import '../../models/catalog/catalog_item.dart';
import '../../models/catalog/catalog_metadata.dart';
import '../../utils/app_logger.dart';
import '../data_aggregation_service.dart';
import 'seerr_catalog_source.dart';

enum RecommendationAvailability { checking, owned, missing, requested, unknown }

/// Local rendering metadata, independent of catalog routing. Owned cards remain
/// real server items (artwork, favorites, context menu and navigation included).
class RecommendationCardData {
  static const rawKey = 'plezyDetailRecommendation';
  final CatalogItem ratingItem;
  final RecommendationAvailability availability;
  const RecommendationCardData(this.ratingItem, this.availability);

  static RecommendationCardData? fromItem(MediaItem item) {
    final data = item.raw?[rawKey];
    if (data is! Map || data['ratingItem'] is! Map) return null;
    final availability = RecommendationAvailability.values.asNameMap()[data['availability']];
    if (availability == null) return null;
    return RecommendationCardData(
      CatalogItem.fromJson((data['ratingItem'] as Map).cast<String, Object?>()),
      availability,
    );
  }

  MediaItem attach(MediaItem item) => item.copyWith(
    raw: {
      ...?item.raw,
      rawKey: {'ratingItem': ratingItem.toJson(), 'availability': availability.name},
    },
  );
}

CatalogItem _requestItem(CatalogItem item, SeerrCatalogSource? seerr) => seerr != null && item.ids.tmdb != null
    ? CatalogItem.fromJson({...item.toJson(), 'source': CatalogSourceId.seerr.name})
    : item;

/// Publish the recommendations immediately, then replace artwork with verified
/// library copies in small batches. Failed/offline servers never imply absence.
/// Only missing titles need a supplemental Seerr status lookup.
Stream<List<MediaItem>> resolveDetailRecommendations(
  List<CatalogItem> recommendations, {
  required Future<LibraryLookupResult> Function(CatalogItem) match,
  SeerrCatalogSource? seerr,
  bool Function()? isCurrent,
}) async* {
  bool current() => isCurrent?.call() ?? true;
  final items = [
    for (final item in recommendations)
      RecommendationCardData(
        _requestItem(item, seerr),
        RecommendationAvailability.checking,
      ).attach(_requestItem(item, seerr).toMediaItem()),
  ];
  if (!current()) return;
  yield List.of(items);
  for (var start = 0; start < recommendations.length && current(); start += 4) {
    final end = (start + 4).clamp(0, recommendations.length);
    await Future.wait([
      for (var index = start; index < end; index++)
        () async {
          if (!current()) return;
          final recommendation = recommendations[index];
          final requestItem = _requestItem(recommendation, seerr);
          try {
            final result = await match(recommendation);
            if (!current()) return;
            if (result.items.isNotEmpty) {
              items[index] = RecommendationCardData(
                requestItem,
                RecommendationAvailability.owned,
              ).attach(result.items.first);
              return;
            }
            final absenceConfirmed =
                result.succeededServerIds.isNotEmpty &&
                result.failedServerIds.isEmpty &&
                result.cancelledServerIds.isEmpty &&
                result.unqueriedServerIds.isEmpty;
            if (!absenceConfirmed) {
              items[index] = RecommendationCardData(
                requestItem,
                RecommendationAvailability.unknown,
              ).attach(requestItem.toMediaItem());
              return;
            }
            var enriched = requestItem;
            if (seerr != null && requestItem.source == CatalogSourceId.seerr) {
              try {
                final detail = (await seerr.fetchDetail(requestItem, castLimit: 0, relatedLimit: 0)).item;
                enriched = CatalogItem.fromJson({
                  ...requestItem.toJson(),
                  if (detail.serverState != null) 'serverState': detail.serverState!.toJson(),
                });
              } catch (error) {
                appLogger.d('Recommendation request status unavailable', error: error);
              }
            }
            final state = enriched.serverState;
            bool active(CatalogRequestState? value) =>
                value == CatalogRequestState.pending ||
                value == CatalogRequestState.approved ||
                value == CatalogRequestState.processing;
            final requested = active(state?.request) || active(state?.request4k);
            items[index] = RecommendationCardData(
              enriched,
              requested ? RecommendationAvailability.requested : RecommendationAvailability.missing,
            ).attach(enriched.toMediaItem());
          } catch (error) {
            appLogger.d('Recommendation library lookup unavailable', error: error);
            items[index] = RecommendationCardData(
              requestItem,
              RecommendationAvailability.unknown,
            ).attach(requestItem.toMediaItem());
          }
        }(),
    ]);
    if (current()) yield List.of(items);
  }
}
