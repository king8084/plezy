import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/media/media_rating.dart';
import 'package:plezy/models/catalog/catalog_item.dart';
import 'package:plezy/providers/catalog_sources_provider.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/recommendation_card_caption.dart';
import 'package:provider/provider.dart';

class _RatingSource extends CatalogSourcesProvider {
  final result = Completer<List<MediaRatingSource>>();
  int loads = 0;
  @override
  Stream<List<MediaRatingSource>> communityRatingsForCatalogItem(CatalogItem item) {
    loads++;
    return Stream.fromFuture(result.future);
  }
}

void main() {
  testWidgets('IMDb enrichment replaces no score, never substitutes Simkl/TMDB or their votes', (tester) async {
    final source = _RatingSource();
    addTearDown(source.dispose);
    const item = CatalogItem(
      source: CatalogSourceId.seerr,
      kind: MediaKind.show,
      title: 'Show',
      year: 2020,
      rating: 9.9,
      votes: 999999,
      ids: CatalogItemIds(tmdb: 1),
      ratings: [MediaRatingSource(source: 'simkl', value: 9.1, votes: 100)],
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<CatalogSourcesProvider>.value(
        value: source,
        child: MaterialApp(
          theme: monoTheme(MonoPalette.dark),
          home: const Scaffold(
            body: SizedBox(width: 160, child: RecommendationCardCaption(item: item)),
          ),
        ),
      ),
    );
    expect(find.text('9.9'), findsNothing);
    expect(find.text('9.1'), findsNothing);
    source.result.complete([const MediaRatingSource(source: 'imdb', value: 8.5, votes: 12500)]);
    await tester.pumpAndSettle();
    expect(find.text('8.5'), findsOneWidget);
    expect(find.text('12.5K'), findsOneWidget);
    expect(find.textContaining('IMDb'), findsNothing);
    expect(find.textContaining('votes'), findsNothing);
    expect(source.loads, 1);
    expect(tester.takeException(), isNull);
  });

  for (final width in [80.0, 120.0, 180.0]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('rating and vote box fit width $width, labels $scale', (tester) async {
        const item = CatalogItem(
          source: CatalogSourceId.simkl,
          kind: MediaKind.show,
          title: 'Show',
          ids: CatalogItemIds(simkl: 1),
          ratings: [MediaRatingSource(source: 'imdb', value: 8.5, votes: 1250000)],
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: monoTheme(MonoPalette.dark),
            home: Scaffold(
              body: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: width,
                    child: const RecommendationCardCaption(item: item),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('8.5'), findsOneWidget);
        expect(find.text('1.25M'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
