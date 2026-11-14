import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_reorder_mixin.dart';
import '../../focus/input_mode_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../navigation/sidebar_order.dart';
import '../../services/settings_service.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/bottom_sheet_page_scaffold.dart';

class SidebarOrderSheet extends StatefulWidget {
  const SidebarOrderSheet({super.key});

  @override
  State<SidebarOrderSheet> createState() => _SidebarOrderSheetState();
}

class _SidebarOrderSheetState extends State<SidebarOrderSheet> with DpadReorderListMixin<String, SidebarOrderSheet> {
  late List<String> _items;
  final _focusNode = FocusNode(debugLabel: 'sidebar_order');
  final _scrollController = ScrollController();

  @override
  List<String> get reorderItems => _items;
  @override
  set reorderItems(List<String> value) => _items = value;
  @override
  int get lastReorderColumn => 0;
  @override
  ScrollController get reorderScrollController => _scrollController;
  @override
  void onReorderColumnActivated(int column, int index) {}
  @override
  void onReorderMoveConfirmed() => _save();

  void _save() {
    // Keep currently hidden entries in the saved order as well.
    final saved = resolveSidebarOrder(SettingsService.instance.read(SettingsService.sidebarOrder), defaultSidebarOrder);
    final visible = _items.toSet();
    var i = 0;
    unawaited(
      SettingsService.instance.write(SettingsService.sidebarOrder, [
        for (final key in saved) visible.contains(key) ? _items[i++] : key,
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    _items = resolveSidebarOrder(SettingsService.instance.read(SettingsService.sidebarOrder), [
      for (final key in defaultSidebarOrder)
        if ((key != 'downloads' || !PlatformDetector.isAppleTV()) &&
            (key != 'nowPlaying' || PlatformDetector.isTV()) &&
            (key != 'favorites' || SettingsService.instance.read(SettingsService.pinFavoritesToSidebar)) &&
            (key != 'collections' || SettingsService.instance.read(SettingsService.pinCollectionsToSidebar)))
          key,
    ]);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  (String, IconData) _label(String key) => switch (key) {
    'home' => (t.common.home, Symbols.home_rounded),
    'nowPlaying' => (t.music.nowPlaying, Symbols.music_note_rounded),
    'libraries' => (t.navigation.libraries, Symbols.video_library_rounded),
    'favorites' => (t.libraries.filterCategories.favorites, Symbols.favorite_rounded),
    'collections' => (t.collections.title, Symbols.collections_rounded),
    'liveTv' => (t.navigation.liveTv, Symbols.live_tv_rounded),
    'explore' => (t.navigation.explore, Symbols.explore_rounded),
    'search' => (t.common.search, Symbols.search_rounded),
    'downloads' => (t.navigation.downloads, Symbols.download_rounded),
    _ => (t.common.settings, Symbols.settings_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final keyboard = InputModeTracker.isKeyboardMode(context);
    return BottomSheetPageScaffold(
      title: t.settings.sidebarOrder,
      icon: Symbols.swap_vert_rounded,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(t.settings.sidebarOrderDescription)),
          Flexible(
            child: Focus(
              focusNode: _focusNode,
              autofocus: keyboard,
              descendantsAreFocusable: false,
              onKeyEvent: handleReorderKeyEvent,
              child: ReorderableListView.builder(
                shrinkWrap: true,
                scrollController: _scrollController,
                buildDefaultDragHandles: false,
                itemCount: _items.length,
                onReorderItem: (from, to) {
                  setState(() => _items.insert(to, _items.removeAt(from)));
                  _save();
                },
                itemBuilder: (context, index) {
                  final (label, icon) = _label(_items[index]);
                  return ListTile(
                    key: ValueKey(_items[index]),
                    tileColor: movingIndex == index
                        ? Theme.of(context).colorScheme.primaryContainer
                        : keyboard && focusedIndex == index
                        ? Theme.of(context).colorScheme.surfaceContainerHighest
                        : null,
                    leading: AppIcon(icon, fill: 1),
                    title: Text(label),
                    trailing: ReorderableDragStartListener(
                      index: index,
                      child: const AppIcon(Symbols.drag_indicator_rounded),
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
