import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_backend.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/media/media_item.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/widgets/tv_spotlight_scaffold.dart';
import '../test_helpers/media_items.dart';

MediaItem _item(String id) => testMediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: id);

MediaHub _hub(String id, List<MediaItem> items) =>
    MediaHub(id: id, title: id, type: 'movie', size: items.length, items: items);

void main() {
  testWidgets('spotlight settles on a new title in 80 milliseconds', (tester) async {
    final first = _item('first');
    final second = _item('second');
    final controller = TvSpotlightController()..value = first;
    addTearDown(controller.dispose);
    controller.select(second);
    await tester.pump(const Duration(milliseconds: 79));
    expect(controller.value, same(first));
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.value, same(second));
  });
  test('spotlight controller cancels an intermediate debounced selection', () async {
    final first = _item('first');
    final second = _item('second');
    final controller = TvSpotlightController(settleDelay: const Duration(milliseconds: 10));
    addTearDown(controller.dispose);
    controller.value = first;

    controller.select(second);
    controller.select(first);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(controller.value, same(first));
  });

  test('spotlight controller resolves valid selection or first hub item', () {
    final first = _item('first');
    final second = _item('second');
    final controller = TvSpotlightController(settleDelay: Duration.zero);
    addTearDown(controller.dispose);
    final hubs = [
      _hub('one', [first]),
      _hub('two', [second]),
    ];

    expect(controller.resolve(hubs), same(first));
    controller.select(second);
    expect(controller.resolve(hubs), same(second));

    controller.value = _item('removed');
    expect(controller.resolve(hubs), same(first));
  });

  test('spotlight controller resolves the latest item instance for a retained selection', () {
    final stale = _item('same');
    final refreshed = testMediaItem(id: 'same', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Updated');
    final controller = TvSpotlightController(settleDelay: Duration.zero);
    addTearDown(controller.dispose);
    controller.value = stale;

    expect(
      controller.resolve([
        _hub('one', [refreshed]),
      ]),
      same(refreshed),
    );
  });
}
