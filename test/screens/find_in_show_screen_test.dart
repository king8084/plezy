import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/screens/find_in_show_screen.dart';
import 'package:plezy/services/data_aggregation_service.dart';
import 'package:plezy/services/download_manager_service.dart';
import 'package:plezy/services/download_storage_service.dart';
import 'package:plezy/services/jellyfin_api_cache.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/plex_api_cache.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/services/smart_search/smart_search_client.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/media_server_http_client.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/episode_card.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

class _FakeFindService extends DataAggregationService {
  _FakeFindService(this.answer) : super(MultiServerManager());

  final List<SmartSuggestion> Function(String query) answer;
  final calls = <({String show, String query, bool recall})>[];

  @override
  Future<List<SmartSuggestion>> findInShow(
    MediaItem show,
    String query, {
    bool recall = false,
    AbortController? abort,
  }) async {
    calls.add((show: show.id, query: query, recall: recall));
    return answer(query);
  }
}

MediaItem _episode(String id, String title, int season, int number) => testMediaItem(
  id: id,
  backend: MediaBackend.jellyfin,
  kind: MediaKind.episode,
  title: title,
  parentIndex: season,
  index: number,
  grandparentTitle: 'Modern Family',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final show = testMediaItem(
    id: 'modern-family',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.show,
    title: 'Modern Family',
  );

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
    await SettingsService.getInstance();
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Future<void> pumpFind(WidgetTester tester, _FakeFindService service) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();
    addTearDown(() async {
      downloadProvider.dispose();
      downloadManager.dispose();
      await db.close();
    });
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<DownloadProvider>.value(
          value: downloadProvider,
          child: MaterialApp(
            theme: monoTheme(MonoPalette.dark),
            home: FindInShowScreen(show: show, service: service),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing finds the show\'s episodes; Search also asks the AI', (tester) async {
    final service = _FakeFindService(
      (query) => [
        SmartSuggestion(item: _episode('e1', 'Benched', 1, 20), match: SmartSearchMatch.possible),
        SmartSuggestion(item: _episode('e2', 'Basketball', 8, 16), match: SmartSearchMatch.possible),
      ],
    );
    await pumpFind(tester, service);

    expect(find.text('Find in Modern Family'), findsOneWidget);
    expect(find.textContaining('Describe what happens'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'phil basketball');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(service.calls.single, (show: 'modern-family', query: 'phil basketball', recall: false));
    expect(find.byType(EpisodeCard), findsNWidgets(2));
    expect(find.textContaining('Benched', findRichText: true), findsWidgets);

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    expect(service.calls.last, (show: 'modern-family', query: 'phil basketball', recall: true));
  });

  testWidgets('says so when nothing matches', (tester) async {
    final service = _FakeFindService((_) => const []);
    await pumpFind(tester, service);

    await tester.enterText(find.byType(TextField), 'dragons');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('No matching episodes'), findsOneWidget);
    expect(find.byType(EpisodeCard), findsNothing);
  });
}
