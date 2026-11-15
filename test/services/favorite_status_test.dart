import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/services/favorite_status.dart';

import '../test_helpers/media_items.dart';

class _Client implements MediaServerClient {
  @override
  final authenticationSessionId = Object();
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  final response = Completer<MediaItem?>();
  int fetches = 0;
  @override
  Future<MediaItem?> fetchItem(String id) {
    fetches++;
    return response.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final episode = testMediaItem(id: 'e', kind: MediaKind.episode, grandparentId: 'show');
  final show = testMediaItem(id: 'show', kind: MediaKind.show).copyWith(isFavorite: false);

  test('parent lookup coalesces and a concurrent successful write beats an old response', () async {
    final client = _Client();
    final status = FavoriteStatus.forClient(client);
    final first = status.resolve(client, episode);
    final second = status.resolve(client, episode);
    expect(client.fetches, 1);
    expect(status.cachedTarget(episode), isNull);
    status.confirm('show', true);
    client.response.complete(show);
    expect((await first)!.isFavorite, isTrue);
    expect((await second)!.isFavorite, isTrue);
    expect(status.cachedTarget(episode)!.isFavorite, isTrue);
    await status.resolve(client, episode);
    expect(client.fetches, 1);
  });

  test('favorite state is isolated between authenticated sessions on the same server', () {
    final alice = _Client();
    final bob = _Client();
    FavoriteStatus.forClient(alice).confirm('show', true);
    expect(FavoriteStatus.forClient(alice).value('show'), isTrue);
    expect(FavoriteStatus.forClient(bob).value('show'), isNull);
  });

  test('session cache stays bounded during long browsing sessions', () {
    final status = FavoriteStatus.forClient(_Client());
    for (var i = 0; i < 520; i++) {
      status.confirm('show-$i', true);
    }
    expect(status.value('show-0'), isNull);
    expect(status.value('show-519'), isTrue);
  });

  test('failed lookup stays unknown and does not fan out on every visible card', () async {
    final client = _Client();
    final status = FavoriteStatus.forClient(client);
    final pending = status.resolve(client, episode);
    client.response.completeError(StateError('offline'));
    expect(await pending, isNull);
    expect(status.value('show'), isNull);
    expect(await status.resolve(client, episode), isNull);
    expect(client.fetches, 1);
  });

  test('episode and season targets always resolve their series', () {
    expect(FavoriteStatus.targetId(episode), 'show');
    expect(FavoriteStatus.targetId(testMediaItem(id: 's8', kind: MediaKind.season, parentId: 'show')), 'show');
    expect(FavoriteStatus.targetId(testMediaItem(id: 'missing', kind: MediaKind.episode)), isNull);
  });
}
