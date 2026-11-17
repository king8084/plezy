import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/utils/formatters.dart';
import 'package:plezy/utils/media_runtime_label.dart';

import '../test_helpers/media_items.dart';

void main() {
  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  final episode = testMediaItem(kind: MediaKind.episode, durationMs: 21 * 60000);

  test('partly watched episode shows the remaining minutes', () {
    expect(mediaRuntimeLabel(episode.copyWith(viewOffsetMs: 7 * 60000)), '14 min left');
  });

  test('movie remaining time includes hours', () {
    final movie = testMediaItem(durationMs: 120 * 60000, viewOffsetMs: 48 * 60000);
    expect(mediaRuntimeLabel(movie), '${formatDurationTextual(72 * 60000)} left');
  });

  for (final offset in [null, 0, -1, 21 * 60000, 22 * 60000]) {
    test('missing, unstarted or completed progress keeps total runtime: $offset', () {
      expect(mediaRuntimeLabel(episode.copyWith(viewOffsetMs: offset)), formatDurationTextual(21 * 60000));
    });
  }

  test('remaining time rounds upward and never prematurely shows zero', () {
    expect(mediaRuntimeLabel(episode.copyWith(viewOffsetMs: 7 * 60000 - 1)), '15 min left');
    expect(mediaRuntimeLabel(episode.copyWith(viewOffsetMs: 21 * 60000 - 1)), '1 min left');
  });

  test('rewatching a previously watched title still shows active progress', () {
    expect(mediaRuntimeLabel(episode.copyWith(viewCount: 1, viewOffsetMs: 7 * 60000)), '14 min left');
  });

  test('series metadata keeps its nominal runtime even if given an offset', () {
    expect(
      mediaRuntimeLabel(episode.copyWith(kind: MediaKind.show, viewOffsetMs: 7 * 60000)),
      formatDurationTextual(21 * 60000),
    );
  });

  test('unknown duration does not invent a remaining time', () {
    expect(mediaRuntimeLabel(episode.copyWith(durationMs: null, viewOffsetMs: 7 * 60000)), isNull);
  });
}
