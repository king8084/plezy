import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_stream.dart';
import '../media/media_version.dart';
import 'codec_utils.dart';
import 'resolution_label.dart';
import 'formatters.dart';

List<String> buildMediaQualityLabels(MediaItem item, {int versionIndex = 0}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null) return const [];

  final labels = <String>[];
  final resolution = _formatResolution(version);
  if (resolution != null) labels.add(resolution);

  final video = _firstStreamOfKind(version, MediaStreamKind.video);
  if (video?.dolbyVision == true) {
    labels.add(_formatDolbyVision(video!));
  } else if (video?.hdr == true) {
    labels.add('HDR');
  }

  final audio = _selectedAudioStream(version);
  final audioLabel = _formatAudio(audio);
  if (audioLabel != null) labels.add(audioLabel);

  return labels;
}

/// Resolution, video codec, and dynamic range — the picture half of
/// [buildMediaQualityLabels], for a line that names the audio track separately.
List<String> buildMediaVideoLabels(MediaItem item, {int versionIndex = 0, int? partIndex}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null) return const [];

  return _videoLabels(version, partIndex: partIndex);
}

/// File badges for browsing: the first version and exactly its first audio
/// track, irrespective of the server's selected/default audio flags. These
/// describe the source file, not the device's eventual HDMI output.
List<String> buildMediaTechnicalLabels(MediaItem item, {int versionIndex = 0}) {
  if (!item.isMovie && !item.isEpisode) return const [];
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null) return const [];
  return [
    ..._videoLabels(version, fullDolbyVisionName: true),
    ?_formatAudio(_firstStreamOfKind(version, MediaStreamKind.audio)),
    ?buildMediaFileSummaryLabel(item, versionIndex: versionIndex),
  ];
}

/// Size and overall bitrate for the selected file version.
String? buildMediaFileSummaryLabel(MediaItem item, {int versionIndex = 0}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null) return null;
  final size = buildMediaSizeLabel(item, versionIndex: versionIndex);
  final bitrate = version.bitrate;
  final labels = [
    if (size != null) size.replaceFirst('.0 MB', ' MB').replaceAll(' ', ''),
    if (bitrate != null && bitrate > 0) ByteFormatter.formatBitrate(bitrate).replaceAll(' ', ''),
  ];
  return labels.isEmpty ? null : labels.join(' | ');
}

List<String> _videoLabels(MediaVersion version, {int? partIndex, bool fullDolbyVisionName = false}) {
  final labels = <String>[];
  final resolution = _formatResolution(version);
  if (resolution != null) labels.add(resolution);

  final video = _firstStreamOfKind(version, MediaStreamKind.video, partIndex: partIndex);
  final codec = (video?.codec ?? version.videoCodec)?.trim();
  if (codec != null && codec.isNotEmpty) labels.add(CodecUtils.formatVideoCodec(codec));

  if (video?.dolbyVision == true) {
    labels.add(fullDolbyVisionName ? 'Dolby Vision' : _formatDolbyVision(video!));
  } else if (video?.hdr == true) {
    labels.add('HDR');
  }

  return labels;
}

String? buildMediaSizeLabel(MediaItem item, {int versionIndex = 0}) {
  final version = _selectedVersion(item.mediaVersions, versionIndex);
  if (version == null || version.parts.isEmpty) return null;

  var totalBytes = 0;
  for (final part in version.parts) {
    final sizeBytes = part.sizeBytes;
    if (sizeBytes == null || sizeBytes <= 0) return null;
    totalBytes += sizeBytes;
  }

  return ByteFormatter.formatBytes(totalBytes);
}

String _formatDolbyVision(MediaStream stream) {
  final profile = stream.dolbyVisionProfile;
  return profile == null || profile <= 0 ? 'DV' : 'DV P$profile';
}

MediaVersion? _selectedVersion(List<MediaVersion>? versions, int versionIndex) {
  if (versions == null || versions.isEmpty) return null;
  if (versionIndex >= 0 && versionIndex < versions.length) {
    return versions[versionIndex];
  }
  return versions.first;
}

String? _formatResolution(MediaVersion version) {
  // Re-evaluate dimensions even for cached Jellyfin rows whose old canonical
  // label was computed before cropped 4K widths were recognized.
  final dimensions = resolutionLabelFromDimensions(version.width, version.height);
  if (dimensions != null) return resolutionDisplayLabel(dimensions);
  final raw = version.videoResolution?.trim();
  if (raw != null && raw.isNotEmpty) return resolutionDisplayLabel(raw);
  return null;
}

MediaStream? _firstStreamOfKind(MediaVersion version, MediaStreamKind kind, {int? partIndex}) {
  if (partIndex != null && partIndex >= 0 && partIndex < version.parts.length) {
    for (final stream in version.parts[partIndex].streams) {
      if (stream.kind == kind) return stream;
    }
    return null;
  }
  for (final part in version.parts) {
    for (final stream in part.streams) {
      if (stream.kind == kind) return stream;
    }
  }
  return null;
}

MediaStream? _selectedAudioStream(MediaVersion version) {
  MediaStream? first;
  MediaStream? containerDefault;
  for (final part in version.parts) {
    for (final stream in part.streams) {
      if (stream.kind != MediaStreamKind.audio) continue;
      first ??= stream;
      if (stream.selected) return stream;
      if (stream.isDefault) containerDefault ??= stream;
    }
  }
  return containerDefault ?? first;
}

String? _formatAudio(MediaStream? stream) {
  if (stream == null) return null;

  final parts = <String>[];
  final codec = stream.codec?.trim();
  if (codec != null && codec.isNotEmpty) parts.add(_formatAudioCodec(codec));

  if (_isAtmos(stream)) {
    parts.add('Atmos');
  } else {
    final channels = CodecUtils.formatAudioChannels(stream.channels);
    if (channels != null) parts.add(channels);
  }

  return parts.isEmpty ? null : parts.join(' ');
}

String _formatAudioCodec(String codec) {
  return switch (codec.toLowerCase()) {
    'eac3' || 'ec3' => 'EAC3',
    'ac3' => 'AC3',
    _ => CodecUtils.formatAudioCodec(codec),
  };
}

bool _isAtmos(MediaStream stream) {
  return [
    stream.codec,
    stream.title,
    stream.displayTitle,
  ].whereType<String>().any((value) => value.toLowerCase().contains('atmos'));
}
