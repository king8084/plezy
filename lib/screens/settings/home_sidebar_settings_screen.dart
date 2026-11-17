import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focusable_action_bar.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_hub.dart';
import '../../providers/discover_provider.dart';
import '../../services/settings_service.dart';
import '../../utils/home_rows.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/library_management_sheet.dart';
import '../../widgets/overlay_sheet.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import 'pinned_home_collections_screen.dart';
import 'sidebar_order_sheet.dart';

/// One place for everything that shapes Home and the sidebar: which Home rows
/// show and in what order, the sidebar's items, pinned collections and the
/// library list. Every change saves immediately.
class HomeSidebarSettingsScreen extends StatelessWidget {
  const HomeSidebarSettingsScreen({super.key, @visibleForTesting this.debugRows});

  /// Rows to show instead of reading them from [DiscoverProvider] (tests).
  final List<MediaHub>? debugRows;

  /// Home rows as the TV Home shows them, plus hidden ones, in the saved order.
  /// Continue Watching is synthesized by Home; only its key matters here.
  static List<MediaHub> currentRows(DiscoverProvider? discover, List<String> order) {
    if (discover == null) return const [];
    final rows = <MediaHub>[
      if (discover.onDeck.isNotEmpty)
        MediaHub(id: 'continue_watching', title: t.discover.continueWatching, type: 'mixed', items: const [], size: 0),
      ...discover.hubs.where((hub) => hub.items.isNotEmpty),
    ];
    return orderHomeRows(rows, order: order);
  }

  @override
  Widget build(BuildContext context) {
    final discover = context.watch<DiscoverProvider?>();
    return SettingsBuilder(
      prefs: const [SettingsService.homeRowOrder, SettingsService.homeRowHidden],
      builder: (context) {
        final settings = SettingsService.instance;
        final order = settings.read(SettingsService.homeRowOrder);
        final hidden = settings.read(SettingsService.homeRowHidden).toSet();
        final rows = debugRows == null ? currentRows(discover, order) : orderHomeRows(debugRows!, order: order);
        final sideNavigation = PlatformDetector.shouldUseSideNavigation(context);
        return SettingsPage(
          title: Text(t.settings.homeAndSidebar),
          children: [
            SettingsGroup(
              title: t.settings.homeRows,
              children: [
                if (rows.isEmpty)
                  Padding(padding: const EdgeInsets.all(16), child: Text(t.settings.homeRowsEmpty))
                else
                  for (final (index, row) in rows.indexed)
                    _HomeRowTile(
                      key: ValueKey(homeRowKey(row)),
                      row: row,
                      hidden: hidden.contains(homeRowKey(row)),
                      autofocus: index == 0,
                      onToggleHidden: () {
                        final key = homeRowKey(row);
                        final next = Set<String>.of(hidden);
                        if (!next.remove(key)) next.add(key);
                        settings.write(SettingsService.homeRowHidden, next.toList());
                      },
                      onMoveUp: index == 0
                          ? null
                          : () => settings.write(
                              SettingsService.homeRowOrder,
                              moveHomeRow(rows, order, index, index - 1),
                            ),
                      onMoveDown: index == rows.length - 1
                          ? null
                          : () => settings.write(
                              SettingsService.homeRowOrder,
                              moveHomeRow(rows, order, index, index + 1),
                            ),
                    ),
              ],
            ),
            SettingsGroup(
              title: t.settings.sidebarAndLibraries,
              children: [
                if (sideNavigation)
                  SettingNavigationTile(
                    icon: Symbols.tune_rounded,
                    title: t.settings.customizeSidebar,
                    subtitle: t.settings.customizeSidebarDescription,
                    onTap: () =>
                        OverlaySheetController.showAdaptive(context, builder: (_) => const SidebarOrderSheet()),
                  ),
                SettingNavigationTile(
                  icon: Symbols.push_pin_rounded,
                  title: t.settings.pinnedHomeCollections,
                  subtitle: t.settings.pinnedHomeCollectionsDescription,
                  destinationBuilder: (_) => const PinnedHomeCollectionsScreen(),
                ),
                SettingNavigationTile(
                  icon: Symbols.video_library_rounded,
                  title: t.libraries.manageLibraries,
                  subtitle: t.settings.manageLibrariesDescription,
                  onTap: () => showLibraryManagementSheet(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _HomeRowTile extends StatelessWidget {
  const _HomeRowTile({
    super.key,
    required this.row,
    required this.hidden,
    required this.onToggleHidden,
    this.onMoveUp,
    this.onMoveDown,
    this.autofocus = false,
  });

  final MediaHub row;
  final bool hidden;
  final VoidCallback onToggleHidden;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45);
    return ListTile(
      title: Text(row.title, style: hidden ? TextStyle(color: muted) : null),
      subtitle: Text(
        [if (row.serverName != null) row.serverName!, if (hidden) t.settings.hiddenFromHome].join(' · '),
        style: hidden ? TextStyle(color: muted) : null,
      ),
      trailing: FocusableActionBar(
        actions: [
          FocusableAction(
            icon: hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
            tooltip: hidden ? t.settings.showRowOnHome : t.settings.hideRowFromHome,
            autofocus: autofocus,
            onPressed: onToggleHidden,
          ),
          FocusableAction(icon: Symbols.arrow_upward_rounded, tooltip: t.discover.moveRowUp, onPressed: onMoveUp),
          FocusableAction(icon: Symbols.arrow_downward_rounded, tooltip: t.discover.moveRowDown, onPressed: onMoveDown),
        ],
      ),
    );
  }
}
