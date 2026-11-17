import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/services/sidebar_library_items.dart';

import '../test_helpers/media_items.dart';

class _Client implements MediaServerClient {
  _Client(this.backend, this.serverId);
  @override
  final MediaBackend backend;
  @override
  final ServerId serverId;
  @override
  ServerCapabilities get capabilities =>
      backend == MediaBackend.plex ? ServerCapabilities.plex : ServerCapabilities.jellyfin;
  @override
  Object authenticationSessionId = Object();
  final queries = <LibraryQuery>[];
  final collections = <String>[];
  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    dynamic abort,
  }) async {
    queries.add(query);
    expect(libraryKind, MediaKind.show);
    expect(query.filters.single.field, 'favorite');
    expect(query.filters.single.values, ['1']);
    return LibraryPage(
      items: [testMediaItem(id: '${query.offset}', kind: MediaKind.show, title: 'Favorite', serverId: serverId.value)],
      totalCount: 2,
      offset: query.offset,
    );
  }

  @override
  Future<LibraryPage<MediaItem>> fetchCollectionsPage(String libraryId, {int? start, int? size, dynamic abort}) async {
    collections.add(libraryId);
    return LibraryPage(
      items: [testMediaItem(id: libraryId, kind: MediaKind.collection, serverId: serverId.value)],
      totalCount: 1,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibrary _library(_Client client, String id) =>
    MediaLibrary(id: id, backend: client.backend, title: id, kind: MediaKind.show, serverId: client.serverId.value);

void main() {
  test('favorites are filtered and paged, and unsupported backends are never queried', () async {
    final jellyfin = _Client(MediaBackend.jellyfin, ServerId('jf'));
    final plex = _Client(MediaBackend.plex, ServerId('plex'));
    final items = await fetchSidebarLibraryItems(
      favorites: true,
      sources: [
        (library: _library(jellyfin, 'shows'), client: jellyfin),
        (library: _library(plex, 'plex-shows'), client: plex),
      ],
    );
    expect(items.map((item) => item.id), ['0', '1']);
    expect(jellyfin.queries.map((query) => query.offset), [0, 1]);
    expect(plex.queries, isEmpty);
  });

  test('collections read one Jellyfin server root but every Plex library', () async {
    final jellyfin = _Client(MediaBackend.jellyfin, ServerId('jf'));
    final plex = _Client(MediaBackend.plex, ServerId('plex'));
    final items = await fetchSidebarLibraryItems(
      favorites: false,
      sources: [
        for (final client in [jellyfin, plex])
          for (final id in ['a', 'b']) (library: _library(client, id), client: client),
      ],
    );
    expect(jellyfin.collections, ['a']);
    expect(plex.collections, ['a', 'b']);
    expect(items.map((item) => item.globalKey).toSet(), hasLength(3));
  });
}
