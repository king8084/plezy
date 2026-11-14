import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/navigation/sidebar_order.dart';
import 'package:plezy/screens/settings/sidebar_order_sheet.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';

import '../../test_helpers/prefs.dart';

void main() {
  test('sidebar ordering tolerates unknown/duplicate saved keys and appends new entries', () {
    expect(
      resolveSidebarOrder(
        ['favorites', 'stale', 'favorites', 'settings'],
        ['home', 'favorites', 'settings', 'collections'],
      ),
      ['favorites', 'settings', 'home', 'collections'],
    );
  });

  testWidgets('remote moves Favorites to the top, confirms it, and cancels an uncommitted move', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.pinFavoritesToSidebar, true);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: InputModeTracker(child: const SidebarOrderSheet())),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    // Home, Now Playing, Libraries, Favorites.
    for (var i = 0; i < 3; i++) {
      await press(LogicalKeyboardKey.arrowDown);
    }
    await press(LogicalKeyboardKey.select);
    for (var i = 0; i < 3; i++) {
      await press(LogicalKeyboardKey.arrowUp);
    }
    await press(LogicalKeyboardKey.select);
    expect(settings.read(SettingsService.sidebarOrder).first, 'favorites');
    final saved = List.of(settings.read(SettingsService.sidebarOrder));
    await press(LogicalKeyboardKey.select);
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.escape);
    expect(settings.read(SettingsService.sidebarOrder), saved);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title! as Text).data, 'Favorites');
    expect(tester.takeException(), isNull);
  });
}
