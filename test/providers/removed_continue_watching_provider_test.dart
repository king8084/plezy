import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/providers/removed_continue_watching_provider.dart';
import 'package:plezy/screens/settings/removed_continue_watching_screen.dart';
import 'package:plezy/services/settings_service.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/utils/watch_state_notifier.dart';
import 'package:provider/provider.dart';
import '../test_helpers/media_items.dart';
import '../test_helpers/prefs.dart';

MediaItem episode(String id, {String server = 'server', String series = 'show'}) => testMediaItem(
  id: id,
  kind: MediaKind.episode,
  backend: MediaBackend.jellyfin,
  title: 'Episode $id',
  serverId: server,
  grandparentId: series,
  grandparentTitle: 'Modern Family',
  viewOffsetMs: 123000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  test('series removal filters resume/next up, preserves library and progress, persists per profile', () async {
    final removed = RemovedContinueWatchingProvider(profileId: 'alice');
    await removed.ensureInitialized();
    addTearDown(removed.dispose);
    final item = episode('14');
    await removed.remove(item);
    expect(removed.entries.single.item.title, 'Modern Family');
    expect(removed.isHidden(episode('15')), isTrue);
    expect(removed.isHidden(episode('14', server: 'other')), isFalse);
    expect(item.viewOffsetMs, 123000);
    MediaHub hub(String id) => MediaHub(id: id, title: id, type: 'episode', items: [item]);
    final hubs = removed.filterHubs([hub('continue_watching'), hub('tv.nextup'), hub('recent')]);
    expect(hubs[0].items, isEmpty);
    expect(hubs[1].items, isEmpty);
    expect(hubs[2].items, [item]);
    final reload = RemovedContinueWatchingProvider(profileId: 'alice');
    final other = RemovedContinueWatchingProvider(profileId: 'bob');
    addTearDown(reload.dispose);
    addTearDown(other.dispose);
    await Future.wait([reload.ensureInitialized(), other.ensureInitialized()]);
    expect(reload.isHidden(item), isTrue);
    expect(other.entries, isEmpty);
    await reload.restore(reload.entries.single.key);
    expect(reload.isHidden(item), isFalse);
    expect(reload.entries, isEmpty);
  });

  test('new playback restores whole series, other server events do not', () async {
    final removed = RemovedContinueWatchingProvider(profileId: 'alice');
    await removed.ensureInitialized();
    addTearDown(removed.dispose);
    await removed.remove(episode('14'));
    WatchStateNotifier().notifyProgress(item: episode('15', server: 'other'), viewOffset: 1000, duration: 100000);
    await pumpEventQueue();
    expect(removed.entries, hasLength(1));
    WatchStateNotifier().notifyProgress(item: episode('15'), viewOffset: 1000, duration: 100000);
    await pumpEventQueue();
    expect(removed.entries, isEmpty);
  });

  test('server playback newer than removal restores without resetting resume', () async {
    final now = DateTime.utc(2026, 11, 14, 15);
    final removed = RemovedContinueWatchingProvider(profileId: 'alice', now: () => now);
    await removed.ensureInitialized();
    addTearDown(removed.dispose);
    await Future.wait([removed.remove(episode('14')), removed.remove(episode('1', series: 'other-show'))]);
    expect(removed.entries, hasLength(2));
    final fresh = episode(
      '15',
    ).copyWith(lastViewedAt: now.add(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000);
    expect(removed.isHidden(fresh), isFalse);
    await removed.observeItems([fresh]);
    expect(removed.entries.single.item.id, 'other-show');
    expect(fresh.viewOffsetMs, 123000);
  });

  testWidgets('Settings shows poster/title/date and Select restores the focused entry', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    late RemovedContinueWatchingProvider removed;
    await tester.runAsync(() async {
      removed = RemovedContinueWatchingProvider(profileId: 'alice');
      await removed.ensureInitialized();
      await removed.remove(episode('14'));
    });
    addTearDown(removed.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: removed,
        child: MaterialApp(home: const RemovedContinueWatchingScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Modern Family'), findsOneWidget);
    expect(find.textContaining(t.settings.restoreContinueWatching), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(removed.entries, isEmpty);
    expect(find.text(t.hubDetail.noItemsFound), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
