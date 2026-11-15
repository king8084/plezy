import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:plezy/utils/layout_constants.dart';
import 'package:plezy/widgets/fitted_metadata_line.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:plezy/focus/locked_hub_controller.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/media/media_part.dart';
import 'package:plezy/media/media_stream.dart';
import 'package:plezy/media/media_version.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/multi_server_fixtures.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('SpotlightTestFont')..addFont(rootBundle.load('assets/go-noto-current-regular.ttf'));
    await loader.load();
  });
  for (final canvas in [const Size(960, 540), const Size(1280, 720), const Size(1920, 1080)]) {
    for (final density in [1, 2, 3, 4, 5, 6, 7]) {
      for (final labelScale in [1.0, 1.5]) {
        for (final isShow in [false, true]) {
          testWidgets(
            'Home keeps normal headers and smaller synopsis at $canvas, poster $density, labels $labelScale, show $isShow',
            (tester) async {
              resetSharedPreferencesForTest();
              SettingsService.resetForTesting();
              TvDetectionService.debugSetAppleTVOverride(true);
              addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
              LocaleSettings.setLocaleSync(AppLocale.en);
              final settings = await SettingsService.getInstance();
              await settings.write(SettingsService.libraryDensity, density);
              await settings.write(SettingsService.episodePosterMode, EpisodePosterMode.seriesPoster);
              tester.view.physicalSize = canvas;
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.reset);
              const episode = MediaItem.jellyfin(
                id: 'dexter',
                kind: MediaKind.episode,
                title: 'Fallen',
                grandparentTitle: 'Dexter: Resurrection',
                parentIndex: 2,
                index: 2,
                rating: 8.7,
                ratings: [MediaRatingSource(source: 'imdb', value: 8.7)],
                durationMs: 3480000,
                viewOffsetMs: 44 * 60000,
                originallyAvailableAt: '2026-11-08',
                genres: ['Crime', 'Drama'],
                contentRating: 'TV-MA',
                summary:
                    "After choking at last year's charity basketball game, Phil has been training all year to redeem himself. However, when NBA stars Charles Barkley and DeAndre Jordan attend the game and start making bets, Phil tries to not buckle under the pressure. Meanwhile, Gloria has to step-up at Manny's school when his nemesis, Donna Duncan, tries to shame her for her lack of involvement.",
                mediaVersions: [
                  MediaVersion(
                    id: 'source',
                    videoResolution: '4k',
                    videoCodec: 'hevc',
                    bitrate: 12000,
                    parts: [
                      MediaPart(
                        id: 'part',
                        sizeBytes: 5261334938,
                        streams: [
                          MediaStream(id: 'video', kind: MediaStreamKind.video, dolbyVision: true),
                          MediaStream(
                            id: 'audio',
                            kind: MediaStreamKind.audio,
                            codec: 'eac3',
                            channels: 6,
                            displayTitle: 'EAC3 Atmos',
                            selected: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              );
              final item = isShow
                  ? episode.copyWith(
                      kind: MediaKind.show,
                      title: 'MobLand',
                      grandparentTitle: 'MobLand',
                      mediaVersions: const [],
                    )
                  : episode;
              final items = [
                for (final title in [
                  'Detective Conan',
                  'The Rainmaker',
                  'Dexter: Resurrection',
                  'Hannibal',
                  'Black Clover',
                ])
                  item.copyWith(id: title, grandparentTitle: title),
              ];
              final hub = MediaHub(id: 'continue_watching', title: 'Continue Watching', type: 'show', items: items);
              final controller = ValueNotifier<MediaItem?>(item);
              addTearDown(controller.dispose);
              final theme = monoTheme(
                MonoPalette.dark,
              ).copyWith(textTheme: monoTheme(MonoPalette.dark).textTheme.apply(fontFamily: 'SpotlightTestFont'));
              await tester.pumpWidget(
                ChangeNotifierProvider<MultiServerProvider>.value(
                  value: testMultiServer(clients: []).provider,
                  child: MaterialApp(
                    theme: theme,
                    home: RepaintBoundary(
                      key: const ValueKey('capture'),
                      child: TvSpotlightScaffold(
                        hubs: [hub],
                        spotlightListenable: controller,
                        resolveSpotlight: () => item,
                        resolveClient: (_) => null,
                        textScale: labelScale,
                        showNextHubPeek: false,
                        foreground: Align(
                          alignment: Alignment.bottomCenter,
                          child: TvBrowseRail(
                            hubs: [hub],
                            focusMemory: HubFocusMemory(),
                            iconForHub: (_, _) => Icons.play_circle,
                            showNextHubPeek: false,
                            tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                            widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.pumpAndSettle();
              expect(tester.widget<Text>(find.byKey(const ValueKey('tv_spotlight_summary'))).maxLines, 3);
              expect(tester.takeException(), isNull);
              final summary = find.byKey(const ValueKey('tv_spotlight_summary'));
              expect(tester.getBottomLeft(summary).dy, lessThan(tester.getTopLeft(find.byType(TvBrowseRail)).dy));
              final summaryStyle = tester.widget<Text>(summary).style!;
              expect(tester.renderObject<RenderParagraph>(summary).didExceedMaxLines, isFalse);
              expect(
                tester.getSize(summary).height,
                greaterThanOrEqualTo(summaryStyle.fontSize! * summaryStyle.height! * 3 - 0.01),
              );
              final scale = TvLayoutConstants.scaleForSize(canvas);
              final metadataStyle = tester.widget<FittedMetadataLine>(find.byType(FittedMetadataLine)).textStyle;
              expect(metadataStyle.fontSize, closeTo(18 * scale * labelScale, 0.001));
              if (isShow) {
                expect(find.byKey(const ValueKey('tv_spotlight_episode_title')), findsNothing);
                expect(find.byKey(const ValueKey('tv_spotlight_technical_badges')), findsNothing);
              } else {
                final episodeTitleStyle = tester
                    .widget<Text>(find.byKey(const ValueKey('tv_spotlight_episode_title')))
                    .style!;
                expect(metadataStyle.fontSize, episodeTitleStyle.fontSize);
              }
              expect(summaryStyle.fontSize, closeTo(14 * scale, 0.001));
              expect(summaryStyle.fontSize, lessThan(metadataStyle.fontSize!));
              if (!isShow) {
                expect(tester.widget<Text>(find.text('HEVC')).style!.fontSize, closeTo(16 * scale * labelScale, 0.001));
                for (final label in ['4K', 'HEVC', 'Dolby Vision', 'EAC3 Atmos', '4.90GB | 12.0Mbps']) {
                  expect(find.text(label), findsOneWidget);
                }
              }
              expect(
                tester.getSize(find.byKey(const ValueKey('tv_spotlight_logo_slot'))).height,
                closeTo(96 * scale, 0.001),
              );
              for (final card in find.byType(MediaCard).evaluate()) {
                final box = card.renderObject! as RenderBox;
                expect(box.localToGlobal(Offset(0, box.size.height)).dy, lessThanOrEqualTo(canvas.height));
              }
            },
          );
        }
      }
    }
  }
}
