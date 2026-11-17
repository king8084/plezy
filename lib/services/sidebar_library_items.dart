import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_filter.dart';
import '../media/media_item.dart';
import '../media/media_library.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';

/// Loads the sidebar shortcuts from the active profile's visible libraries.
/// Jellyfin collections share a server-wide root; Plex collections are scoped
/// to each library. Favorites are queried only on backends that support them.
Future<List<MediaItem>> fetchSidebarLibraryItems({
  required bool favorites,
  required List<({MediaLibrary library, MediaServerClient client})> sources,
}) async {
  final seenRoots = <String>{};
  final items = <String, MediaItem>{};
  Object? failure;
  var succeeded = false;
  for (final source in sources) {
    final (:library, :client) = source;
    if (favorites && !client.capabilities.userFavorites) continue;
    final root = !favorites && client.backend != MediaBackend.plex ? '${client.serverId}' : library.globalKey;
    if (!seenRoots.add(root)) continue;
    final session = client.authenticationSessionId;
    try {
      final pageItems = await drainPages<MediaItem>((start, size) async {
        if (!identical(session, client.authenticationSessionId)) throw StateError('Retired library session');
        final page = favorites
            ? await client.fetchLibraryPagedContent(
                library.id,
                libraryKind: library.kind,
                query: LibraryQuery(
                  includeKinds: library.defaultBrowseKinds,
                  offset: start,
                  limit: size,
                  filters: const [
                    LibraryFilter(field: MediaFilterField.favorite, values: ['1']),
                  ],
                ),
              )
            : await client.fetchCollectionsPage(library.id, start: start, size: size);
        if (!identical(session, client.authenticationSessionId)) throw StateError('Retired library session');
        return page;
      }, pageSize: 100);
      for (final item in pageItems) {
        items[item.globalKey] = item;
      }
      succeeded = true;
    } catch (error) {
      failure = error;
      appLogger.d('Sidebar library shortcut load failed', error: error);
    }
  }
  if (!succeeded && failure != null) throw failure;
  return items.values.toList()..sort((a, b) => a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()));
}
