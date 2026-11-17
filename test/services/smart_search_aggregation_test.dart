import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/search_hit.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/jellyfin_client.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/smart_search/smart_search_client.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';

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
                'id': 'kids-movie',
                'kind': 'Movie',
                'title': 'Kids Space Movie',
                'libraries': ['lib-movies'],
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

    setUp(similarRequests.clear);

    test('top rated and because-you-watched rows drop watched titles', () async {
      final client = jellyfin();
      manager.debugRegisterClientForTesting(client);
      final service = DataAggregationService(manager, smartSearch: homeSmart());

      final hubs = await service.smartHomeHubs();

      expect([for (final hub in hubs) hub.id], [smartTopRatedHubId, smartBecauseWatchedHubId]);
      expect([for (final item in hubs[0].items) item.id], ['dark', 'kids-movie']);
      expect(hubs[1].title, contains('Last Played'));
      expect([for (final item in hubs[1].items) item.id], ['firefly']);
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
