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

  test('flat library order survives the legacy Libraries position', () {
    expect(
      resolveSidebarOrder(
        ['home', 'libraries', 'settings', 'library:movies'],
        ['home', 'library:movies', 'library:tv', 'settings'],
      ),
      ['home', 'library:tv', 'settings', 'library:movies'],
    );
    final saved = mergeSidebarOrder(
      ['home', 'libraries', 'favorites', 'library:offline'],
      ['favorites', 'home', 'library:movies'],
    );
    expect(saved, contains('library:offline'));
    expect(resolveSidebarOrder(saved, ['home', 'favorites', 'library:movies']), [
      'favorites',
      'home',
      'library:movies',
    ]);
  });

  testWidgets('remote arrows move Favorites immediately and Pin toggles visibility', (tester) async {
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

    // Home, Favorites. Inactive services are omitted, as in the actual rail.
    await press(LogicalKeyboardKey.arrowDown);
    await press(LogicalKeyboardKey.select);
    expect(settings.read(SettingsService.sidebarOrder).first, 'favorites');
    await press(LogicalKeyboardKey.arrowLeft);
    await press(LogicalKeyboardKey.select);
    expect(settings.read(SettingsService.pinFavoritesToSidebar), isFalse);
    await press(LogicalKeyboardKey.select);
    expect(settings.read(SettingsService.pinFavoritesToSidebar), isTrue);
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title! as Text).data, 'Favorites');
    expect(find.text('Libraries'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
