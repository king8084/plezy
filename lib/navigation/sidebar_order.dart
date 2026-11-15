/// Stable storage keys. Hidden destinations retain their position when their
/// setting/service becomes available again. TV libraries have independent keys; legacy group positions are preserved.
const defaultSidebarOrder = [
  'home',
  'nowPlaying',
  'libraries',
  'favorites',
  'collections',
  'liveTv',
  'explore',
  'search',
  'downloads',
  'settings',
];

List<String> resolveSidebarOrder(List<String> saved, Iterable<String> visible) {
  final available = visible.toList();
  final allowed = available.toSet();
  final libraries = available.where((key) => key.startsWith('library:'));
  final explicitlyPlaced = saved.where((key) => key.startsWith('library:')).toSet();
  final seen = <String>{};
  return [
    for (final key in [...saved, ...defaultSidebarOrder, ...available])
      if (key == 'libraries' && !allowed.contains(key)) ...[
        for (final library in libraries)
          if (!explicitlyPlaced.contains(library) && seen.add(library)) library,
      ] else if (allowed.contains(key) && seen.add(key))
        key,
  ];
}

/// Reorder visible entries while keeping hidden destinations and unavailable
/// library pins in storage, ready to return at their previous position.
List<String> mergeSidebarOrder(List<String> saved, List<String> visible) {
  final all = resolveSidebarOrder(saved, {...saved, ...defaultSidebarOrder, ...visible});
  final changed = visible.toSet();
  var index = 0;
  return [for (final key in all) changed.contains(key) ? visible[index++] : key];
}
