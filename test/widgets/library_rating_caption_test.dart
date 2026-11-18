import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:plezy/widgets/recommendation_card_caption.dart';

import '../test_helpers/media_items.dart';

void main() {
  testWidgets('library cards show the server rating and the year, never an outside score', (tester) async {
    final movie = LibraryRatingCaption.mark(testMediaItem(id: 'm1', kind: MediaKind.movie, rating: 8.8, year: 2010));
    expect(LibraryRatingCaption.isMarked(movie), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(body: LibraryRatingCaption(item: movie)),
      ),
    );

    expect(find.text('8.8'), findsOneWidget);
    expect(find.text('· 2010'), findsOneWidget);
  });

  testWidgets('no rating falls back to the year alone', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(MonoPalette.dark),
        home: Scaffold(body: const RatingYearCaption(year: 1999)),
      ),
    );
    expect(find.text('1999'), findsOneWidget);
  });

  test('only movies and shows are marked', () {
    final episode = LibraryRatingCaption.mark(testMediaItem(id: 'e1', kind: MediaKind.episode));
    expect(LibraryRatingCaption.isMarked(episode), isFalse);
  });
}
