import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/media_kind.dart';
import '../media/media_library.dart';
import '../services/settings_service.dart';

const sidebarLibraryPrefix = 'library:';
String sidebarLibraryKey(MediaLibrary library) => '$sidebarLibraryPrefix${library.globalKey}';

IconData sidebarLibraryIcon(MediaLibrary library) => switch (library.kind) {
  MediaKind.movie => Symbols.movie_rounded,
  MediaKind.show || MediaKind.season || MediaKind.episode => Symbols.tv_rounded,
  MediaKind.artist || MediaKind.album || MediaKind.track => Symbols.music_note_rounded,
  MediaKind.photo => Symbols.photo_library_rounded,
  _ => Symbols.folder_rounded,
};

(String, IconData) sidebarDestination(String key) => switch (key) {
  'home' => (t.common.home, Symbols.home_rounded),
  'nowPlaying' => (t.music.nowPlaying, Symbols.graphic_eq_rounded),
  'libraries' => (t.navigation.libraries, Symbols.video_library_rounded),
  'favorites' => (t.libraries.filterCategories.favorites, Symbols.favorite_rounded),
  'collections' => (t.collections.title, Symbols.stacks_rounded),
  'liveTv' => (t.navigation.liveTv, Symbols.live_tv_rounded),
  'explore' => (t.navigation.explore, Symbols.explore_rounded),
  'search' => (t.common.search, Symbols.search_rounded),
  'downloads' => (t.navigation.downloads, Symbols.download_rounded),
  _ => (t.common.settings, Symbols.settings_rounded),
};

/// Before customization, keep existing libraries accessible. Once customized,
/// only explicitly pinned keys appear; newly discovered libraries do not undo
/// the user's choice. Unavailable pins remain saved for a reconnect.
Set<String> pinnedSidebarLibraries(SettingsService settings, Iterable<MediaLibrary> libraries) =>
    settings.read(SettingsService.sidebarLibrariesConfigured)
    ? settings.read(SettingsService.sidebarPinnedLibraries).toSet()
    : {for (final library in libraries) library.globalKey};
