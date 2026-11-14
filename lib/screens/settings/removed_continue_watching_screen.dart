import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../providers/removed_continue_watching_provider.dart';
import '../../utils/error_message_utils.dart';
import '../../utils/provider_extensions.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/optimized_media_image.dart';
import '../../widgets/settings_page.dart';

class RemovedContinueWatchingScreen extends StatefulWidget {
  const RemovedContinueWatchingScreen({super.key});
  @override
  State<RemovedContinueWatchingScreen> createState() => _RemovedContinueWatchingScreenState();
}

class _RemovedContinueWatchingScreenState extends State<RemovedContinueWatchingScreen> {
  final Set<String> _restoring = {};

  Future<void> _restore(RemovedContinueWatchingEntry entry) async {
    if (!_restoring.add(entry.key)) return;
    setState(() {});
    try {
      await context.read<RemovedContinueWatchingProvider>().restore(entry.key);
    } catch (e) {
      if (mounted) showErrorSnackBar(context, t.messages.errorLoading(error: localizedErrorReason(e)));
    } finally {
      if (mounted) setState(() => _restoring.remove(entry.key));
    }
  }

  @override
  Widget build(BuildContext context) {
    final removed = context.watch<RemovedContinueWatchingProvider>();
    return SettingsPage(
      title: Text(t.settings.removedContinueWatching),
      children: [
        if (!removed.isInitialized)
          const Center(child: CircularProgressIndicator())
        else if (removed.entries.isEmpty)
          Padding(padding: const EdgeInsets.all(24), child: Text(t.hubDetail.noItemsFound))
        else
          for (final (index, entry) in removed.entries.indexed)
            FocusableListTile(
              key: ValueKey(entry.key),
              autofocus: index == 0,
              enabled: !_restoring.contains(entry.key),
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: OptimizedMediaImage.poster(
                  client: context.tryGetMediaClientForServer(serverIdOrNull(entry.item.serverId)),
                  imagePath: entry.item.thumbPath,
                  width: 54,
                  height: 80,
                ),
              ),
              title: Text(entry.item.displayTitle),
              subtitle: Text('${DateFormat.yMMMd().format(entry.removedAt)} · ${t.settings.restoreContinueWatching}'),
              trailing: const AppIcon(Symbols.restore_rounded),
              onTap: () => _restore(entry),
            ),
      ],
    );
  }
}
