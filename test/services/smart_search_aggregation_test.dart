import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/utils/external_ids.dart';
import 'package:plezy/media/search_hit.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/jellyfin_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/smart_search/smart_search_client.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';
import '../test_helpers/media_items.dart';

const _views = [
  {'Id': 'lib-movies', 'Name': 'Movies', 'CollectionType': 'movies', 'Type': 'CollectionFolder'},
  {'Id': 'lib-tv', 'Name': 'TV Shows', 'CollectionType': 'tvshows', 'Type': 'CollectionFolder'},
  {'Id': 'lib-music', 'Name': 'Music', 'CollectionType': 'music', 'Type': 'CollectionFolder'},
];

const _rows = {
  'watched-film': {
    'Id': 'watched-film',
    'Type': 'Movie',
    'Name': 'Already Seen',
    'UserData': {'Played': true, 'PlayCount': 1},
  },
  'dark': {'Id': 'dark', 'Type': 'Series', 'Name': 'Dark'},
  'firefly': {'Id': 'firefly', 'Type': 'Series', 'Name': 'Firefly'},
  'kids-movie': {'Id': 'kids-movie', 'Type': 'Movie', 'Name': 'Kids Space Movie'},
  'half-film': {
    'Id': 'half-film',
    'Type': 'Movie',
    'Name': 'Half Seen',
    'RunTimeTicks': 72000000000,
    'UserData': {'Played': false, 'PlaybackPositionTicks': 6000000000},
  },
};

void main() {
  late AppDatabase db;
  late MultiServerManager manager;
  late List<Uri> jellyfinRequests;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    JellyfinApiCache.initialize(db);
    manager = MultiServerManager();
    jellyfinRequests = [];
  });

  tearDown(() => db.close());

  JellyfinClient jellyfin() {
    final client = testJellyfinClient(
      httpClient: MockClient((request) async {
        jellyfinRequests.add(request.url);
        final q = request.url.queryParameters;
        if (request.url.path.endsWith('/Views')) return jsonResponse({'Items': _views});
        if (request.url.path.endsWith('/Items/last-played/Similar')) {
          return jsonResponse({
            'Items': [_rows['dark'], _rows['firefly']],
          });
        }
        if (request.url.path.endsWith('/Items/last-played')) {
          return jsonResponse({
            'Id': 'last-played',
            'Type': 'Movie',
            'Name': 'Last Played',
            'ProviderIds': {'Imdb': 'tt-last'},
          });
        }
        if (request.url.path == '/Items' && q['SortBy'] == 'DatePlayed') {
          return jsonResponse({
            'Items': [
              {
                'Id': 'last-played',
                'Type': 'Movie',
                'Name': 'Last Played',
                'UserData': {'Played': true, 'PlayCount': 1, 'LastPlayedDate': '2026-11-16T20:00:00Z'},
              },
            ],
          });
        }
        if (request.url.path == '/Items' && q['Ids'] != null) {
          return jsonResponse({
            'Items': [
              for (final id in q['Ids']!.split(','))
                if (_rows[id] != null) _rows[id],
            ],
          });
        }
        if (request.url.path == '/Items' && q['ParentId'] == 'lib-music' && q['IncludeItemTypes'] == 'MusicAlbum') {
          return jsonResponse({
            'Items': [
              {'Id': 'album', 'Type': 'MusicAlbum', 'Name': 'Sci Fi Shows Soundtracks'},
            ],
          });
        }
        if (request.url.path == '/Items' && q['ParentId'] != null && q['ParentId'] != 'lib-music') {
          return jsonResponse({
            'Items': [
              {'Id': 'server-title-hit', 'Type': 'Movie', 'Name': 'Sci Fi Shows Over 8 (server search)'},
            ],
          });
        }
        return jsonResponse({'Items': <Object>[]});
      }),
    );
    addTearDown(client.close);
    return client;
  }

  SmartSearchClient smart({bool failSearch = false}) => SmartSearchClient(
    httpClientFactory: () => MockClient((request) async {
      if (request.url.path == '/v1/ping') return jsonResponse({'ok': true, 'server_id': 'srv-1'});
      if (failSearch) return http.Response('boom', 500);
      return jsonResponse({
        'results': [
          // Index order on purpose: not alphabetical, not title-relevance order.
          {
            'id': 'firefly',
            'kind': 'Series',
            'title': 'Firefly',
            'libraries': ['lib-tv'],
          },
          {
            'id': 'dark',
            'kind': 'Series',
            'title': 'Dark',
            'libraries': ['lib-tv'],
          },
          {
            'id': 'kids-movie',
            'kind': 'Movie',
            'title': 'Kids Space Movie',
            'libraries': ['lib-movies'],
          },
        ],
        'indexed_libraries': ['lib-movies', 'lib-tv'],
      });
    }),
  );

  List<String> titleIds(SearchAggregationResult result) => [
    for (final hit in result.hits)
      if (hit is MediaSearchHit) hit.item.id,
  ];

  test("smart titles keep the index's order and the server still searches music", () async {
    final client = jellyfin();
    manager.debugRegisterClientForTesting(client);
    final service = DataAggregationService(manager, smartSearch: smart());

    final result = await service.searchAcrossServers('sci fi shows over 8');

    expect(titleIds(result), ['firefly', 'dark', 'kids-movie', 'album']);
    final searchedLibraries = {
      for (final uri in jellyfinRequests)
        if (uri.path == '/Items' && uri.queryParameters['SearchTerm'] != null) uri.queryParameters['ParentId'],
    };
    expect(searchedLibraries, {'lib-music'}, reason: 'indexed libraries are not searched twice');
  });

  test('a hidden library drops its smart results', () async {
    final client = jellyfin();
    manager.debugRegisterClientForTesting(client);
    final service = DataAggregationService(manager, smartSearch: smart());

    final result = await service.searchAcrossServers(
      'sci fi shows over 8',
      hiddenLibraryKeys: {'${client.serverId}:lib-movies'},
    );

    expect(titleIds(result), isNot(contains('kids-movie')));
    expect(titleIds(result).take(2), ['firefly', 'dark']);
  });

  test('a failing index falls back to ordinary server search', () async {
    final client = jellyfin();
    manager.debugRegisterClientForTesting(client);
    final service = DataAggregationService(manager, smartSearch: smart(failSearch: true));

    final result = await service.searchAcrossServers('sci fi shows over 8');

    expect(titleIds(result), contains('server-title-hit'));
    expect(titleIds(result), isNot(contains('firefly')));
  });

  test('smart suggestions load items for this user with their match labels', () async {
    final client = jellyfin();
    manager.debugRegisterClientForTesting(client);
    final service = DataAggregationService(
      manager,
      smartSearch: SmartSearchClient(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path == '/v1/ping') return jsonResponse({'ok': true, 'server_id': 'srv-1'});
          return jsonResponse({
            'results': [
              {
                'id': 'dark',
                'kind': 'Series',
                'title': 'Dark',
                'libraries': ['lib-tv'],
                'match': 'confirmed',
              },
              {
                'id': 'gone',
                'kind': 'Series',
                'title': 'Not visible to this user',
                'libraries': ['lib-tv'],
              },
              {
                'id': 'firefly',
                'kind': 'Series',
                'libraries': ['lib-tv'],
                'match': 'possible',
                'recalled': true,
              },
            ],
          });
        }),
      ),
    );

    final suggestions = await service.smartSuggestions('a show about time travel in a german town');

    expect(suggestions.map((s) => (s.item.id, s.match, s.recalled)), [
      ('dark', SmartSearchMatch.confirmed, false),
      ('firefly', SmartSearchMatch.possible, true),
    ]);
    expect(suggestions.first.item.libraryId, 'lib-tv');
  });

  test('an unwatched request drops what this profile has already watched', () async {
    final client = jellyfin();
    manager.debugRegisterClientForTesting(client);
    final service = DataAggregationService(
      manager,
      smartSearch: SmartSearchClient(
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path == '/v1/ping') return jsonResponse({'ok': true, 'server_id': 'srv-1'});
          return jsonResponse({
            'unwatched': true,
            'results': [
              {
                'id': 'watched-film',
                'kind': 'Movie',
                'title': 'Already Seen',
                'libraries': ['lib-movies'],
              },
              {
                'id': 'kids-movie',
                'kind': 'Movie',
                'title': 'Kids Space Movie',
                'libraries': ['lib-movies'],
              },
            ],
            'indexed_libraries': ['lib-movies', 'lib-tv'],
          });
        }),
      ),
    );

    final result = await service.searchAcrossServers('sci fi movies i have not watched');

    expect(titleIds(result), contains('kids-movie'));
    expect(titleIds(result), isNot(contains('watched-film')));
  });

  test('without an index nothing changes', () async {
    final client = jellyfin();
    manager.debugRegisterClientForTesting(client);
    final service = DataAggregationService(manager);

    final result = await service.searchAcrossServers('sci fi shows over 8');

    expect(titleIds(result), contains('server-title-hit'));
    expect(await service.smartSuggestions('anything'), isEmpty);
  });

  group('smart Home rows', () {
    final similarRequests = <Uri>[];
    final resolveRequests = <Uri>[];
    final smartRequests = <Uri>[];
    SmartSearchClient homeSmart() => SmartSearchClient(
      httpClientFactory: () => MockClient((request) async {
        final path = request.url.path;
        if (path == '/v1/ping') return jsonResponse({'ok': true, 'server_id': 'srv-1'});
        if (path == '/v1/top') {
          return jsonResponse({
            'results': [
              {
                'id': 'watched-film',
                'kind': 'Movie',
                'title': 'Already Seen',
                'libraries': ['lib-movies'],
              },
              {
                'id': 'dark',
                'kind': 'Series',
                'title': 'Dark',
                'libraries': ['lib-tv'],
              },
              {
                'id': 'half-film',
                'kind': 'Movie',
                'title': 'Half Seen',
                'libraries': ['lib-movies'],
              },
              {
                'id': 'kids-movie',
                'kind': 'Movie',
                'title': 'Kids Space Movie',
                'libraries': ['lib-movies'],
              },
            ],
          });
        }
        if (path == '/v1/smart') {
          smartRequests.add(request.url);
          return jsonResponse({
            'results': [
              {'id': 'firefly', 'kind': 'Episode', 'title': 'Firefly', 'match': 'possible'},
              {'id': 'dark', 'kind': 'Episode', 'title': 'Dark', 'match': 'rejected'},
              {'id': 'kids-movie', 'kind': 'Episode', 'title': 'Kids', 'match': 'confirmed'},
            ],
          });
        }
        if (path == '/v1/resolve') {
          resolveRequests.add(request.url);
          const known = {'show:imdb:tt-dark': 'dark', 'movie:imdb:tt-kids': 'kids-movie'};
          final ids = <String>[];
          for (final ref in request.url.queryParameters['refs']!.split(',')) {
            final id = ref.startsWith('item:') ? ref.substring(5) : known[ref];
            if (id != null && !ids.contains(id)) ids.add(id);
          }
          return jsonResponse({
            'results': [
              for (final id in ids)
                {
                  'id': id,
                  'kind': 'Movie',
                  'title': id,
                  'libraries': [if (id == 'kids-movie') 'lib-movies' else 'lib-tv'],
                },
            ],
          });
        }
        if (path == '/v1/similar') {
          similarRequests.add(request.url);
          return jsonResponse({
            'source': {'id': 'last-played', 'kind': 'Movie', 'title': 'Last Played'},
            'results': [
              {
                'id': 'firefly',
                'kind': 'Series',
                'title': 'Firefly',
                'libraries': ['lib-tv'],
              },
              {
                'id': 'watched-film',
                'kind': 'Movie',
                'title': 'Already Seen',
                'libraries': ['lib-movies'],
              },
            ],
          });
        }
        return http.Response('not found', 404);
      }),
    );

    setUp(() {
      similarRequests.clear();
      resolveRequests.clear();
      smartRequests.clear();
    });

    test('top rated and because-you-watched rows drop watched titles', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: homeSmart());

      final hubs = await service.smartHomeHubs();

      expect([for (final hub in hubs) hub.id], [smartTopRatedHubId, smartBecauseWatchedHubId]);
      expect([for (final item in hubs[0].items) item.id], ['dark', 'kids-movie']);
      expect(hubs[1].title, contains('Last Played'));
      expect([for (final item in hubs[1].items) item.id], ['firefly', 'dark']);
      expect(similarRequests.single.queryParameters['id'], 'last-played');
      expect(hubs.every((hub) => hub.serverId == '${client.serverId}'), isTrue);
    });

    test('a hidden library is left out of the rows', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: homeSmart());

      final hubs = await service.smartHomeHubs(hiddenLibraryKeys: {'${client.serverId}:lib-tv'});

      expect([for (final item in hubs.single.items) item.id], ['kids-movie']);
    });

    test('because-you-watched blends index, Jellyfin, Simkl and Trakt by agreement', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: homeSmart());
      MediaKind? askedKind;
      ExternalIds? askedIds;

      final hubs = await service.smartHomeHubs(
        externalRecommendations: (kind, ids) async {
          askedKind = kind;
          askedIds = ids;
          return [
            [
              const CatalogItem(
                source: CatalogSourceId.simkl,
                kind: MediaKind.movie,
                title: 'Kids Space Movie',
                ids: CatalogItemIds(imdb: 'tt-kids'),
              ),
              const CatalogItem(
                source: CatalogSourceId.simkl,
                kind: MediaKind.movie,
                title: 'Not In Library',
                ids: CatalogItemIds(imdb: 'tt-missing', tmdb: 42),
              ),
            ],
            [
              const CatalogItem(
                source: CatalogSourceId.trakt,
                kind: MediaKind.show,
                title: 'Dark',
                ids: CatalogItemIds(imdb: 'tt-dark'),
              ),
            ],
          ];
        },
      );

      final because = hubs.firstWhere((hub) => hub.id == smartBecauseWatchedHubId);
      // dark: Jellyfin #1 + Trakt #1; firefly: index #1 + Jellyfin #2;
      // kids-movie: Simkl only; watched-film: watched, dropped.
      expect([for (final item in because.items) item.id], ['dark', 'firefly', 'kids-movie']);
      expect(askedKind, MediaKind.movie);
      expect(askedIds?.imdb, 'tt-last');
      expect(resolveRequests.every((uri) => uri.queryParameters['seed'] == 'last-played'), isTrue);
      expect(
        resolveRequests.map((uri) => uri.queryParameters['refs']),
        containsAll(['item:dark,item:firefly', 'movie:imdb:tt-kids,movie:imdb:tt-missing,movie:tmdb:42']),
      );
    });

    test('partly watched titles are left out', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: homeSmart());

      final hubs = await service.smartHomeHubs();

      expect(hubs.first.items.map((item) => item.id), isNot(contains('half-film')));
      expect(hubs.first.items.map((item) => item.id), contains('kids-movie'));
    });

    test('blend favours agreement, then each source\'s own order', () {
      expect(
        DataAggregationService.blendRecommendations([
          ['a', 'b', 'c'],
          ['c', 'd'],
          ['b'],
        ]),
        ['b', 'c', 'a', 'd'],
      );
      expect(DataAggregationService.blendRecommendations([]), isEmpty);
    });

    test('find in show searches that show only and drops rejected matches', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: homeSmart());
      final show = testMediaItem(
        id: 'modern-family',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.show,
        title: 'Modern Family',
        serverId: '${client.serverId}',
      );

      final found = await service.findInShow(show, ' phil basketball ', recall: true);

      expect([for (final s in found) s.item.id], ['firefly', 'kids-movie']);
      expect(found.last.match, SmartSearchMatch.confirmed);
      final q = smartRequests.single.queryParameters;
      expect((q['q'], q['series'], q['recall']), ('phil basketball', 'modern-family', '1'));
      expect(await service.smartSearchAvailableOn('${client.serverId}'), isTrue);
      expect(await service.smartSearchAvailableOn('elsewhere'), isFalse);
    });

    test('no index means no rows', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: smart(failSearch: true));
      final unreachable = SmartSearchClient(httpClientFactory: () => MockClient((_) async => http.Response('', 404)));

      expect(await DataAggregationService(manager, smartSearch: unreachable).smartHomeHubs(), isEmpty);
      expect(await service.smartHomeHubs(), isEmpty);
    });
  });
}
