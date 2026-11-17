import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';

import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/media_navigation_helper.dart';
import '../test_helpers/media_items.dart';

void main() {
  test('hardware Play ignores both card activation preferences', () {
    expect(
      shouldOpenEpisodeDetailsForActivation(
        playDirectly: true,
        forcePlayback: true,
        continueWatchingAction: ContinueWatchingAction.details,
        episodeAction: EpisodeAction.details,
      ),
      isFalse,
    );
  });

  test('hardware Play keeps episode startup free of extra server lookups', () async {
    final client = _PlaybackClient();
    final episode = testMediaItem(kind: MediaKind.episode);
    expect(await resolveDirectPlaybackItem(client, episode), same(episode));
    expect(client.lookups, 0);
  });

  test('hardware Play on a show resumes its On Deck episode on the same server', () async {
    final client = _PlaybackClient()..onDeck = testMediaItem(id: 'resume', kind: MediaKind.episode);
    final show = testMediaItem(id: 'show', kind: MediaKind.show, serverId: 'server-1');
    final target = await resolveDirectPlaybackItem(client, show);
    expect(target?.id, 'resume');
    expect(target?.serverId, 'server-1');
    expect(client.lookups, 1);
  });

  test('hardware Play on a season selects its first unwatched episode in order', () async {
    final client = _PlaybackClient()
      ..episodes = [
        testMediaItem(id: 'three', kind: MediaKind.episode, parentIndex: 1, index: 3),
        testMediaItem(id: 'one', kind: MediaKind.episode, parentIndex: 1, index: 1, viewCount: 1),
        testMediaItem(id: 'two', kind: MediaKind.episode, parentIndex: 1, index: 2),
      ];
    final season = testMediaItem(id: 'season', kind: MediaKind.season, serverId: 'server-1');
    expect((await resolveDirectPlaybackItem(client, season))?.id, 'two');
  });

  test('hardware Play handles an empty show without launching its container', () async {
    expect(await resolveDirectPlaybackItem(_PlaybackClient(), testMediaItem(kind: MediaKind.show)), isNull);
  });

  test('episode detail target opens parent show and focuses season episode', () {
    final episode = testMediaItem(
      id: 'episode-1',
      backend: MediaBackend.plex,
      kind: MediaKind.episode,
      title: 'Episode 1',
      parentId: 'season-2',
      parentIndex: 2,
      grandparentId: 'show-1',
      grandparentTitle: 'The Show',
      serverId: 'server-1',
    );

    final target = mediaDetailNavigationTargetFor(episode);

    expect(target.metadata.id, 'show-1');
    expect(target.metadata.kind, MediaKind.show);
    expect(target.initialSeasonId, 'season-2');
    expect(target.initialSeasonIndex, 2);
    expect(target.initialEpisodeId, 'episode-1');
  });

  test('season detail target opens parent show and focuses season', () {
    final season = testMediaItem(
      id: 'season-3',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 3',
      index: 3,
      parentId: 'show-1',
      parentTitle: 'The Show',
      serverId: 'server-1',
    );

    final target = mediaDetailNavigationTargetFor(season);

    expect(target.metadata.id, 'show-1');
    expect(target.metadata.kind, MediaKind.show);
    expect(target.initialSeasonId, 'season-3');
    expect(target.initialSeasonIndex, 3);
    expect(target.initialEpisodeId, isNull);
  });

  test('movie detail target keeps the movie itself', () {
    final movie = testMediaItem(id: 'movie-1', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Movie');

    final target = mediaDetailNavigationTargetFor(movie);

    expect(target.metadata, same(movie));
    expect(target.initialSeasonId, isNull);
    expect(target.initialEpisodeId, isNull);
  });

  group('episode activation details decision', () {
    test('normal activation uses the episode action setting', () {
      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: false,
          continueWatchingAction: ContinueWatchingAction.details,
          episodeAction: EpisodeAction.play,
        ),
        isFalse,
      );

      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: false,
          continueWatchingAction: ContinueWatchingAction.play,
          episodeAction: EpisodeAction.details,
        ),
        isTrue,
      );
    });

    test('play-direct activation uses only the continue watching action setting', () {
      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: true,
          continueWatchingAction: ContinueWatchingAction.play,
          episodeAction: EpisodeAction.details,
        ),
        isFalse,
      );

      expect(
        shouldOpenEpisodeDetailsForActivation(
          playDirectly: true,
          continueWatchingAction: ContinueWatchingAction.details,
          episodeAction: EpisodeAction.play,
        ),
        isTrue,
      );
    });
  });
}

class _PlaybackClient implements MediaServerClient {
  MediaItem? onDeck;
  List<MediaItem> episodes = [];
  int lookups = 0;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async {
    lookups++;
    return (item: null, onDeckEpisode: onDeck);
  }

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    lookups++;
    return episodes;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
