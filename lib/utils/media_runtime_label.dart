import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import 'formatters.dart';

/// The TV browsing runtime slot describes the current resume point. File Info
/// continues to use the source duration, and series keep their nominal runtime.
String? mediaRuntimeLabel(MediaItem item) {
  final duration = item.durationMs;
  if (duration == null) return null;
  if (!(item.isEpisode || item.isMovie) || !item.hasActiveProgress) {
    return formatDurationTextual(duration);
  }

  final minutes = ((duration - item.viewOffsetMs!) / Duration.millisecondsPerMinute).ceil();
  if (minutes < 60) return t.discover.minutesLeft(minutes: minutes);
  return t.discover.durationLeft(duration: formatDurationTextual(minutes * Duration.millisecondsPerMinute));
}
