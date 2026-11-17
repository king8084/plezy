// Allow a small edge crop without dropping a file into the next lower tier.
const _resolutionCropTolerance = 16;

bool _nearResolutionDimension(int? value, int nominal) => value != null && value >= nominal - _resolutionCropTolerance;

/// Map a video stream height (pixels) onto the canonical resolution label
/// the rest of the app uses (`'4k'`, `'1080'`, `'720'`, `'480'`, or the raw
/// height for non-standard sizes). Returns `null` when [height] is null.
///
/// Plex hands the label back already in its `Media.videoResolution` field;
/// Jellyfin only gives raw pixel dimensions, which the Jellyfin mapper feeds
/// through [resolutionLabelFromDimensions] to produce the same shape.
String? resolutionLabelFromHeight(int? height) {
  if (height == null) return null;
  if (_nearResolutionDimension(height, 2160)) return '4k';
  if (_nearResolutionDimension(height, 1080)) return '1080';
  if (_nearResolutionDimension(height, 720)) return '720';
  if (_nearResolutionDimension(height, 480)) return '480';
  return height.toString();
}

/// Convenience overload that takes width + height. Width is considered first
/// for scope-cropped files, e.g. `3832x1600` should still be labeled `4k`.
/// Allow a small edge crop of up to 16 pixels on either dimension from the
/// nominal raster. This applies equally to 4K, 1080p, 720p and 480p tiers.
String? resolutionLabelFromDimensions(int? width, int? height) {
  if (_nearResolutionDimension(width, 3840) || _nearResolutionDimension(height, 2160)) return '4k';
  if (_nearResolutionDimension(width, 1920) || _nearResolutionDimension(height, 1080)) return '1080';
  if (_nearResolutionDimension(width, 1280) || _nearResolutionDimension(height, 720)) return '720';
  if (_nearResolutionDimension(width, 854) || _nearResolutionDimension(height, 480)) return '480';
  return resolutionLabelFromHeight(height);
}

final _numericResolutionValue = RegExp(r'^(\d+)(?:p)?$');

/// Format a canonical resolution label — or a raw numeric height, with or
/// without a trailing `p` — for display: `'1080'`/`'1080p'` → `'1080p'`,
/// `'4k'`/`'uhd'`/heights ≥ 2160 → `'4K'`, `'sd'` → `'SD'`; anything else is
/// uppercased verbatim.
String resolutionDisplayLabel(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == '4k' || normalized == 'uhd') return '4K';
  if (normalized == 'sd') return 'SD';

  final numeric = _numericResolutionValue.firstMatch(normalized);
  if (numeric != null) {
    final height = int.tryParse(numeric.group(1)!);
    if (height != null && height >= 2160) return '4K';
    return '${numeric.group(1)}p';
  }

  return value.trim().toUpperCase();
}
