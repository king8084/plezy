import '../media/media_hub.dart';

/// Identity of a Home row across launches: server, hub and library. Shared by
/// the Home screen and the Home & Sidebar settings page so both agree on which
/// row a saved order or hidden flag belongs to.
String homeRowKey(MediaHub hub) => '${hub.serverId ?? ''}\u001f${hub.id}\u001f${hub.libraryId ?? ''}';

/// [hubs] in the user's saved [order] (rows missing from it keep their natural
/// position after the saved ones), without rows whose key is in [hidden].
List<MediaHub> orderHomeRows(List<MediaHub> hubs, {required List<String> order, Set<String> hidden = const {}}) {
  final positions = {for (var i = 0; i < order.length; i++) order[i]: i};
  final indexed = [
    for (var i = 0; i < hubs.length; i++)
      if (!hidden.contains(homeRowKey(hubs[i]))) (index: i, hub: hubs[i]),
  ];
  indexed.sort((a, b) {
    final aPos = positions[homeRowKey(a.hub)] ?? order.length + a.index;
    final bPos = positions[homeRowKey(b.hub)] ?? order.length + b.index;
    return aPos.compareTo(bPos);
  });
  return [for (final entry in indexed) entry.hub];
}

/// A full saved order after moving the row at [from] to [to] within [rows]
/// (the rows as currently shown, hidden ones included). Keys of rows that are
/// not present right now keep their saved places at the end.
List<String> moveHomeRow(List<MediaHub> rows, List<String> previous, int from, int to) {
  final keys = [for (final row in rows) homeRowKey(row)];
  final key = keys.removeAt(from);
  keys.insert(to, key);
  return [...keys, ...previous.where((saved) => !keys.contains(saved))];
}
