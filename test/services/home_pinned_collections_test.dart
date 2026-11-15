import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/home_pinned_collections.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

class _Client implements MediaServerClient, ScopedMediaServerClient {
  _Client(this.scopedServerId, this.title);
  @override
  final String scopedServerId;
  final String title;
  int titleReads = 0;
  int pageReads = 0;
  bool missing = false;
  @override
  ServerId get serverId => ServerId('server');
  @override
  Future<MediaItem?> fetchItem(String id) async {
    titleReads++;
    return missing
        ? null
        : testMediaItem(
            id: id,
            backend: MediaBackend.jellyfin,
            kind: MediaKind.collection,
            title: title,
            serverId: 'server',
            libraryId: 'library',
          );
  }

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String id, {
    int? start,
    int? size,
    dynamic abort,
    String? libraryId,
    String? libraryTitle,
  }) async {
    pageReads++;
    expect(libraryId, 'library');
    return LibraryPage(
      items: [testMediaItem(id: 'movie', kind: MediaKind.movie)],
      totalCount: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  test('refresh reuses title metadata and isolates it by user scope', () async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.homePinnedCollections, [homePinnedCollectionKey('server', 'collection')]);
    final alice = _Client('server/alice', 'Alice collection');
    Future<List<String>> load(_Client client) async => (await fetchPinnedHomeCollectionHubs(
      settings: settings,
      serverIds: {'server'},
      clientForServer: (_) => client,
    )).map((hub) => hub.title).toList();
    expect(await load(alice), ['Alice collection']);
    expect(await load(alice), ['Alice collection']);
    expect(alice.titleReads, 1);
    expect(alice.pageReads, 2);
    final bob = _Client('server/bob', 'Bob collection');
    expect(await load(bob), ['Bob collection']);
    expect(bob.titleReads, 1);
  });

  test('missing collection stays saved and corrupt optimization data falls back to the server', () async {
    final settings = await SettingsService.getInstance();
    final key = homePinnedCollectionKey('server', 'gone');
    await settings.write(SettingsService.homePinnedCollections, [key]);
    await settings.write(SettingsService.homePinnedCollectionMetadata, ['broken']);
    final client = _Client('server/alice', 'Collection')..missing = true;
    expect(
      await fetchPinnedHomeCollectionHubs(settings: settings, serverIds: {'server'}, clientForServer: (_) => client),
      isEmpty,
    );
    expect(settings.read(SettingsService.homePinnedCollections), [key]);
    client.missing = false;
    expect(
      await fetchPinnedHomeCollectionHubs(settings: settings, serverIds: {'server'}, clientForServer: (_) => client),
      hasLength(1),
    );
  });
}
