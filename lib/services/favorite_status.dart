import 'dart:async';

import 'package:flutter/foundation.dart';

import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';

/// A small shared cache for the current authenticated client session. It never
/// persists credentials or state across profiles, and never blocks navigation.
class FavoriteStatus extends ChangeNotifier {
  FavoriteStatus({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static final _sessions = Expando<FavoriteStatus>();

  static FavoriteStatus forClient(MediaServerClient client) =>
      _sessions[client.authenticationSessionId] ??= FavoriteStatus();

  final _items = <String, MediaItem>{};
  final DateTime Function() _now;
  final _confirmed = <String, bool>{};
  final _confirmedAt = <String, DateTime>{};
  final _pending = <String, Future<MediaItem?>>{};
  final _versions = <String, int>{};
  final _readAt = <String, DateTime>{};
  static const _cacheLimit = 512;

  static String? targetId(MediaItem item) => item.isEpisode
      ? item.grandparentId
      : item.isSeason
      ? item.parentId
      : (item.isShow || item.isMovie ? item.id : null);

  bool? value(String id, {bool? fallback}) {
    final writtenAt = _confirmedAt[id];
    if (writtenAt != null && _now().difference(writtenAt) < const Duration(minutes: 2)) {
      return _confirmed[id];
    }
    return fallback ?? _items[id]?.isFavorite;
  }

  MediaItem? cachedTarget(MediaItem item) {
    final id = targetId(item);
    if (id == null) return null;
    final target = id == item.id ? item : _items[id];
    return target?.copyWith(isFavorite: value(id, fallback: target.isFavorite));
  }

  /// Called only after an acknowledged write; stale snapshots cannot undo it.
  void confirm(String id, bool favorite) {
    _versions[id] = (_versions[id] ?? 0) + 1;
    _confirmed[id] = favorite;
    _confirmedAt[id] = _now();
    if (_items[id] case final item?) _items[id] = item.copyWith(isFavorite: favorite);
    _trim();
    notifyListeners();
  }

  /// Parent lookup is shared by visible series posters and episode menus.
  /// Failures stay unknown rather than pretending a show isn't a favorite.
  Future<MediaItem?> resolve(MediaServerClient client, MediaItem item) {
    final id = targetId(item);
    if (id == null || !client.capabilities.userFavorites) return Future.value();
    final cached = cachedTarget(item);
    final freshness = cached == null ? const Duration(seconds: 5) : const Duration(minutes: 2);
    if (id == item.id || (_readAt[id] != null && _now().difference(_readAt[id]!) < freshness)) {
      return Future.value(cached);
    }
    return _pending[id] ??= _load(client, id);
  }

  Future<MediaItem?> _load(MediaServerClient client, String id) async {
    final version = _versions[id] ?? 0;
    try {
      final item = await client.fetchItem(id).timeout(const Duration(seconds: 5));
      if (item != null && item.id == id && (item.isShow || item.isMovie)) {
        _items[id] = (_versions[id] ?? 0) == version ? item : item.copyWith(isFavorite: _confirmed[id]);
        if ((_versions[id] ?? 0) == version) {
          _confirmed.remove(id);
          _confirmedAt.remove(id);
        }
        notifyListeners();
        return item.copyWith(isFavorite: value(id, fallback: item.isFavorite));
      }
      return null;
    } catch (_) {
      return _items[id];
    } finally {
      _readAt[id] = _now();
      _pending.removeWhere((key, _) => key == id);
      _trim();
    }
  }

  void _trim() {
    final keys = {..._readAt.keys, ..._confirmedAt.keys};
    if (keys.length <= _cacheLimit) return;
    final oldest = keys.where((id) => !_pending.containsKey(id)).toList()
      ..sort((a, b) => (_confirmedAt[a] ?? _readAt[a]!).compareTo(_confirmedAt[b] ?? _readAt[b]!));
    for (final id in oldest.take(keys.length - _cacheLimit)) {
      _items.remove(id);
      _confirmed.remove(id);
      _confirmedAt.remove(id);
      _readAt.remove(id);
      _versions.remove(id);
    }
  }
}
