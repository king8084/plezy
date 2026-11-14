import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:plezy/utils/formatters.dart';

import '../../../media/media_item.dart';
import '../../../media/media_item_types.dart';
import '../../../media/ids.dart';
import '../../../media/media_rating.dart';
import '../../../utils/provider_extensions.dart';
import '../../optimized_media_image.dart';
import '../../media_rating_badge.dart';
import '../../../i18n/strings.g.dart';
import '../../../watch_together/widgets/watch_together_overlay.dart';
import '../../../watch_together/providers/watch_together_provider.dart';
import '../../app_bar_back_button.dart';
import '../../system_clock.dart';

/// Header layout style for video controls
enum VideoHeaderStyle {
  /// Multi-line: Series name on first line, episode info on second line
  multiLine,

  /// Single-line: All info combined with separators (for macOS)
  singleLine,
}

/// Shared header widget for video controls with back button and title.
///
/// Displays the video title with optional series/episode information.
/// Supports both single-line (macOS) and multi-line (other platforms) layouts.
class VideoControlsHeader extends StatelessWidget {
  final MediaItem metadata;
  final VideoHeaderStyle style;

  /// Optional trailing widget (e.g., track/chapter controls)
  final Widget? trailing;

  /// Optional callback for back button. If null, defaults to Navigator.pop(true).
  final VoidCallback? onBack;
  final VoidCallback? onCancelAutoHide;
  final VoidCallback? onStartAutoHide;

  /// Whether to show the system clock. Off for a portrait phone, where the
  /// header is too narrow to fit the clock beside the title and trailing
  /// controls.
  final bool showClock;
  final bool useTvArtwork;

  const VideoControlsHeader({
    super.key,
    required this.metadata,
    this.style = VideoHeaderStyle.multiLine,
    this.trailing,
    this.onBack,
    this.onCancelAutoHide,
    this.onStartAutoHide,
    this.showClock = true,
    this.useTvArtwork = false,
  });

  @override
  Widget build(BuildContext context) {
    final itemTitle = metadata.title ?? t.common.unknown;
    return Row(
      children: [
        AppBarBackButton(style: BackButtonStyle.video, onPressed: onBack ?? () => Navigator.of(context).pop(true)),
        const SizedBox(width: 16),
        Expanded(
          child: style == VideoHeaderStyle.singleLine
              ? _buildSingleLineTitle(itemTitle)
              : _buildMultiLineTitle(context, itemTitle),
        ),
        Selector<WatchTogetherProvider, bool>(
          selector: (_, p) => p.isInSession,
          builder: (context, inSession, child) {
            if (!inSession) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: WatchTogetherSessionIndicator(
                onCancelAutoHide: onCancelAutoHide,
                onStartAutoHide: onStartAutoHide,
              ),
            );
          },
        ),
        if (showClock)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: SystemClock(
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: .w500),
            ),
          ),
        ?trailing,
      ],
    );
  }

  Widget _buildSingleLineTitle(String itemTitle) {
    final seriesName = metadata.grandparentTitle ?? itemTitle;
    final hasEpisodeInfo = metadata.parentIndex != null && metadata.index != null;

    final List<String> parts = [seriesName];

    if (hasEpisodeInfo) {
      parts.add('S${metadata.parentIndex}E${metadata.index}');
      parts.add(itemTitle);
    }

    return Text(
      toBulletedString(parts),
      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: .w500),
      maxLines: 1,
      overflow: .ellipsis,
    );
  }

  Widget _buildMultiLineTitle(BuildContext context, String itemTitle) {
    final List<String> secondLineParts = [];

    if (metadata.parentIndex != null && metadata.index != null) {
      secondLineParts.add('S${metadata.parentIndex}');
      secondLineParts.add('E${metadata.index}');
      secondLineParts.add(itemTitle);
    }

    if (metadata.durationMs != null) {
      secondLineParts.add(formatDurationTextual(metadata.durationMs!));
    }

    final title = Text(
      metadata.grandparentTitle ?? itemTitle,
      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: .bold),
      maxLines: 1,
      overflow: .ellipsis,
    );
    final ratings = useTvArtwork && metadata.isEpisode ? mediaRatingsFor(metadata) : const <MediaRatingSource>[];
    // Prefer attributed IMDb. Jellyfin exposes its episode headline score as
    // audience; retain that same score used on Home without borrowing a series
    // rating or adding critic/other provider scores.
    final rating =
        ratings.where((r) => r.source == 'imdb').firstOrNull ??
        ratings.where((r) => r.source == 'audience' || r.source.isEmpty).firstOrNull;
    final episodeNumbers = metadata.parentIndex != null && metadata.index != null;
    return Column(
      crossAxisAlignment: .start,
      children: [
        if (useTvArtwork && metadata.isEpisode && metadata.clearLogoPath?.isNotEmpty == true)
          ClearLogoImage(
            client: context.tryGetMediaClientForServer(metadata.serverId == null ? null : ServerId(metadata.serverId!)),
            logoPath: metadata.clearLogoPath,
            width: 180,
            height: 36,
            fallbackWidth: 360,
            fallbackBuilder: (_) => title,
          )
        else
          title,
        if (secondLineParts.isNotEmpty)
          if (rating != null && episodeNumbers)
            Row(
              children: [
                Text(
                  '${toBulletedString(secondLineParts.take(2).toList())} · ',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                InlineRatingBadges(
                  ratings: [rating],
                  goldStars: true,
                  textStyle: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Flexible(
                  child: Text(
                    ' · ${toBulletedString(secondLineParts.skip(2).toList())}',
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                    maxLines: 1,
                    overflow: .ellipsis,
                  ),
                ),
              ],
            )
          else
            Text(
              toBulletedString(secondLineParts),
              style: const TextStyle(color: Colors.white70, fontSize: 14),
              maxLines: 1,
              overflow: .ellipsis,
            ),
      ],
    );
  }
}
