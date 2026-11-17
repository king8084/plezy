import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/input_mode_tracker.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_library.dart';
import '../../navigation/sidebar_destinations.dart';
import '../../navigation/sidebar_order.dart';
import '../../providers/hidden_libraries_provider.dart';
import '../../providers/libraries_provider.dart';
import '../../providers/catalog_sources_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/settings_service.dart';
import '../../services/music/music_playback_service.dart';
import '../../utils/platform_detector.dart';
import '../../utils/scroll_utils.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_page_scaffold.dart';
import '../../widgets/overlay_sheet.dart';

/// Explicit Pin / Up / Down controls: every move saves immediately. The remote
/// uses the same controls as touch, with no invisible drag or confirm mode.
class SidebarOrderSheet extends StatefulWidget {
  const SidebarOrderSheet({super.key});

  @override
  State<SidebarOrderSheet> createState() => _SidebarOrderSheetState();
}

class _SidebarOrderSheetState extends State<SidebarOrderSheet> {
  final _focusNode = FocusNode(debugLabel: 'sidebar_order');
  final _scrollController = ScrollController();
  final _items = <String>[];
  int _index = 0;
  int _action = 1;
  bool _initialized = false;
  bool _savingPin = false;
  SettingsService get _settings => SettingsService.instance;

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _move(int index, int delta) {
    final next = index + delta;
    if (next < 0 || next >= _items.length) return;
    setState(() {
      _items.insert(next, _items.removeAt(index));
      _index = next;
    });
    unawaited(
      _settings.write(
        SettingsService.sidebarOrder,
        mergeSidebarOrder(_settings.read(SettingsService.sidebarOrder), _items),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) scrollIndexIntoView(_scrollController, _index);
    });
  }

  bool _isPinned(String key, List<MediaLibrary> libraries) {
    if (key.startsWith(sidebarLibraryPrefix)) {
      return pinnedSidebarLibraries(_settings, libraries).contains(key.substring(sidebarLibraryPrefix.length));
    }
    if (key == 'favorites') return _settings.read(SettingsService.pinFavoritesToSidebar);
    if (key == 'collections') return _settings.read(SettingsService.pinCollectionsToSidebar);
    return true;
  }

  bool _canPin(String key) => key == 'favorites' || key == 'collections' || key.startsWith(sidebarLibraryPrefix);

  Future<void> _togglePin(String key, List<MediaLibrary> libraries) async {
    if (!_canPin(key) || _savingPin) return;
    _savingPin = true;
    try {
      if (key.startsWith(sidebarLibraryPrefix)) {
        final pinned = pinnedSidebarLibraries(_settings, libraries);
        final id = key.substring(sidebarLibraryPrefix.length);
        if (!pinned.remove(id)) pinned.add(id);
        // Write the keys first: the configured flag can never expose an empty
        // intermediate list on the first customization.
        await _settings.write(SettingsService.sidebarPinnedLibraries, pinned.toList());
        await _settings.write(SettingsService.sidebarLibrariesConfigured, true);
      } else {
        final pref = key == 'favorites'
            ? SettingsService.pinFavoritesToSidebar
            : SettingsService.pinCollectionsToSidebar;
        await _settings.write(pref, !_settings.read(pref));
      }
      if (mounted) setState(() {});
    } finally {
      _savingPin = false;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event, List<MediaLibrary> libraries) {
    if (event.logicalKey.isBackKey) {
      return handleBackKeyAction(event, () => OverlaySheetController.popAdaptive(context));
    }
    final selected = handleOneShotSelect(event, () {
      if (_items.isEmpty) return;
      switch (_action) {
        case 0:
          unawaited(_togglePin(_items[_index], libraries));
        case 1:
          _move(_index, -1);
        case 2:
          _move(_index, 1);
      }
    });
    if (selected != KeyEventResult.ignored) return selected;
    if (!event.isActionable || _items.isEmpty) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowDown) {
      setState(() => _index = (_index + (key == LogicalKeyboardKey.arrowDown ? 1 : -1)).clamp(0, _items.length - 1));
      scrollIndexIntoView(_scrollController, _index);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowLeft || key == LogicalKeyboardKey.arrowRight) {
      setState(() => _action = (_action + (key == LogicalKeyboardKey.arrowRight ? 1 : -1)).clamp(0, 2));
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final libraries = context.watch<LibrariesProvider?>()?.libraries ?? const <MediaLibrary>[];
    final hidden = context.watch<HiddenLibrariesProvider?>()?.hiddenLibraryKeys ?? const <String>{};
    final available = [
      for (final library in libraries)
        if (!hidden.contains(library.globalKey)) library,
    ];
    final byKey = {for (final library in available) sidebarLibraryKey(library): library};
    final hasNowPlaying = context.watch<MusicPlaybackService?>()?.currentTrack != null;
    final hasLiveTv = context.watch<MultiServerProvider?>()?.hasLiveTv ?? false;
    final hasExplore =
        (context.watch<CatalogSourcesProvider?>()?.hasAnySource ?? false) &&
        _settings.read(SettingsService.showExploreTab);
    final keys = [
      for (final key in defaultSidebarOrder)
        if ((key != 'libraries' || !PlatformDetector.isTV()) &&
            (key != 'downloads' || !PlatformDetector.isAppleTV()) &&
            (key != 'nowPlaying' || (PlatformDetector.isTV() && hasNowPlaying)) &&
            (key != 'liveTv' || hasLiveTv) &&
            (key != 'explore' || hasExplore))
          key,
      if (PlatformDetector.isTV()) ...byKey.keys,
    ];
    if (!_initialized) {
      _items.addAll(resolveSidebarOrder(_settings.read(SettingsService.sidebarOrder), keys));
      _initialized = true;
    } else {
      if (_items.length != keys.length || !_items.toSet().containsAll(keys)) {
        final focusedKey = _items.isEmpty ? null : _items[_index];
        _items
          ..clear()
          ..addAll(resolveSidebarOrder(_settings.read(SettingsService.sidebarOrder), keys));
        final restored = focusedKey == null ? -1 : _items.indexOf(focusedKey);
        if (restored >= 0) _index = restored;
      }
      _index = _index.clamp(0, _items.isEmpty ? 0 : _items.length - 1);
    }
    final keyboard = InputModeTracker.isKeyboardMode(context);
    final colors = Theme.of(context).colorScheme;
    return BottomSheetPageScaffold(
      title: t.settings.customizeSidebar,
      icon: Symbols.tune_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(t.settings.customizeSidebarDescription)),
          Flexible(
            child: Focus(
              focusNode: _focusNode,
              autofocus: keyboard,
              descendantsAreFocusable: false,
              onKeyEvent: (node, event) => _onKey(node, event, available),
              child: ListView.builder(
                shrinkWrap: true,
                controller: _scrollController,
                itemCount: _items.length,
                itemBuilder: (context, index) {
                  final key = _items[index];
                  final library = byKey[key];
                  final (label, icon) = library == null
                      ? sidebarDestination(key)
                      : (library.title, sidebarLibraryIcon(library));
                  final pinned = _isPinned(key, available);
                  Widget action(int column, IconData icon, String hint, VoidCallback? onTap) => Semantics(
                    label: hint,
                    button: true,
                    enabled: onTap != null,
                    focused: keyboard && index == _index && column == _action,
                    child: Tooltip(
                      message: hint,
                      child: InkWell(
                        onTap: onTap,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          key: ValueKey('sidebar_${key}_action_$column'),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: keyboard && index == _index && column == _action ? colors.primary : null,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: AppIcon(
                            icon,
                            fill: column == 0 && pinned && _canPin(key) ? 1 : 0,
                            weight: 400,
                            size: 22,
                            color: keyboard && index == _index && column == _action
                                ? colors.onPrimary.withValues(alpha: onTap == null ? 0.45 : 1)
                                : onTap == null
                                ? colors.onSurface.withValues(alpha: 0.25)
                                : column == 0 && pinned
                                ? const Color(0xFFE6B95B)
                                : colors.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                  return Container(
                    key: ValueKey(key),
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                    decoration: BoxDecoration(
                      color: keyboard && _index == index ? colors.surfaceContainerHighest : colors.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: ListTile(
                      leading: AppIcon(
                        icon,
                        fill: 0,
                        weight: 400,
                        color: pinned ? colors.onSurface : colors.onSurfaceVariant,
                      ),
                      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: library == null || library.serverName == null
                          ? null
                          : Text(library.serverName!, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          action(
                            0,
                            pinned ? Symbols.push_pin_rounded : Symbols.add_rounded,
                            pinned ? t.settings.unpinFromSidebar : t.settings.pinToSidebar,
                            _canPin(key) ? () => unawaited(_togglePin(key, available)) : null,
                          ),
                          action(
                            1,
                            Symbols.arrow_upward_rounded,
                            t.settings.sidebarMoveUp,
                            index > 0 ? () => _move(index, -1) : null,
                          ),
                          action(
                            2,
                            Symbols.arrow_downward_rounded,
                            t.settings.sidebarMoveDown,
                            index + 1 < _items.length ? () => _move(index, 1) : null,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
