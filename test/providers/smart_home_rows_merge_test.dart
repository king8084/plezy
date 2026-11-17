import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/providers/discover_provider.dart';
import 'package:plezy/services/data_aggregation_service.dart';

import '../test_helpers/media_items.dart';

MediaHub _hub(String id, List<String> items, {String? title}) => MediaHub(
  id: id,
  title: title ?? id,
  type: 'mixed',
  items: [for (final item in items) testMediaItem(id: item)],
  size: items.length,
);

void main() {
  final latest = _hub('latest-movies', ['m1']);

  test('fresh smart rows replace the old ones, first, other rows untouched', () {
    final hubs = [
      _hub(smartTopRatedHubId, ['a', 'b']),
      _hub(smartBecauseWatchedHubId, ['c'], title: 'Old'),
      latest,
    ];
    final merged = DiscoverProvider.mergeSmartHomeRows(hubs, [
      _hub(smartBecauseWatchedHubId, ['d', 'e'], title: 'New'),
    ])!;
    expect([for (final hub in merged) hub.id], [smartTopRatedHubId, smartBecauseWatchedHubId, 'latest-movies']);
    expect(merged[1].title, 'New');
    expect([for (final item in merged[0].items) item.id], ['a', 'b'], reason: 'a missing row keeps its version');
    expect(identical(merged[2], latest), isTrue);
  });

  test('nothing changes when the fresh rows match', () {
    final hubs = [
      _hub(smartTopRatedHubId, ['a']),
      latest,
    ];
    expect(
      DiscoverProvider.mergeSmartHomeRows(hubs, [
        _hub(smartTopRatedHubId, ['a']),
      ]),
      isNull,
    );
    expect(DiscoverProvider.mergeSmartHomeRows([latest], const []), isNull);
  });

  test('a first smart row appears at the top', () {
    final merged = DiscoverProvider.mergeSmartHomeRows(
      [latest],
      [
        _hub(smartBecauseWatchedHubId, ['x']),
      ],
    )!;
    expect([for (final hub in merged) hub.id], [smartBecauseWatchedHubId, 'latest-movies']);
  });
}
