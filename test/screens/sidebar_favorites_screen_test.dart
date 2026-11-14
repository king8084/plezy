import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/ids.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_server_client.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/sidebar_favorites_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/media_card.dart';
import 'package:plezy/widgets/media_technical_badges.dart';
import 'package:plezy/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/media_items.dart';
import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';

class _Client implements MediaServerClient {
  _Client(this.items);
  final List<MediaItem> items;
  final reads = <String>[];
  @override
  ServerId get serverId => ServerId('server');
  @override
  MediaBackend get backend => MediaBackend.jellyfin;
  @override
  Future<MediaItem?> fetchItem(String id) async {
    reads.add(id);
    return items.firstWhere((item) => item.id == id);
  }

  @override
  void close() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Favorites follows focused show metadata and the existing Poster Card Size setting', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.libraryDensity, LibraryDensity.min);
    final items = [
      for (var i = 1; i <= 2; i++)
        testMediaItem(
          backend: MediaBackend.jellyfin,
          id: 'show$i',
          title: 'Favorite Show $i',
          kind: MediaKind.show,
          summary: 'Description for favorite show $i.',
          year: 2009,
          rating: 8.5,
          genres: ['Comedy'],
          contentRating: 'TV-PG',
          serverId: 'server',
        ),
    ];
    final client = _Client(items);
    final provider = testMultiServer(clients: [client]).provider;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          home: withProfileNavigationScope(child: SidebarFavoritesScreen(loadItems: () async => items)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Description for favorite show 1.'), findsOneWidget);
    expect(find.textContaining('Comedy'), findsWidgets);
    expect(tester.widget<MediaTechnicalBadges>(find.byType(MediaTechnicalBadges)).labels, isEmpty);
    final rail = tester.state<TvBrowseRailState>(find.byType(TvBrowseRail));
    expect(rail.focusedMediaItem?.id, 'show1');
    final narrow = tester.getSize(find.byType(MediaCard).first).width;
    await settings.write(SettingsService.libraryDensity, LibraryDensity.max);
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(MediaCard).first).width, greaterThan(narrow));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(rail.focusedMediaItem?.id, 'show2');
    expect(find.text('Description for favorite show 2.'), findsOneWidget);
    expect(client.reads.toSet().difference({'show1', 'show2'}), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
