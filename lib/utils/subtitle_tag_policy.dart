import '../services/settings_service.dart';

/// Plain-text subtitle formats: they have no styles of their own beyond
/// italics/bold, so the viewer's subtitle settings should always decide size.
const _plainTextSubtitleCodecs = {'subrip', 'srt', 'webvtt', 'vtt', 'text', 'mov_text'};

/// mpv `sub-ass-override` for the selected subtitle track.
///
/// Some SRT files hard-code a size on every line (`<font size="71">` on the
/// English track of a whole show), which mpv obeys: the text then fills a
/// quarter of the screen. For plain-text tracks the inline tags are stripped,
/// so the viewer's own size, colour and font apply (italics go with them).
/// Styled ASS/SSA tracks (anime signs, karaoke) keep the viewer's chosen
/// policy, [preference].
String subAssOverrideForTrack(String? codec, SubAssOverride preference) {
  final plainText = codec != null && _plainTextSubtitleCodecs.contains(codec.toLowerCase());
  return plainText ? SubAssOverride.strip.name : preference.name;
}
