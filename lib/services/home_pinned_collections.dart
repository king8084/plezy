import '../media/ids.dart';
import '../media/media_hub.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import 'settings_service.dart';

const int pinnedHomeCollectionPreviewLimit = 20;
const String _pinSeparator = '\u001f';

String homePinnedCollectionKey(String serverId, String collectionId) => '$serverId$_pinSeparator$collectionId';

({String serverId, String collectionId})? parseHomePinnedCollectionKey(String key) {
  final separator = key.indexOf(_pinSeparator);
  if (separator <= 0 || separator == key.length - 1) return null;
  return (serverId: key.substring(0, separator), collectionId: key.substring(separator + 1));
}

/// Build local home rows from saved collection ids. Like Wholphin's collection
/// rows, each row is just a query for the collection's children; the server
/// does not need a special home-screen plugin.
Future<List<MediaHub>> fetchPinnedHomeCollectionHubs({
  required SettingsService settings,
  required Set<String> serverIds,
  required MediaServerClient? Function(ServerId serverId) clientForServer,
}) async {
  Future<MediaHub?> fetchHub(String key) async {
    final pin = parseHomePinnedCollectionKey(key);
    if (pin == null || !serverIds.contains(pin.serverId)) return null;
    final client = clientForServer(ServerId(pin.serverId));
    if (client == null) return null;

    try {
      final collection = await client.fetchItem(pin.collectionId);
      if (collection == null || collection.kind != MediaKind.collection) return null;
      final page = await client.fetchCollectionPage(
        pin.collectionId,
        size: pinnedHomeCollectionPreviewLimit,
        libraryId: collection.libraryId,
        libraryTitle: collection.libraryTitle,
      );
      if (page.items.isEmpty) return null;
      return MediaHub(
        id: 'pinned-collection:${pin.serverId}:${pin.collectionId}',
        identifier: 'pinned_collection',
        title: collection.displayTitle,
        type: 'collection',
        items: [
          for (final item in page.items)
            item.serverId == null ? item.copyWith(serverId: pin.serverId, serverName: collection.serverName) : item,
        ],
        size: page.totalCount,
        more: page.totalCount > page.items.length,
        libraryId: collection.libraryId,
        serverId: pin.serverId,
        serverName: collection.serverName,
      );
    } catch (error, stackTrace) {
      appLogger.w('Failed to load pinned home collection ${pin.collectionId}', error: error, stackTrace: stackTrace);
      return null;
    }
  }

  final pins = settings.read(SettingsService.homePinnedCollections);
  final hubs = await Future.wait(pins.map(fetchHub));
  return hubs.whereType<MediaHub>().toList(growable: false);
}
