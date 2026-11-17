import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/media_browser_dialect.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/smart_search/smart_search_client.dart';

import '../test_helpers/backend_client_fixtures.dart';
import '../test_helpers/http_fixtures.dart';

void main() {
  group('SmartSearchResponse', () {
    SmartSearchResponse response(List<Map<String, Object?>> results) => SmartSearchResponse.fromJson({
      'results': results,
      'understood': ['Shows', 'Sci-Fi'],
      'indexed_libraries': ['tv'],
    });

    test('keeps rank order and drops items whose every library is hidden', () {
      final r = response([
        {
          'id': 'a',
          'kind': 'Series',
          'title': 'A',
          'libraries': ['tv'],
        },
        {
          'id': 'b',
          'kind': 'Movie',
          'title': 'B',
          'libraries': ['movies'],
        },
        {
          'id': 'c',
          'kind': 'Movie',
          'title': 'C',
          'libraries': ['movies', 'kids'],
        },
      ]);
      expect(r.visibleIds({'movies'}), [(id: 'a', libraryId: 'tv'), (id: 'c', libraryId: 'kids')]);
      expect(r.understood, ['Shows', 'Sci-Fi']);
      expect(r.indexedLibraries, {'tv'});
    });

    test('includes other copies, keeps untagged items, never shows rejected ones', () {
      final r = response([
        {
          'id': 'heat-4k',
          'kind': 'Movie',
          'title': 'Heat',
          'libraries': ['uhd'],
          'copies': [
            {
              'id': 'heat-hd',
              'libraries': ['movies'],
            },
          ],
        },
        {'id': 'new', 'kind': 'Movie', 'title': 'Just added', 'libraries': []},
        {
          'id': 'wrong',
          'kind': 'Episode',
          'title': 'Wrong show',
          'libraries': ['tv'],
          'match': 'rejected',
        },
      ]);
      expect(r.visibleIds({'uhd'}), [(id: 'heat-hd', libraryId: 'movies'), (id: 'new', libraryId: null)]);
    });

    test('ignores malformed rows instead of failing the whole search', () {
      final r = SmartSearchResponse.fromJson({
        'results': [
          'nonsense',
          {'kind': 'Movie'},
          {'id': 'ok', 'kind': 'Movie', 'match': 'confirmed', 'recalled': true},
        ],
      });
      expect(r.results.single.id, 'ok');
      expect(r.results.single.match, SmartSearchMatch.confirmed);
      expect(r.results.single.recalled, isTrue);
    });
  });

  group('SmartSearchClient', () {
    test('uses the Jellyfin host on the service port, never for Emby', () {
      final uri = SmartSearchClient.endpointFor(testJellyfinConnection(baseUrl: 'http://10.0.0.5:8096/jellyfin'));
      expect(uri.toString(), 'http://10.0.0.5:8787');
      expect(SmartSearchClient.endpointFor(testJellyfinConnection(dialect: MediaBrowserDialect.emby)), isNull);
    });

    SmartSearchClient client(http.Response Function(http.Request request) handler, {List<Uri>? seen}) =>
        SmartSearchClient(
          httpClientFactory: () => MockClient((request) async {
            seen?.add(request.url);
            return handler(request);
          }),
        );

    test('is available only when the service indexes this exact server', () async {
      final connection = testJellyfinConnection(machineId: 'ABC-123');
      expect(await client((_) => jsonResponse({'ok': true, 'server_id': 'abc123'})).isAvailable(connection), isTrue);
      expect(await client((_) => jsonResponse({'ok': true, 'server_id': 'another'})).isAvailable(connection), isFalse);
      expect(await client((_) => http.Response('nope', 500)).isAvailable(connection), isFalse);
    });

    test('caches the probe and forgets it after a failed request', () async {
      final seen = <Uri>[];
      final connection = testJellyfinConnection(machineId: 'srv');
      final smart = client((_) => jsonResponse({'ok': true, 'server_id': 'srv'}), seen: seen);
      expect(await smart.isAvailable(connection), isTrue);
      expect(await smart.isAvailable(connection), isTrue);
      expect(seen.where((u) => u.path == '/v1/ping'), hasLength(1));
      smart.markUnavailable(connection);
      expect(await smart.isAvailable(connection), isFalse);
    });

    test("sends the user's own Jellyfin token and parses results", () async {
      late http.Request sent;
      final smart = SmartSearchClient(
        httpClientFactory: () => MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'id': 'x',
                  'kind': 'Series',
                  'title': 'Firefly',
                  'libraries': ['tv'],
                },
              ],
            }),
            200,
          );
        }),
      );
      final result = await smart.instant(testJellyfinConnection(accessToken: 'tok-1'), 'sci fi shows over 8');
      expect(sent.url.path, '/v1/search');
      expect(sent.url.queryParameters['q'], 'sci fi shows over 8');
      expect(sent.headers['Authorization'], 'MediaBrowser Token="tok-1"');
      expect(result.results.single.title, 'Firefly');
    });

    test('turns HTTP errors into SmartSearchUnavailable so callers can fall back', () async {
      final smart = client((_) => http.Response('denied', 401));
      expect(smart.instant(testJellyfinConnection(), 'x'), throwsA(isA<SmartSearchUnavailable>()));
    });
  });

  group('JellyfinClient.fetchItemsInOrder', () {
    late AppDatabase db;
    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      JellyfinApiCache.initialize(db);
    });
    tearDown(() => db.close());

    test('returns items in the requested order and omits ids Jellyfin did not return', () async {
      final captured = <Uri>[];
      final jellyfin = testJellyfinClient(
        httpClient: MockClient((request) async {
          captured.add(request.url);
          return jsonResponse({
            'Items': [
              {'Id': 'b', 'Type': 'Movie', 'Name': 'B'},
              {'Id': 'a', 'Type': 'Series', 'Name': 'A'},
            ],
          });
        }),
      );
      addTearDown(jellyfin.close);
      final items = await jellyfin.fetchItemsInOrder(['a', 'hidden', 'b']);
      expect(items.map((i) => i.id), ['a', 'b']);
      expect(captured.single.queryParameters['Ids'], 'a,hidden,b');
      expect(captured.single.queryParameters['userId'], isNotEmpty);
    });
  });
}
