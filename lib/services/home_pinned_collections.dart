import 'dart:convert';

import '../media/ids.dart';
import '../media/media_item.dart';
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
  final metadata = readPinnedHomeCollectionMetadata(settings);
  final updatedMetadata = <String, Map<String, dynamic>>{};
  Future<MediaHub?> fetchHub(String key) async {
    final pin = parseHomePinnedCollectionKey(key);
    if (pin == null || !serverIds.contains(pin.serverId)) return null;
    final client = clientForServer(ServerId(pin.serverId));
    if (client == null) return null;

    try {
      final cacheKey = '${client.cacheServerId}$_pinSeparator$key';
      final cached = metadata[cacheKey];
      final storedAt = cached?['cachedAt'] as int?;
      final fresh =
          storedAt != null &&
          DateTime.now().millisecondsSinceEpoch - storedAt < const Duration(hours: 24).inMilliseconds;
      MediaItem? cachedCollection;
      if (fresh) {
        try {
          final item = MediaItem.fromJson(cached!['item'] as Map<String, dynamic>);
          if (item.id == pin.collectionId && item.kind == MediaKind.collection) cachedCollection = item;
        } catch (_) {
          // Optimization data must never make a healthy pin disappear.
        }
      }
      final collection = cachedCollection ?? await client.fetchItem(pin.collectionId);
      if (collection == null || collection.kind != MediaKind.collection) return null;
      if (cachedCollection == null) {
        updatedMetadata[cacheKey] = pinnedHomeCollectionMetadata(collection, key)..['cacheKey'] = cacheKey;
      }
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
  if (updatedMetadata.isNotEmpty) {
    // Merge after the parallel requests so one pin cannot overwrite another.
    try {
      final current = readPinnedHomeCollectionMetadata(settings)..addAll(updatedMetadata);
      final savedPins = settings.read(SettingsService.homePinnedCollections).toSet();
      current.removeWhere((_, data) => !savedPins.contains(data['pinKey']));
      await settings.write(SettingsService.homePinnedCollectionMetadata, current.values.map(jsonEncode).toList());
    } catch (error) {
      appLogger.d('Pinned collection metadata cache write failed', error: error);
    }
  }
  return hubs.whereType<MediaHub>().toList(growable: false);
}

/// Cached titles are only a refresh optimization. Saved pins remain independently
/// visible in Settings even when their server or collection is unavailable.
Map<String, Map<String, dynamic>> readPinnedHomeCollectionMetadata(SettingsService settings) {
  final result = <String, Map<String, dynamic>>{};
  for (final raw in settings.read(SettingsService.homePinnedCollectionMetadata)) {
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final key = data['cacheKey'] as String;
      if (data['item'] is Map<String, dynamic> && data['cachedAt'] is int) result[key] = data;
    } catch (_) {
      // Ignore damaged optimization data; the pin ids are stored separately.
    }
  }
  return result;
}

Map<String, dynamic> pinnedHomeCollectionMetadata(MediaItem collection, String pinKey) => {
  'pinKey': pinKey,
  'cachedAt': DateTime.now().millisecondsSinceEpoch,
  'item': {
    'backend': collection.toJson()['backend'],
    'dialect': ?collection.toJson()['dialect'],
    'id': collection.id,
    'kind': MediaKind.collection.name,
    'title': collection.displayTitle,
    'libraryId': collection.libraryId,
    'libraryTitle': collection.libraryTitle,
    'serverId': collection.serverId,
    'serverName': collection.serverName,
  },
};

/// Preserve the name at pin time, even if the first Home refresh fails. Mark it
/// stale so the next successful fetch still completes its library metadata.
Future<void> rememberPinnedHomeCollection({
  required SettingsService settings,
  required MediaServerClient client,
  required MediaItem collection,
}) async {
  final pinKey = homePinnedCollectionKey(client.serverId.value, collection.id);
  final cacheKey = '${client.cacheServerId}$_pinSeparator$pinKey';
  final metadata = readPinnedHomeCollectionMetadata(settings);
  metadata[cacheKey] = pinnedHomeCollectionMetadata(collection, pinKey)
    ..['cacheKey'] = cacheKey
    ..['cachedAt'] = 0;
  await settings.write(SettingsService.homePinnedCollectionMetadata, metadata.values.map(jsonEncode).toList());
}
