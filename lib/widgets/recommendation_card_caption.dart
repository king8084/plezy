import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../i18n/app_locale_utils.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_rating.dart';
import '../models/catalog/catalog_item.dart';
import '../providers/catalog_sources_provider.dart';
import '../services/catalog/community_ratings.dart';
import '../theme/mono_tokens.dart';
import '../utils/formatters.dart';
import 'app_icon.dart';

/// A realized recommendation card shares the existing profile ratings cache
/// with Seerr/details. The IMDb score and its own votes always stay paired.
class RecommendationCardCaption extends StatefulWidget {
  const RecommendationCardCaption({super.key, required this.item});
  final CatalogItem item;
  @override
  State<RecommendationCardCaption> createState() => _RecommendationCardCaptionState();
}

class _RecommendationCardCaptionState extends State<RecommendationCardCaption> {
  CatalogSourcesProvider? _provider;
  List<Object> _sources = const [];
  String? _identity;
  Stream<List<MediaRatingSource>>? _ratings;

  void _bind(CatalogSourcesProvider? provider) {
    final sources = provider?.connectedSources ?? const [];
    if (identical(provider, _provider) &&
        _identity == widget.item.identityKey &&
        sources.length == _sources.length &&
        sources.indexed.every((entry) => identical(entry.$2, _sources[entry.$1]))) {
      return;
    }
    _provider = provider;
    _sources = sources;
    _identity = widget.item.identityKey;
    _ratings = provider?.communityRatingsForCatalogItem(widget.item);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bind(context.watch<CatalogSourcesProvider?>());
  }

  @override
  void didUpdateWidget(covariant RecommendationCardCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind(_provider);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<MediaRatingSource>>(
    key: ValueKey(_identity),
    stream: _ratings,
    builder: (context, snapshot) {
      final imdb = catalogImdbRating(widget.item, snapshot.data ?? const []);
      return RatingYearCaption(rating: imdb?.value, votes: imdb?.votes, year: widget.item.year);
    },
  );
}

/// The caption every "More like this" card shares: gold star, IMDb score,
/// vote count in a small box when known, then the year.
class RatingYearCaption extends StatelessWidget {
  const RatingYearCaption({super.key, this.rating, this.votes, this.year});
  final double? rating;
  final int? votes;
  final int? year;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontSize: 11, height: 1.1, color: tokens(context).textMuted);
    final rating = this.rating;
    if (rating == null || rating <= 0) return Text(year?.toString() ?? ' ', maxLines: 1, style: style);
    final votes = this.votes;
    final number = votes != null && votes > 0
        ? NumberFormat.compact(locale: LocaleSettings.currentLocale.intlLocaleName).format(votes)
        : null;
    return Row(
      children: [
        const AppIcon(Symbols.star_rounded, fill: 1, size: 13, color: Color(0xFFE6B95B)),
        const SizedBox(width: 3),
        Text(formatRating(rating), style: style),
        if (number != null) ...[
          const SizedBox(width: 5),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: tokens(context).text.withValues(alpha: 0.08),
                border: Border.all(color: tokens(context).text.withValues(alpha: 0.18)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                number,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style?.copyWith(fontSize: 10, height: 1),
              ),
            ),
          ),
        ],
        if (year != null) ...[
          const SizedBox(width: 5),
          Flexible(
            child: Text('· $year', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
        ],
      ],
    );
  }
}

/// A library title's caption: the server's own community rating (the
/// household's IMDb score) and year. Never an outside service's score.
class LibraryRatingCaption extends StatelessWidget {
  const LibraryRatingCaption({super.key, required this.item});
  final MediaItem item;

  /// Marks a library row whose cards use this caption.
  static const rawKey = 'plezyLibraryRatingCaption';

  /// IMDb vote count (from the household index's copy of IMDb's ratings).
  static const votesKey = 'plezyImdbVotes';

  static MediaItem mark(MediaItem item, {int? votes}) => item.kind == MediaKind.movie || item.kind == MediaKind.show
      ? item.copyWith(raw: {...?item.raw, rawKey: true, votesKey: ?votes})
      : item;

  static bool isMarked(MediaItem item) => item.raw?[rawKey] == true;

  @override
  Widget build(BuildContext context) => RatingYearCaption(
    rating: item.rating,
    votes: switch (item.raw?[votesKey]) {
      final int votes => votes,
      _ => null,
    },
    year: item.year,
  );
}
