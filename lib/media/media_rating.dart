/// One attributed score for a media item.
///
/// Backends routinely return several: Plex's `/library/metadata/{id}` carries
/// an IMDb score next to both Rotten Tomatoes panels and TMDB, Simkl carries
/// Simkl/IMDb/MAL side by side, Jellyfin carries a community score next to a
/// Tomatometer. `MediaItem.rating` keeps the backend's headline number; this
/// list keeps every score with attribution so the UI can badge and label them.
///
/// Serialization is hand-written rather than `json_serializable` because
/// catalog objects round-trip through `MediaItem.raw` maps rather than a
/// generated codec.
library;

class MediaRatingSource {
  /// Stable, lowercase source key: `imdb`, `tmdb`, `rottenTomatoesCritic`,
  /// `rottenTomatoesAudience`, `metacritic`, `letterboxd`, `simkl`, `mal`,
  /// `anilist`, `trakt`, `critic`, `audience`. Rendered through a label map,
  /// never raw.
  final String source;

  /// Normalized to 0-10 by the mapper, matching `MediaItem.rating`. Percentage
  /// sources (Rotten Tomatoes, TMDB, Trakt, AniList) are rendered back as
  /// `value * 10`%, the Metascore as `value * 10`, Letterboxd as `value / 2`
  /// stars.
  final double value;

  /// How many users the score is based on, when the backend says.
  final int? votes;

  const MediaRatingSource({required this.source, required this.value, this.votes});

  /// A score a provider reported on [source]'s own scale — 10 for IMDb, 100
  /// for percentages and the Metascore, 5 for Letterboxd stars — moved onto
  /// the 0-10 scale. Null when it is no score: missing, zero (providers write
  /// 0 for "not rated yet"), beyond [scale], or resting on no votes.
  static MediaRatingSource? fromScale(String source, num? value, {required num scale, num? votes}) {
    if (value == null || value.isNaN || value <= 0 || value > scale) return null;
    if (votes != null && votes <= 0) return null;
    return MediaRatingSource(source: source, value: value * 10 / scale, votes: votes?.toInt());
  }

  Map<String, Object?> toJson() => {'source': source, 'value': value, if (votes != null) 'votes': votes};

  static MediaRatingSource? fromJson(Map<String, Object?> json) {
    final source = json['source'] as String?;
    final value = (json['value'] as num?)?.toDouble();
    if (source == null || value == null) return null;
    return MediaRatingSource(source: source, value: value, votes: json['votes'] as int?);
  }
}

/// One badge per source, with IMDb first regardless of arrival/server order.
/// Once IMDb is attributed, a bare server headline adds no identifiable score.
List<MediaRatingSource> orderedMediaRatings(Iterable<MediaRatingSource> ratings) {
  const order = [
    'imdb',
    'rottenTomatoesCritic',
    'rottenTomatoesAudience',
    'tmdb',
    'metacritic',
    'letterboxd',
    'trakt',
    'simkl',
    'mal',
    'anilist',
  ];
  String identity(String source) => source == 'rottenTomatoes' ? 'rottenTomatoesCritic' : source;
  final unique = <String, MediaRatingSource>{};
  for (final rating in ratings) {
    unique.putIfAbsent(identity(rating.source), () => rating);
  }
  if (unique['imdb'] case final imdb?) {
    unique.remove('');
    final audience = unique['audience'];
    if (audience != null && (audience.value - imdb.value).abs() < 0.0001) unique.remove('audience');
  }
  final entries = unique.entries.toList();
  final displayOrder = [
    'imdb',
    // Jellyfin's unbranded community score uses the same gold star in TV
    // metadata. Keep that star before a Tomatometer without relabelling its
    // unknown provenance or changing Plex's generic critic/audience order.
    if (unique.keys.any((source) => source.startsWith('rottenTomatoes'))) ...['', 'audience'],
    ...order.skip(1),
  ];
  int rank(String source) {
    final index = displayOrder.indexOf(source);
    return index < 0 ? displayOrder.length : index;
  }

  // Preserve input order for equally ranked, unattributed sources.
  return [
    for (final key in displayOrder)
      if (unique.containsKey(key)) unique[key]!,
    for (final entry in entries)
      if (rank(entry.key) == displayOrder.length) entry.value,
  ];
}
