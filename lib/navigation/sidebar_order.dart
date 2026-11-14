/// Stable storage keys. Hidden destinations retain their position when their
/// setting/service becomes available again. Nested libraries travel as a group.
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
  final allowed = visible.toSet();
  final seen = <String>{};
  return [
    for (final key in [...saved, ...defaultSidebarOrder])
      if (allowed.contains(key) && seen.add(key)) key,
  ];
}
