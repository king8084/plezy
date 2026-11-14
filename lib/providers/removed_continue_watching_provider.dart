import '../profiles/profile.dart';
import '../media/media_item_types.dart';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../media/media_backend.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../mixins/disposable_change_notifier_mixin.dart';
import '../services/base_shared_preferences_service.dart';
import '../utils/watch_state_notifier.dart';

class RemovedContinueWatchingEntry {
  const RemovedContinueWatchingEntry(this.item, this.removedAt);
  final MediaItem item;
  final DateTime removedAt;
  String get key => item.globalKey;

  bool matches(MediaItem candidate) =>
      candidate.serverId == item.serverId &&
      (candidate.id == item.id || candidate.grandparentId == item.id || candidate.parentId == item.id);

  bool playedSinceRemoval(MediaItem candidate) =>
      matches(candidate) &&
      candidate.lastViewedAt != null &&
      candidate.lastViewedAt! * 1000 > removedAt.millisecondsSinceEpoch;

  Map<String, Object?> toJson() => {
    'id': item.id,
    'serverId': item.serverId,
    'backend': item.backend.name,
    'kind': item.kind.id,
    'title': item.title,
    'thumbPath': item.thumbPath,
    'removedAt': removedAt.millisecondsSinceEpoch,
  };

  static RemovedContinueWatchingEntry? fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final id = value['id'];
    final server = value['serverId'];
    final removedAt = value['removedAt'];
    if (id is! String || server is! String || removedAt is! int) return null;
    final backend = MediaBackend.values.where((backend) => backend.name == value['backend']).firstOrNull;
    if (backend == null) return null;
    return RemovedContinueWatchingEntry(
      MediaItem(
        id: id,
        serverId: server,
        backend: backend,
        kind: value['kind'] == 'show' ? MediaKind.show : MediaKind.movie,
        title: value['title'] is String ? value['title'] as String : null,
        thumbPath: value['thumbPath'] is String ? value['thumbPath'] as String : null,
      ),
      DateTime.fromMillisecondsSinceEpoch(removedAt),
    );
  }
}

/// Profile-local suppression of whole series (or movies), with an explicit
/// restore list. No server watch-state mutation and no resume-position loss.
class RemovedContinueWatchingProvider extends ChangeNotifier with DisposableChangeNotifierMixin {
  RemovedContinueWatchingProvider({required this.profileId, DateTime Function()? now}) : _now = now ?? DateTime.now {
    _ready = _load();
    _watchSubscription = WatchStateNotifier().stream.listen((event) {
      if (event.changeType != WatchStateChangeType.progressUpdate || (event.viewOffset ?? 0) <= 0) return;
      unawaited(
        _mutate(() {
          _entries.removeWhere(
            (_, entry) =>
                entry.item.serverId == event.serverId.value &&
                (entry.item.id == event.itemId || event.parentChain.contains(entry.item.id)),
          );
        }),
      );
    });
  }

  final String profileId;
  final DateTime Function() _now;
  final Map<String, RemovedContinueWatchingEntry> _entries = {};
  late final Future<void> _ready;
  late final SharedPreferencesWithCache _prefs;
  late final StreamSubscription<WatchStateEvent> _watchSubscription;
  Future<void> _writes = Future.value();
  String get _storageKey => profileScopedPrefsKey(profileId, 'removed_continue_watching');
  List<RemovedContinueWatchingEntry> get entries => List.unmodifiable(_entries.values.toList().reversed);
  bool _initialized = false;
  bool get isInitialized => _initialized;
  Future<void> ensureInitialized() => _ready;

  Future<void> _load() async {
    _prefs = await BaseSharedPreferencesService.sharedCache();
    for (final raw in _prefs.getStringList(_storageKey) ?? const <String>[]) {
      try {
        final entry = RemovedContinueWatchingEntry.fromJson(jsonDecode(raw));
        if (entry != null) _entries[entry.key] = entry;
      } on FormatException {
        /* A damaged entry must not prevent Home from loading. */
      }
    }
    _initialized = true;
    if (!isDisposed) safeNotifyListeners();
  }

  bool isHidden(MediaItem item) =>
      _entries.values.any((entry) => entry.matches(item) && !entry.playedSinceRemoval(item));
  List<MediaItem> filterItems(List<MediaItem> items) => items.where((item) => !isHidden(item)).toList();
  List<MediaHub> filterHubs(List<MediaHub> hubs) => [
    for (final hub in hubs)
      if (hub.isContinueWatchingHub || hub.usesContinueWatchingAction)
        hub.copyWith(items: filterItems(hub.items))
      else
        hub,
  ];

  Future<void> remove(MediaItem item) {
    if (item.serverId == null) return Future.value();
    final seriesId = item.isEpisode
        ? item.grandparentId
        : item.isSeason
        ? item.parentId
        : null;
    final target = seriesId == null
        ? item
        : MediaItem(
            id: seriesId,
            backend: item.backend,
            serverId: item.serverId,
            kind: MediaKind.show,
            title: item.isEpisode ? item.grandparentTitle ?? item.displayTitle : item.parentTitle ?? item.displayTitle,
            thumbPath: item.isEpisode ? item.grandparentThumbPath : item.parentThumbPath,
          );
    return _mutate(() {
      _entries[target.globalKey] = RemovedContinueWatchingEntry(target, _now());
    });
  }

  Future<void> restore(String key) => _mutate(() {
    _entries.remove(key);
  });
  Future<void> observeItems(List<MediaItem> items) => _mutate(() {
    _entries.removeWhere((_, entry) => items.any(entry.playedSinceRemoval));
  });

  Future<void> _mutate(void Function() change) {
    final result = _writes.then((_) async {
      await _ready;
      if (isDisposed) return;
      final before = jsonEncode([for (final entry in _entries.values) entry.toJson()]);
      final previous = Map.of(_entries);
      change();
      if (before == jsonEncode([for (final entry in _entries.values) entry.toJson()])) return;
      try {
        await _prefs.setStringList(_storageKey, [for (final entry in _entries.values) jsonEncode(entry.toJson())]);
      } catch (_) {
        _entries
          ..clear()
          ..addAll(previous);
        rethrow;
      }
      if (!isDisposed) safeNotifyListeners();
    });
    _writes = result.catchError((Object _) {});
    return result;
  }

  @override
  void dispose() {
    unawaited(_watchSubscription.cancel());
    super.dispose();
  }
}
