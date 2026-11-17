import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/i18n/strings.g.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/utils/platform_detector.dart';
import 'package:plezy/widgets/full_description_dialog.dart';

import '../test_helpers/media_items.dart';

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('remote reads the entire long overview and Close remains usable', (tester) async {
    final item = testMediaItem(
      id: 'e16',
      kind: MediaKind.episode,
      title: 'Basketball',
      grandparentTitle: 'Modern Family',
      parentIndex: 8,
      index: 16,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    FullDescriptionDialog(item: item, description: '${'Long episode overview. ' * 300}THE END'),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Modern Family · S8 E16 · Basketball'), findsOneWidget);
    final scroll = tester
        .widget<SingleChildScrollView>(
          find.descendant(of: find.byType(AlertDialog), matching: find.byType(SingleChildScrollView)).first,
        )
        .controller!;
    expect(scroll.position.maxScrollExtent, greaterThan(0));
    for (var i = 0; i < 70; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pumpAndSettle();
    expect(scroll.offset, scroll.position.maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(scroll.offset, lessThan(scroll.position.maxScrollExtent));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('short or hidden description keeps the fallback and close action', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: FullDescriptionDialog(item: testMediaItem(id: 'm'), description: null),
      ),
    );
    expect(find.text(t.discover.noDescription), findsOneWidget);
    expect(find.text(t.common.close), findsOneWidget);
  });
}
