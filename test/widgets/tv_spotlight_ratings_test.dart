import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/tv_spotlight_background.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';

import '../test_helpers/prefs.dart';

/// The TV dashboard spotlight (Discover, Explore, and the library recommended
/// tab all render through [TvSpotlightBackground]) shows every score the hub
/// listing already returned. Listings carry the scalar rating pair, so this is
/// normally one or two entries — never a reason to re-fetch an item.
Future<void> _pumpSpotlight(
  WidgetTester tester,
  MediaItem item, {
  double textScale = 1,
  Size canvas = const Size(1920, 1080),
  double contentTop = 80,
  double contentBottom = 200,
  MediaItem? ratingsFallback,
  MediaItem? technicalItem,
  bool hideSpoilers = false,
}) async {
  await SettingsService.getInstance();
  tester.view.physicalSize = canvas;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        home: Scaffold(
          // TvSpotlightScaffold fills the screen with the background; a loose
          // Scaffold body would leave its bottom-anchored info block unbounded.
          body: SizedBox.expand(
            child: TvSpotlightBackground(
              item: item,
              hideSpoilers: hideSpoilers,
              ratingsFallback: ratingsFallback,
              technicalItem: technicalItem,
              client: null,
              allowNetwork: false,
              compact: true,
              textScale: textScale,
              contentTop: contentTop,
              contentBottom: contentBottom,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('tight Home header keeps the normal logo size', (tester) async {
    final episode = MediaItem.jellyfin(
      id: 'episode',
      kind: MediaKind.episode,
      title: 'Basketball',
      grandparentTitle: 'Modern Family',
      parentIndex: 8,
      index: 16,
      summary: List.filled(20, 'Phil trains for a charity basketball game.').join(' '),
    );
    await _pumpSpotlight(tester, episode, contentBottom: 760);
    final summary = find.byKey(const ValueKey('tv_spotlight_summary'));
    expect(tester.widget<Text>(summary).maxLines, 1);
    expect(tester.getBottomLeft(summary).dy, lessThanOrEqualTo(320));
    expect(tester.getSize(find.byKey(const ValueKey('tv_spotlight_logo_slot'))).height, 96);
    expect(tester.takeException(), isNull);
  });

  for (final canvas in [const Size(1280, 720), const Size(1920, 1080)]) {
    for (final density in [6, 7]) {
      testWidgets('Home keeps its normal logo and readable synopsis with poster size $density at $canvas', (
        tester,
      ) async {
        final settings = await SettingsService.getInstance();
        await settings.write(SettingsService.libraryDensity, density);
        await settings.write(SettingsService.episodePosterMode, EpisodePosterMode.seriesPoster);
        tester.view.physicalSize = canvas;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final episode = MediaItem.jellyfin(
          id: 'episode',
          kind: MediaKind.episode,
          title: 'Basketball',
          grandparentTitle: 'Modern Family',
          parentIndex: 8,
          index: 16,
          summary: List.filled(20, 'Phil trains for a charity basketball game.').join(' '),
        );
        final hubs = [
          MediaHub(id: 'continue', title: 'Continue Watching', type: 'show', items: [episode]),
        ];
        final railHeight = TvBrowseRailLayout.estimateHeight(
          size: canvas,
          hubs: hubs,
          density: density,
          episodePosterMode: settings.read(SettingsService.episodePosterMode),
          tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
          widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
          showNextHubPeek: false,
        );
        final spotlight = ValueNotifier<MediaItem?>(episode);
        addTearDown(spotlight.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: TvSpotlightScaffold(
              showNextHubPeek: false,
              hubs: hubs,
              spotlightListenable: spotlight,
              resolveSpotlight: () => episode,
              resolveClient: (_) => null,
              foreground: Align(
                alignment: Alignment.bottomCenter,
                child: SizedBox(key: const ValueKey('home_rail_bounds'), height: railHeight, width: double.infinity),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final summary = find.byKey(const ValueKey('tv_spotlight_summary'));
        expect(tester.getSize(summary).width, greaterThan(canvas.width * 0.9));
        expect(tester.widget<Text>(summary).style!.shadows, isNotEmpty);
        expect(tester.widget<Text>(summary).maxLines, greaterThanOrEqualTo(density == 6 ? 3 : 2));
        expect(
          tester.getSize(find.byKey(const ValueKey('tv_spotlight_logo_slot'))).height,
          closeTo(96 * (canvas.height / 1080).clamp(0.85, 1.35), 0.01),
        );
        final rail = find.byKey(const ValueKey('home_rail_bounds'));
        expect(tester.getBottomLeft(summary).dy, lessThan(tester.getTopLeft(rail).dy));
        expect(tester.getBottomRight(rail).dy, lessThanOrEqualTo(canvas.height));
        expect(tester.takeException(), isNull);
      });
    }
  }

  for (final canvas in [const Size(1280, 720), const Size(1920, 1080)]) {
    testWidgets('episode title has its own line above number and long titles ellipsize at $canvas', (tester) async {
      final title = List.filled(12, 'A very long episode title').join(' ');
      final episode = MediaItem.jellyfin(
        id: 'ep',
        kind: MediaKind.episode,
        title: title,
        grandparentTitle: 'Modern Family',
        parentIndex: 8,
        index: 19,
        rating: 7.2,
        durationMs: 1260000,
        originallyAvailableAt: '2017-03-01',
      );
      await _pumpSpotlight(tester, episode, canvas: canvas);
      final titleFinder = find.byKey(const ValueKey('tv_spotlight_episode_title'));
      expect(tester.widget<Text>(titleFinder).overflow, TextOverflow.ellipsis);
      expect(tester.renderObject<RenderParagraph>(titleFinder).didExceedMaxLines, isTrue);
      expect(tester.getBottomLeft(titleFinder).dy, lessThan(tester.getTopLeft(find.text('S8 E19')).dy));
      expect(find.text('7.2'), findsOneWidget);
      expect(tester.getBottomRight(find.text('7.2')).dx, lessThan(canvas.width));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('spoiler-hidden episode title appears once above metadata', (tester) async {
    const episode = MediaItem.jellyfin(
      id: 'ep',
      kind: MediaKind.episode,
      title: 'Heavy Is the Head',
      grandparentTitle: 'Modern Family',
      parentIndex: 8,
      index: 14,
      summary: 'Hidden episode synopsis',
    );
    await _pumpSpotlight(tester, episode, hideSpoilers: true);
    expect(find.text('Heavy Is the Head'), findsOneWidget);
    expect(find.text('Hidden episode synopsis'), findsNothing);
  });

  testWidgets('episode spotlight keeps its score without title-level Rotten Tomatoes', (tester) async {
    const episode = MediaItem.jellyfin(
      id: 'ep',
      kind: MediaKind.episode,
      title: 'Episode',
      ratings: [
        MediaRatingSource(source: 'audience', value: 7.2),
        MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.1),
      ],
    );
    const show = MediaItem.jellyfin(
      id: 'show',
      kind: MediaKind.show,
      title: 'Show',
      genres: ['Comedy'],
      ratings: [
        MediaRatingSource(source: 'imdb', value: 8.5),
        MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.3),
        MediaRatingSource(source: 'rottenTomatoesAudience', value: 9.4),
      ],
    );
    await _pumpSpotlight(tester, episode, ratingsFallback: show);
    expect(find.text('7.2'), findsOneWidget);
    for (final value in ['91%', '93%', '94%', '8.5']) {
      expect(find.text(value), findsNothing);
    }
    await _pumpSpotlight(tester, show);
    expect(find.text('93%'), findsOneWidget);
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('8.5'), findsOneWidget);
  });

  testWidgets('episode file tags never borrow the parent series video format', (tester) async {
    const episode = MediaItem.jellyfin(id: 'episode', kind: MediaKind.episode, title: 'Episode');
    const parent = MediaItem.jellyfin(
      id: 'series',
      kind: MediaKind.show,
      title: 'Show',
      mediaVersions: [MediaVersion(id: 'wrong', videoResolution: '4k', videoCodec: 'hevc')],
    );
    await _pumpSpotlight(tester, episode, ratingsFallback: parent, technicalItem: parent);
    expect(find.text('4K'), findsNothing);
    expect(find.text('HEVC'), findsNothing);

    final detail = episode.copyWith(
      mediaVersions: [const MediaVersion(id: 'right', videoResolution: '1080', videoCodec: 'h264')],
    );
    await _pumpSpotlight(tester, episode, ratingsFallback: parent, technicalItem: detail);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('H.264'), findsOneWidget);
    expect(find.text('4K'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('larger Home text scales descriptions and rating icons without overflow', (tester) async {
    const item = MediaItem.jellyfin(
      id: 'scaled',
      kind: MediaKind.movie,
      title: 'Title',
      summary: 'Episode synopsis',
      rating: 8.3,
      ratings: [MediaRatingSource(source: 'audience', value: 8.3)],
      mediaVersions: [
        MediaVersion(
          id: '4k',
          bitrate: 12000,
          videoResolution: '4k',
          videoCodec: 'hevc',
          parts: [
            MediaPart(
              id: 'part',
              sizeBytes: 5261334938,
              streams: [
                MediaStream(id: 'video', kind: MediaStreamKind.video, dolbyVision: true),
                MediaStream(id: 'audio1', kind: MediaStreamKind.audio, codec: 'aac', channels: 2),
                MediaStream(id: 'audio2', kind: MediaStreamKind.audio, codec: 'eac3', channels: 6, selected: true),
              ],
            ),
          ],
        ),
      ],
    );
    await _pumpSpotlight(tester, item);
    final normal = tester.widget<Text>(find.text('Episode synopsis')).style!.fontSize!;
    await _pumpSpotlight(tester, item, textScale: 1.5);
    expect(tester.widget<Text>(find.text('Episode synopsis')).style!.fontSize, normal * 1.5);
    expect(tester.widget<Text>(find.text('Episode synopsis')).maxLines, 3);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('HEVC'), findsOneWidget);
    expect(find.text('Dolby Vision'), findsOneWidget);
    expect(find.text('AAC Stereo'), findsOneWidget);
    expect(find.text('4.90GB | 12.0Mbps'), findsOneWidget);
    expect(find.text('EAC3 5.1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('full focused-file metadata supplies size and bitrate missing from a cached row', (tester) async {
    const episode = MediaItem.jellyfin(
      id: 'cached-episode',
      kind: MediaKind.episode,
      title: 'Episode',
      mediaVersions: [MediaVersion(id: 'file', videoResolution: '1080', videoCodec: 'hevc')],
    );
    final detail = episode.copyWith(
      mediaVersions: [
        const MediaVersion(
          id: 'file',
          videoResolution: '1080',
          videoCodec: 'hevc',
          bitrate: 5000,
          parts: [MediaPart(id: 'part', sizeBytes: 830 * 1024 * 1024)],
        ),
      ],
    );
    await _pumpSpotlight(tester, episode, technicalItem: detail);
    expect(find.text('830MB | 5.0Mbps'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spotlight text rows keep the same baseline and size across synopsis lengths', (tester) async {
    const short = MediaItem.jellyfin(
      id: 'short',
      kind: MediaKind.movie,
      title: 'Short title',
      summary: 'Short synopsis.',
      year: 2024,
    );
    final long = short.copyWith(
      id: 'long',
      title: 'A longer show title',
      summary: List.filled(12, 'A longer synopsis uses more available horizontal space.').join(' '),
    );
    await _pumpSpotlight(tester, short);
    final metadata = find.byKey(const ValueKey('tv_spotlight_metadata'));
    final summary = find.byKey(const ValueKey('tv_spotlight_summary'));
    final initialMetadataTop = tester.getTopLeft(metadata);
    final initialSummaryTop = tester.getTopLeft(summary);
    final initialFont = tester.widget<Text>(summary).style!.fontSize;
    await _pumpSpotlight(tester, long);
    expect(tester.getTopLeft(metadata), initialMetadataTop);
    expect(tester.getTopLeft(summary), initialSummaryTop);
    expect(tester.widget<Text>(summary).style!.fontSize, initialFont);
    expect(tester.getSize(summary).width, greaterThan(1920 * 0.65));
    expect(tester.takeException(), isNull);
  });

  testWidgets('maximum Home text size stays inside the short spotlight band on a 960x540 TV', (tester) async {
    const item = MediaItem.jellyfin(
      id: 'tight',
      kind: MediaKind.movie,
      title: 'A long title on the small TV canvas',
      summary: 'A long description that still has to stay above the posters, with the largest text size.',
      year: 2024,
    );
    await _pumpSpotlight(
      tester,
      item,
      textScale: 1.5,
      canvas: const Size(960, 540),
      contentTop: 54,
      contentBottom: 400,
    );
    expect(tester.getBottomLeft(find.byKey(const ValueKey('tv_spotlight_summary'))).dy, lessThanOrEqualTo(140.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard spotlight badges every rating the listing carried', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.plex(
        id: 'movie_1',
        kind: MediaKind.movie,
        title: 'Spotlight Movie',
        rating: 9.2,
        ratings: [
          MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.2),
          MediaRatingSource(source: 'rottenTomatoesAudience', value: 8.5),
        ],
      ),
    );

    expect(find.text('92%'), findsOneWidget);
    expect(find.text('85%'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNWidgets(2));
  });

  testWidgets('dashboard spotlight still shows one badge for a single-score listing', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.jellyfin(
        id: 'movie_2',
        kind: MediaKind.movie,
        title: 'Community Only',
        rating: 8.3,
        ratings: [MediaRatingSource(source: 'audience', value: 8.3)],
      ),
    );

    // No brand logo exists for an unattributed community score, so it keeps
    // the generic icon and the neutral 0-10 rendering.
    expect(find.text('8.3'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('dashboard spotlight omits the rating slot when the item has no score', (tester) async {
    await _pumpSpotlight(
      tester,
      const MediaItem.plex(id: 'movie_3', kind: MediaKind.movie, title: 'Unrated', year: 2024),
    );

    expect(find.text('2024'), findsOneWidget);
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('dashboard spotlight announces each rating with its source name', (tester) async {
    final semantics = tester.ensureSemantics();

    await _pumpSpotlight(
      tester,
      const MediaItem.plex(
        id: 'movie_4',
        kind: MediaKind.movie,
        title: 'Announced Movie',
        ratings: [
          MediaRatingSource(source: 'rottenTomatoesCritic', value: 9.2),
          MediaRatingSource(source: 'imdb', value: 7.4),
        ],
      ),
    );

    // Without the group's own label a reader would hear "92%, 7.4" with no
    // way to tell which score belongs to which source.
    expect(
      find.bySemanticsLabel('${t.common.ratingSource.imdb} 7.4, ${t.common.ratingSource.rottenTomatoesCritic} 92%'),
      findsOneWidget,
    );
    semantics.dispose();
  });
}
