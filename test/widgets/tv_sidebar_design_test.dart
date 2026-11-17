import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_library.dart';
import 'package:plezy/navigation/navigation_tabs.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/providers/hidden_libraries_provider.dart';
import 'package:plezy/providers/libraries_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/screens/settings/sidebar_order_sheet.dart';
import 'package:plezy/services/multi_server_manager.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/side_navigation_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/multi_server_fixtures.dart';
import '../test_helpers/prefs.dart';

class _Sources extends CatalogSourcesProvider {
  @override
  bool get hasAnySource => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('SidebarTestFont')..addFont(rootBundle.load('assets/go-noto-current-regular.ttf'))).load();
    await (FontLoader(
      'packages/material_symbols_icons/MaterialSymbolsRounded',
    )..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'))).load();
  });

  testWidgets('TV sidebar and customization remain legible with real fonts at 720p', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.pinFavoritesToSidebar, true);
    await settings.write(SettingsService.pinCollectionsToSidebar, true);
    final libraries = LibrariesProvider();
    await libraries.updateLibraryOrder(const [
      MediaLibrary(
        id: 'movies',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Movies',
        serverId: 'server',
        serverName: 'Jellyfin',
      ),
      MediaLibrary(
        id: 'tv',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.show,
        title: 'TV Shows',
        serverId: 'server',
        serverName: 'Jellyfin',
      ),
      MediaLibrary(
        id: 'anime',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.show,
        title: 'Anime',
        serverId: 'server',
        serverName: 'Jellyfin',
      ),
    ]);
    final hidden = HiddenLibrariesProvider();
    await hidden.ensureInitialized();
    final server = testMultiServerProvider(MultiServerManager());
    final sources = _Sources();
    addTearDown(() {
      libraries.dispose();
      hidden.dispose();
      server.dispose();
      sources.dispose();
    });
    tester.view.physicalSize = const Size(800, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final capture = GlobalKey();
    final railKey = GlobalKey<SideNavigationRailState>();
    Widget host(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
        ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
        ChangeNotifierProvider<MultiServerProvider>.value(value: server),
        ChangeNotifierProvider<CatalogSourcesProvider>.value(value: sources),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(
            MonoPalette.dark,
          ).copyWith(textTheme: monoTheme(MonoPalette.dark).textTheme.apply(fontFamily: 'SidebarTestFont')),
          home: Scaffold(
            body: InputModeTracker(
              child: RepaintBoundary(key: capture, child: child),
            ),
          ),
        ),
      ),
    );
    Future<void> screenshot(String name) async {
      if (!const bool.fromEnvironment('PLEZY_UI_PREVIEW')) return;
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.5);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('/tmp/plezy-$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.centerLeft,
          child: SideNavigationRail(
            key: railKey,
            selectedTab: NavigationTabId.discover,
            alwaysExpanded: true,
            isSidebarFocused: true,
            onDestinationSelected: (_) {},
            onLibrarySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    railKey.currentState!.focusHomeItem();
    await tester.pumpAndSettle();
    expect(find.text('Libraries'), findsNothing);
    expect(find.text('TV Shows'), findsOneWidget);
    final item = tester.widget<NavigationRailItem>(find.widgetWithText(NavigationRailItem, 'Home'));
    expect(item.focusNode.hasFocus, isTrue);
    expect(tester.takeException(), isNull);
    await screenshot('sidebar-expanded');
    await tester.pumpWidget(host(const SizedBox(width: 720, child: SidebarOrderSheet())));
    await tester.pumpAndSettle();
    expect(find.text('Customize sidebar'), findsOneWidget);
    expect(find.text('TV Shows'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await screenshot('sidebar-settings');
    final movie = libraries.libraries.first;
    await tester.tap(find.byKey(ValueKey('sidebar_library:${movie.globalKey}_action_0')));
    await tester.pumpAndSettle();
    expect(settings.read(SettingsService.sidebarLibrariesConfigured), isTrue);
    expect(settings.read(SettingsService.sidebarPinnedLibraries), [
      for (final library in libraries.libraries.skip(1)) library.globalKey,
    ]);
    await tester.pumpWidget(
      host(
        Align(
          alignment: Alignment.centerLeft,
          child: SideNavigationRail(
            selectedTab: NavigationTabId.discover,
            alwaysExpanded: true,
            onDestinationSelected: (_) {},
            onLibrarySelected: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Movies'), findsNothing);
    expect(find.text('TV Shows'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
