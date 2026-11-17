import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/widgets/favorite_poster_border.dart';

import '../test_helpers/media_items.dart';

void main() {
  testWidgets('favorite decoration leaves poster size unchanged and reserves no extra space', (tester) async {
    final show = testMediaItem(id: 'show', kind: MediaKind.show);
    Future<void> pump(bool favorite, {bool representsShow = true}) => tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: FavoritePosterBorder(
            item: show.copyWith(isFavorite: favorite),
            representsShow: representsShow,
            borderRadius: 12,
            child: const SizedBox(width: 160, height: 240),
          ),
        ),
      ),
    );
    await pump(false);
    final size = tester.getSize(find.byType(FavoritePosterBorder));
    CustomPainter? painter() => tester
        .widget<CustomPaint>(find.descendant(of: find.byType(FavoritePosterBorder), matching: find.byType(CustomPaint)))
        .foregroundPainter;
    expect(painter(), isNull);
    await pump(true);
    expect(tester.getSize(find.byType(FavoritePosterBorder)), size);
    expect(painter(), isNotNull);
    await pump(true, representsShow: false);
    expect(painter(), isNull);
    expect(tester.getSize(find.byType(FavoritePosterBorder)), size);
  });
}
