import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/input_mode_tracker.dart';
import '../focus/key_event_utils.dart';
import '../focus/locked_hub_controller.dart';
import '../i18n/strings.g.dart';
import '../media/media_hub.dart';
import '../media/media_item.dart';
import '../services/settings_service.dart';
import '../utils/error_message_utils.dart';
import '../utils/provider_extensions.dart';
import '../widgets/app_bar_back_button.dart';
import '../widgets/overlay_sheet.dart';
import '../widgets/settings_builder.dart';
import '../widgets/tv_browse_rail.dart';
import '../widgets/tv_spotlight_scaffold.dart';
import 'libraries/state_messages.dart';

/// Favorites use the same focused-poster hero and card geometry as Home.
/// Show favorites stay show-level; no episode lookup supplies their metadata.
class SidebarFavoritesScreen extends StatefulWidget {
  const SidebarFavoritesScreen({super.key, required this.loadItems});
  final Future<List<MediaItem>> Function() loadItems;

  @override
  State<SidebarFavoritesScreen> createState() => _SidebarFavoritesScreenState();
}

class _SidebarFavoritesScreenState extends State<SidebarFavoritesScreen> {
  final _spotlight = TvSpotlightController();
  final _railKey = GlobalKey<TvBrowseRailState>();
  final _focusMemory = HubFocusMemory();
  final _backFocus = FocusNode(debugLabel: 'favorites_back');
  List<MediaHub> _hubs = const [];
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final items = await widget.loadItems();
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = null;
        _hubs = items.isEmpty
            ? const []
            : [
                MediaHub(
                  id: 'sidebar_favorites',
                  title: t.libraries.filterCategories.favorites,
                  type: 'mixed',
                  items: items,
                ),
              ];
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !(ModalRoute.isCurrentOf(context) ?? true)) return;
        if (_hubs.isEmpty) {
          _backFocus.requestFocus();
        } else {
          _railKey.currentState?.requestInitialFocus();
        }
      });
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = localizedLoadErrorMessage(error, stackTrace, context: t.libraries.filterCategories.favorites);
      });
    }
  }

  void _pop() {
    if (ModalRoute.isCurrentOf(context) ?? true) Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _spotlight.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return OverlaySheetHost(
      canPop: !InputModeTracker.shouldBlockSystemBack(context),
      onSystemBack: () {
        if (!BackKeyCoordinator.consumeIfHandled()) _pop();
      },
      child: Focus(
        onKeyEvent: (_, event) => handleBackKeyAction(event, _pop),
        child: Scaffold(
          body: SettingsBuilder(
            prefs: const [
              SettingsService.libraryDensity,
              SettingsService.gridSpacing,
              SettingsService.tvFullCardLayout,
              SettingsService.episodePosterMode,
              SettingsService.homeTextSize,
            ],
            builder: (context) => TvSpotlightScaffold(
              hubs: _hubs,
              spotlightListenable: _spotlight,
              resolveSpotlight: () => _spotlight.resolve(_hubs),
              resolveClient: (item) => item == null ? null : context.getMediaClientForItemOrNull(item),
              textScale: SettingsService.instance.read(SettingsService.homeTextSize) / 100,
              foreground: Stack(
                fit: StackFit.expand,
                children: [
                  if (_loading) const Center(child: CircularProgressIndicator()),
                  if (_error != null)
                    ErrorStateWidget(message: _error!, onRetry: () => unawaited(_load()), actionAutofocus: true),
                  if (!_loading && _error == null && _hubs.isEmpty)
                    EmptyStateWidget(message: t.hubDetail.noItemsFound, icon: Symbols.favorite_rounded),
                  if (_hubs.isNotEmpty)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: TvBrowseRail(
                        key: _railKey,
                        hubs: _hubs,
                        focusMemory: _focusMemory,
                        iconForHub: (_, _) => Symbols.favorite_rounded,
                        onFocusedItemChanged: _spotlight.select,
                        onRefresh: (_) => unawaited(_load()),
                        onNavigateUp: _backFocus.requestFocus,
                        onBack: _pop,
                        tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
                        widePosterScale: TvBrowseRailLayout.compactEpisodeThumbnailScale,
                      ),
                    ),
                  Positioned(
                    top: 0,
                    left: 0,
                    child: Focus(
                      canRequestFocus: false,
                      onKeyEvent: (_, event) {
                        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.arrowDown) {
                          _railKey.currentState?.requestFocus();
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: AppBarBackButton(focusNode: _backFocus, onPressed: _pop, style: BackButtonStyle.circular),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
