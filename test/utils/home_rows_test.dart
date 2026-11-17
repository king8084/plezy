import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_hub.dart';
import 'package:plezy/utils/home_rows.dart';

MediaHub _hub(String id) => MediaHub(id: id, title: id, type: 'movie', items: const [], size: 0, serverId: 's');

void main() {
  final rows = [_hub('a'), _hub('b'), _hub('c')];
  String key(String id) => homeRowKey(_hub(id));

  test('saved order first, unknown rows keep their natural place after it', () {
    final ordered = orderHomeRows(rows, order: [key('c'), key('a')]);
    expect(ordered.map((h) => h.id), ['c', 'a', 'b']);
  });

  test('hidden rows are left out', () {
    expect(orderHomeRows(rows, order: const [], hidden: {key('b')}).map((h) => h.id), ['a', 'c']);
  });

  test('moving a row keeps saved keys of rows that are not loaded right now', () {
    final order = moveHomeRow(rows, [key('gone'), key('a')], 2, 0);
    expect(order, [key('c'), key('a'), key('b'), key('gone')]);
  });
}
