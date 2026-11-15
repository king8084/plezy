import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_server_client.dart';
import '../../providers/discover_provider.dart';
import '../../services/home_pinned_collections.dart';
import '../../services/settings_service.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/provider_extensions.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/settings_builder.dart';
import '../../widgets/settings_page.dart';

/// Saved ids stay manageable even after a collection is deleted or its server
/// goes offline. A failed Home fetch never silently removes the owner's pin.
class PinnedHomeCollectionsScreen extends StatefulWidget {
  const PinnedHomeCollectionsScreen({super.key});

  @override
  State<PinnedHomeCollectionsScreen> createState() => _PinnedHomeCollectionsScreenState();
}

class _PinnedHomeCollectionsScreenState extends State<PinnedHomeCollectionsScreen> {
  bool _saving = false;

  Future<void> _remove(String key) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final settings = SettingsService.instance;
      final pins = List<String>.of(settings.read(SettingsService.homePinnedCollections))..remove(key);
      await settings.write(SettingsService.homePinnedCollections, pins);
      if (mounted) {
        final discover = context.read<DiscoverProvider?>();
        if (discover != null) unawaited(discover.load());
      }
    } catch (error) {
      if (mounted) showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(error)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SettingsBuilder(
    prefs: const [SettingsService.homePinnedCollections, SettingsService.homePinnedCollectionMetadata],
    builder: (context) {
      final settings = SettingsService.instance;
      final pins = settings.read(SettingsService.homePinnedCollections);
      final metadata = readPinnedHomeCollectionMetadata(settings);
      return SettingsPage(
        title: Text(t.settings.pinnedHomeCollections),
        children: [
          if (pins.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Text(t.hubDetail.noItemsFound)),
          for (final (index, key) in pins.indexed)
            Builder(
              builder: (context) {
                final pin = parseHomePinnedCollectionKey(key);
                final client = pin == null ? null : context.tryGetMediaClientForServer(ServerId(pin.serverId));
                final cache = client == null ? null : metadata['${client.cacheServerId}\u001f$key'];
                final title = (cache?['item'] as Map<String, dynamic>?)?['title'] as String?;
                return FocusableListTile(
                  key: ValueKey(key),
                  autofocus: index == 0,
                  enabled: !_saving,
                  leading: const AppIcon(Symbols.push_pin_rounded),
                  title: Text(title ?? t.settings.pinnedCollectionUnavailable),
                  subtitle: Text(t.mediaMenu.removeFromHome),
                  trailing: const AppIcon(Symbols.close_rounded),
                  onTap: () => _remove(key),
                );
              },
            ),
        ],
      );
    },
  );
}
