import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/widgets/optimized_media_image.dart';
import 'package:plezy/widgets/media_rating_badge.dart';
import 'package:plezy/services/jellyfin_mappers.dart';
import 'package:plezy/watch_together/providers/watch_together_provider.dart';
import 'package:plezy/widgets/video_controls/widgets/video_controls_header.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    LocaleSettings.setLocaleSync(AppLocale.en);
    await initializeDateFormatting('en');
  });

  testWidgets('title-less mapped movie builds with localized fallback in both layouts', (tester) async {
    final item = _mappedItem({'Id': 'movie-without-name', 'Type': 'Movie'});

    for (final style in VideoHeaderStyle.values) {
      await _pumpHeader(tester, metadata: item, style: style);

      expect(find.text(t.common.unknown), findsOneWidget, reason: style.name);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('title-less mapped episode keeps series identity and uses fallback in both layouts', (tester) async {
    final item = _mappedItem({
      'Id': 'episode-without-name',
      'Type': 'Episode',
      'SeriesName': 'Mapped Series',
      'ParentIndexNumber': 2,
      'IndexNumber': 3,
    });

    for (final style in VideoHeaderStyle.values) {
      await _pumpHeader(tester, metadata: item, style: style);

      final expectedEpisodeLine = switch (style) {
        VideoHeaderStyle.singleLine => 'Mapped Series · S2E3 · ${t.common.unknown}',
        VideoHeaderStyle.multiLine => 'S2 · E3 · ${t.common.unknown}',
      };
      expect(find.text(expectedEpisodeLine), findsOneWidget, reason: style.name);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('ordinary mapped episode wording remains unchanged in both layouts', (tester) async {
    final item = _mappedItem({
      'Id': 'titled-episode',
      'Type': 'Episode',
      'Name': 'The Arrival',
      'SeriesName': 'Mapped Series',
      'ParentIndexNumber': 1,
      'IndexNumber': 4,
    });

    for (final style in VideoHeaderStyle.values) {
      await _pumpHeader(tester, metadata: item, style: style);

      final expectedEpisodeLine = switch (style) {
        VideoHeaderStyle.singleLine => 'Mapped Series · S1E4 · The Arrival',
        VideoHeaderStyle.multiLine => 'S1 · E4 · The Arrival',
      };
      expect(find.text(expectedEpisodeLine), findsOneWidget, reason: style.name);
      expect(find.text(t.common.unknown), findsNothing, reason: style.name);
    }
  });
  testWidgets('TV header uses the show logo and only the playing episode score', (tester) async {
    final episode =
        _mappedItem({
          'Id': 'episode-14',
          'Type': 'Episode',
          'Name': 'Heavy Is the Head',
          'SeriesName': 'Modern Family',
          'ParentIndexNumber': 8,
          'IndexNumber': 14,
          'ParentLogoItemId': 'series',
          'ParentLogoImageTag': 'logo',
        }).copyWith(
          ratings: const [
            MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.2),
            MediaRatingSource(source: 'tmdb', value: 8.1),
            MediaRatingSource(source: 'imdb', value: 7.2),
          ],
        );
    await _pumpHeader(tester, metadata: episode, style: VideoHeaderStyle.multiLine, useTvArtwork: true);

    expect(find.byType(ClearLogoImage), findsOneWidget);
    expect(tester.widget<ClearLogoImage>(find.byType(ClearLogoImage)).logoPath, episode.clearLogoPath);
    final badge = tester.widget<InlineRatingBadges>(find.byType(InlineRatingBadges));
    expect(badge.goldStars, isTrue);
    expect(badge.ratings.single.source, 'imdb');
    expect(find.text('7.2'), findsOneWidget);
    expect(find.text('9.2'), findsNothing);
    expect(find.text('8.1'), findsNothing);
    expect(find.text('S8 · E14 · '), findsOneWidget);
  });

  testWidgets('TV header keeps title fallback and does not substitute other provider scores', (tester) async {
    final episode = _mappedItem({
      'Id': 'episode-15',
      'Type': 'Episode',
      'Name': 'Episode title',
      'SeriesName': 'Modern Family',
      'ParentIndexNumber': 8,
      'IndexNumber': 15,
    }).copyWith(ratings: const [MediaRatingSource(source: 'tmdb', value: 8.1)]);
    await _pumpHeader(tester, metadata: episode, style: VideoHeaderStyle.multiLine, useTvArtwork: true);
    expect(find.text('Modern Family'), findsOneWidget);
    expect(find.byType(InlineRatingBadges), findsNothing);
    expect(find.text('S8 · E15 · Episode title'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TV header uses Jellyfin episode headline score just as Home does', (tester) async {
    final episode = _mappedItem({
      'Id': 'episode-14',
      'Type': 'Episode',
      'Name': 'Heavy Is the Head',
      'SeriesName': 'Modern Family',
      'ParentIndexNumber': 8,
      'IndexNumber': 14,
      'CommunityRating': 7.2,
      'CriticRating': 92,
    });
    await _pumpHeader(tester, metadata: episode, style: VideoHeaderStyle.multiLine, useTvArtwork: true);
    final badge = tester.widget<InlineRatingBadges>(find.byType(InlineRatingBadges));
    expect(badge.ratings.single.value, 7.2);
    expect(badge.goldStars, isTrue);
    expect(find.text('92%'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

MediaItem _mappedItem(Map<String, dynamic> json) {
  return JellyfinMappers.mediaItem(
    json,
    serverId: ServerId('header-test-server'),
    serverName: 'Test Server',
    absolutizer: null,
  )!;
}

Future<void> _pumpHeader(
  WidgetTester tester, {
  required MediaItem metadata,
  required VideoHeaderStyle style,
  bool useTvArtwork = false,
}) async {
  final watchTogether = WatchTogetherProvider();
  addTearDown(watchTogether.dispose);

  await tester.pumpWidget(
    TranslationProvider(
      child: ChangeNotifierProvider<WatchTogetherProvider>.value(
        value: watchTogether,
        child: MaterialApp(
          home: Scaffold(
            backgroundColor: Colors.black,
            body: SizedBox(
              width: 900,
              child: VideoControlsHeader(metadata: metadata, style: style, useTvArtwork: useTvArtwork, onBack: () {}),
            ),
          ),
        ),
      ),
    ),
  );
}
