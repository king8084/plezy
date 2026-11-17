import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/screens/settings/home_sidebar_settings_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/utils/home_rows.dart';

import '../../test_helpers/prefs.dart';

MediaHub _hub(String id, String title) =>
    MediaHub(id: id, title: title, type: 'movie', items: const [], size: 0, serverId: 's');

void main() {
  setUpAll(() => LocaleSettings.setLocaleSync(AppLocale.en));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
  });

  final rows = [_hub('recent', 'Recently Added'), _hub('next', 'Next Up'), _hub('kids', 'Kids Picks')];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          home: HomeSidebarSettingsScreen(debugRows: rows),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists every Home row and the sidebar, pins and libraries in one place', (tester) async {
    await pump(tester);
    for (final row in rows) {
      expect(find.text(row.title), findsOneWidget);
    }
    expect(find.text(t.settings.pinnedHomeCollections), findsOneWidget);
    expect(find.text(t.libraries.manageLibraries), findsOneWidget);
  });

  testWidgets('hiding a row saves it and marks it hidden', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(t.settings.hideRowFromHome).last);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.homeRowHidden), [homeRowKey(rows.last)]);
    expect(find.text(t.settings.hiddenFromHome), findsOneWidget);
    await tester.tap(find.byTooltip(t.settings.showRowOnHome));
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.homeRowHidden), isEmpty);
  });

  testWidgets('moving a row down saves the new order', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip(t.discover.moveRowDown).first);
    await tester.pumpAndSettle();
    expect(SettingsService.instance.read(SettingsService.homeRowOrder), [
      homeRowKey(rows[1]),
      homeRowKey(rows[0]),
      homeRowKey(rows[2]),
    ]);
    final next = tester.getTopLeft(find.text('Next Up')).dy;
    expect(next, lessThan(tester.getTopLeft(find.text('Recently Added')).dy));
  });
}
