import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/screens/settings/pinned_home_collections_screen.dart';
import 'package:plezy/services/home_pinned_collections.dart';
import 'package:plezy/services/settings_service.dart';

import '../test_helpers/prefs.dart';

void main() {
  testWidgets('an unavailable saved pin remains visible and can be removed', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.homePinnedCollections, [homePinnedCollectionKey('offline', 'gone')]);
    await tester.pumpWidget(const MaterialApp(home: PinnedHomeCollectionsScreen()));
    expect(find.text(t.settings.pinnedCollectionUnavailable), findsOneWidget);
    await tester.tap(find.text(t.settings.pinnedCollectionUnavailable));
    await tester.pumpAndSettle();
    expect(settings.read(SettingsService.homePinnedCollections), isEmpty);
    expect(find.text(t.hubDetail.noItemsFound), findsOneWidget);
  });
}
