import '../../test_helpers/profile_navigation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/media/server_capabilities.dart';
import 'package:plezy/screens/libraries/tabs/library_recommended_tab.dart';
import 'package:plezy/screens/media_detail_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import '../../test_helpers/library_tab_scaffold.dart';
import '../../test_helpers/media_items.dart';
import '../../test_helpers/multi_server_fixtures.dart';
import '../../test_helpers/prefs.dart';

class _Client implements MediaServerClient {
  final item = testMediaItem(
    id: 'e14',
    backend: MediaBackend.jellyfin,
    kind: MediaKind.episode,
    serverId: 'server',
    title: 'Heavy Is the Head',
    parentIndex: 8,
    index: 14,
    parentId: 's8',
    grandparentId: 'show',
    grandparentTitle: 'Modern Family',
  );
  @override
  ServerId get serverId => ServerId('server');
  @override
  String get serverName => 'Test';
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;
  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
    HubFetchDiagnostics? diagnostics,
  }) async => [
    MediaHub(id: 'continue_watching', title: 'Continue Watching', type: 'episode', items: [item]),
  ];
  @override
  Future<MediaItem?> fetchItem(String id, {bool includeExtras = false}) async =>
      testMediaItem(id: id, backend: backend, kind: MediaKind.show, title: 'Modern Family', serverId: 'server');
  @override
  Future<List<MediaItem>> fetchChildren(String id) async => const [];
  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Apple TV library Select opens the show at its episode even when card actions prefer Play', (
    tester,
  ) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.play);
    await settings.write(SettingsService.episodeAction, EpisodeAction.play);
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final client = _Client();
    final fixture = testMultiServer(clients: [client]);
    final library = MediaLibrary(
      id: 'tv',
      title: 'TV',
      kind: MediaKind.show,
      backend: MediaBackend.jellyfin,
      serverId: client.serverId,
    );
    await pumpLibraryTab(
      tester,
      provider: fixture.provider,
      appBuilder: (context, child) => withProfileNavigationScope(child: child!),
      tab: LibraryRecommendedTab(library: library, isActive: true),
    );
    await pumpRequestFrames(tester);
    final railFinder = find.byType(TvBrowseRail);
    expect(railFinder, findsOneWidget);
    tester.state<TvBrowseRailState>(railFinder).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final detail = tester.widget<MediaDetailScreen>(find.byType(MediaDetailScreen));
    expect(detail.metadata.id, 'show');
    expect(detail.initialEpisodeId, 'e14');
    expect(detail.initialSeasonIndex, 8);
    expect(tester.takeException(), isNull);
  });
}
