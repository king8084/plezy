import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/catalog_item_ref.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/models/catalog/catalog_metadata.dart';
import 'package:plezy/services/catalog/detail_recommendations.dart';
import 'package:plezy/services/catalog/seerr_catalog_source.dart';
import 'package:plezy/services/catalog/catalog_source.dart';
import 'package:plezy/services/data_aggregation_service.dart';

import '../../test_helpers/media_items.dart';

CatalogItem rec(int id) => CatalogItem(
  source: CatalogSourceId.simkl,
  kind: MediaKind.show,
  title: 'Recommendation $id',
  posterUrl: 'https://simkl.in/poster/$id.jpg',
  ids: CatalogItemIds(simkl: id, tmdb: id + 100, imdb: 'tt$id'),
);
LibraryLookupResult lookup({
  List<MediaItem> items = const [],
  Set<String> succeeded = const {'server'},
  Set<String> failed = const {},
  Set<String> unqueried = const {},
  Set<String> cancelled = const {},
}) => (
  items: items,
  succeededServerIds: succeeded,
  failedServerIds: failed,
  unqueriedServerIds: unqueried,
  cancelledServerIds: cancelled,
);

class _RequestSource extends Fake implements SeerrCatalogSource {
  _RequestSource(this.state);
  final CatalogServerState state;
  int reads = 0;
  @override
  Future<CatalogDetail> fetchDetail(CatalogItem item, {int castLimit = 20, int relatedLimit = 20}) async {
    reads++;
    return CatalogDetail(
      item: CatalogItem.fromJson({
        ...item.toJson(),
        'serverState': state.toJson(),
        'posterUrl': 'https://seerr.example/replacement.jpg',
      }),
    );
  }
}

void main() {
  test('row publishes before matching, owned cards retain real identity, poster and favorite state', () async {
    final gate = Completer<LibraryLookupResult>();
    final original = testMediaItem(
      id: 'local',
      kind: MediaKind.show,
      serverId: 'server',
      thumbPath: '/library-poster',
      isFavorite: true,
    );
    final updates = <List<MediaItem>>[];
    final subscription = resolveDetailRecommendations([rec(1)], match: (_) => gate.future).listen(updates.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(updates.single.single.isCatalogItem, isTrue);
    expect(RecommendationCardData.fromItem(updates.single.single)!.availability, RecommendationAvailability.checking);
    gate.complete(lookup(items: [original]));
    await subscription.asFuture<void>();
    final owned = updates.last.single;
    expect(owned.id, original.id);
    expect(owned.serverId, original.serverId);
    expect(owned.thumbPath, original.thumbPath);
    expect(owned.isFavorite, isTrue);
    expect(owned.isCatalogItem, isFalse);
    expect(RecommendationCardData.fromItem(owned)!.availability, RecommendationAvailability.owned);
    expect(() => jsonEncode(owned.raw), returnsNormally);
  });

  for (final result in [
    lookup(failed: {'offline'}),
    lookup(unqueried: {'offline'}),
    lookup(cancelled: {'cancelled'}),
    lookup(succeeded: {}),
  ]) {
    test('incomplete lookup never claims a title needs requesting: $result', () async {
      final rows = await resolveDetailRecommendations([rec(1)], match: (_) async => result).toList();
      expect(RecommendationCardData.fromItem(rows.last.single)!.availability, RecommendationAvailability.unknown);
    });
  }
  test('lookup error leaves a usable unknown catalog card', () async {
    final rows = await resolveDetailRecommendations([rec(1)], match: (_) async => throw StateError('offline')).toList();
    expect(RecommendationCardData.fromItem(rows.last.single)!.availability, RecommendationAvailability.unknown);
  });
  test('missing titles route to Seerr and keep the Simkl poster', () async {
    final seerr = _RequestSource(const CatalogServerState());
    final rows = await resolveDetailRecommendations([rec(1)], match: (_) async => lookup(), seerr: seerr).toList();
    final missing = rows.last.single;
    expect(missing.catalogItem!.source, CatalogSourceId.seerr);
    expect(missing.catalogItem!.ids.tmdb, 101);
    expect(missing.thumbPath, rec(1).posterUrl);
    expect(RecommendationCardData.fromItem(missing)!.availability, RecommendationAvailability.missing);
    expect(seerr.reads, 1);
  });
  test('active requests get Requested instead of Need request', () async {
    final seerr = _RequestSource(const CatalogServerState(request: CatalogRequestState.approved));
    final rows = await resolveDetailRecommendations([rec(1)], match: (_) async => lookup(), seerr: seerr).toList();
    expect(RecommendationCardData.fromItem(rows.last.single)!.availability, RecommendationAvailability.requested);
  });
  test('matching is bounded and stale navigation stops queued requests', () async {
    final gate = Completer<LibraryLookupResult>();
    var active = true;
    var reads = 0;
    final updates = <List<MediaItem>>[];
    final subscription = resolveDetailRecommendations(
      List.generate(30, rec),
      match: (_) {
        reads++;
        return gate.future;
      },
      isCurrent: () => active,
    ).listen(updates.add);
    addTearDown(subscription.cancel);
    await pumpEventQueue();
    expect(reads, 4);
    expect(updates.single, hasLength(30));
    active = false;
    gate.complete(lookup());
    await subscription.asFuture<void>();
    expect(reads, 4);
    expect(updates, hasLength(1));
  });
}
