import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/offline_watch_provider.dart';
import '../utils/provider_extensions.dart';
import '../utils/watch_state_notifier.dart';
import 'trackers/tracker_coordinator.dart';

enum WatchMarkOutcome {
  /// Queued for later sync (offline). The offline provider emitted the event.
  queuedOffline,

  /// Marked on the server; event emitted, trackers fired.
  marked,

  /// Nothing to do (no server id / no bound client).
  skipped,
}

/// Orchestrates watched/unwatched marks: routes offline marks to the offline
/// queue, online marks to the backend client, emits the single
/// [WatchStateNotifier] event, and fires trackers. UI surfaces call this
/// instead of hand-rolling the offline/online + tracker dance; snackbars and
/// refresh callbacks stay with the caller. Client `markWatched`/`markUnwatched`
/// are transport-only — they must never be called directly from UI code.
class WatchActions {
  WatchActions._();

  /// Marks [item] watched/unwatched. [offline] overrides the
  /// [OfflineModeProvider] read for callers that already know (e.g. screens
  /// rendering downloaded content).
  static Future<WatchMarkOutcome> setWatched(
    BuildContext context,
    MediaItem item, {
    required bool watched,
    bool? offline,
  }) async {
    final isOffline = offline ?? context.read<OfflineModeProvider>().isOffline;
    final serverId = item.serverId;

    if (isOffline && serverId != null) {
      final offlineWatch = context.read<OfflineWatchProvider>();
      if (watched) {
        await offlineWatch.markAsWatched(serverId: ServerId(serverId), itemId: item.id);
      } else {
        await offlineWatch.markAsUnwatched(serverId: ServerId(serverId), itemId: item.id);
      }
      return WatchMarkOutcome.queuedOffline;
    }

    if (serverId == null) return WatchMarkOutcome.skipped;
    final client = context.tryGetMediaClientForServer(ServerId(serverId));
    if (client == null) return WatchMarkOutcome.skipped;

    if (watched) {
      await client.markWatched(item);
    } else {
      await client.markUnwatched(item);
    }
    WatchStateNotifier().notifyWatched(
      item: item,
      isNowWatched: watched,
      cacheServerId: client.cacheServerId,
      serverAcknowledged: true,
    );
    unawaited(
      watched
          ? TrackerCoordinator.instance.markWatched(item, client)
          : TrackerCoordinator.instance.markUnwatched(item, client),
    );
    return WatchMarkOutcome.marked;
  }

  /// Marks every episode before [episode] in its show as watched, earlier
  /// seasons included (specials are left alone). For "background" shows the
  /// viewer skims until something catches their eye. Returns how many were
  /// marked; already-watched episodes are skipped. Throws when the show's
  /// episodes cannot be listed.
  static Future<int> markPreviousEpisodesWatched(BuildContext context, MediaItem episode) async {
    final serverId = episode.serverId;
    final seriesId = episode.grandparentId;
    final season = episode.parentIndex;
    final number = episode.index;
    if (serverId == null || seriesId == null || season == null || number == null) return 0;
    final client = context.tryGetMediaClientForServer(ServerId(serverId));
    if (client == null) return 0;
    final episodes = await client.fetchClientSideEpisodeQueue(seriesId);
    if (episodes == null) throw StateError('episodes unavailable');
    final earlier = previousEpisodes(episodes, season: season, number: number);
    var marked = 0;
    for (final item in earlier) {
      if (!context.mounted) break;
      final outcome = await setWatched(context, item, watched: true, offline: false);
      if (outcome == WatchMarkOutcome.marked) marked++;
    }
    return marked;
  }

  /// The unwatched episodes that come before S[season]E[number]: every
  /// earlier regular season, plus this season's earlier episodes.
  @visibleForTesting
  static List<MediaItem> previousEpisodes(List<MediaItem> episodes, {required int season, required int number}) => [
    for (final item in episodes)
      if (item.isEpisode &&
          !item.isWatched &&
          (item.parentIndex ?? 0) > 0 &&
          item.index != null &&
          ((item.parentIndex! < season) || (item.parentIndex == season && item.index! < number)))
        item,
  ];

  /// Removes [item] from Continue Watching without touching watch state.
  /// Throws when no client is bound for the item's server (mirrors the
  /// pre-existing menu behaviour so callers surface an error snackbar).
  static Future<void> removeFromContinueWatching(BuildContext context, MediaItem item) async {
    final client = context.getMediaClientForServer(ServerId(item.serverId!));
    await client.removeFromContinueWatching(item);
    WatchStateNotifier().notifyRemovedFromContinueWatching(item: item);
  }
}
