import 'package:flutter/material.dart';

import '../utils/text_measure_cache.dart';

/// A single row of source-file tags. Omit whole trailing badges when space is
/// tight, rather than wrapping into the synopsis or shrinking the other text.
class MediaTechnicalBadges extends StatelessWidget {
  const MediaTechnicalBadges({super.key, required this.labels, this.scale = 1, this.textScale = 1});

  final List<String> labels;
  final double scale;
  final double textScale;

  static double rowHeight(double scale, double textScale) => (16 * textScale * 1.3 + 8) * scale;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: Colors.white, fontSize: 16 * scale * textScale, height: 1.3, fontWeight: .w600);
    final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
    final gap = 6 * scale;
    final horizontalPadding = 10 * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final badges = <Widget>[];
        var usedWidth = 0.0;
        for (final label in labels) {
          final width =
              cachedSingleLineTextSize(
                label,
                style: effectiveStyle,
                textScaler: MediaQuery.textScalerOf(context),
                textDirection: Directionality.of(context),
              ).width +
              2 * horizontalPadding +
              2 * scale;
          final nextWidth = usedWidth + (badges.isEmpty ? 0 : gap) + width;
          if (nextWidth > constraints.maxWidth) break;
          if (badges.isNotEmpty) badges.add(SizedBox(width: gap));
          badges.add(
            Container(
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 3 * scale),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(20 * scale),
                border: Border.all(color: Colors.white.withValues(alpha: 0.22), width: scale),
              ),
              child: Text(label, style: style, maxLines: 1),
            ),
          );
          usedWidth = nextWidth;
        }
        return Row(mainAxisSize: .min, children: badges);
      },
    );
  }
}
