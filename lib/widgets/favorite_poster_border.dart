import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/media_item.dart';
import '../media/catalog_item_ref.dart';
import '../media/media_item_types.dart';
import '../providers/multi_server_provider.dart';
import '../services/favorite_status.dart';
import '../utils/provider_extensions.dart';

/// Paint-only decoration: the approved poster geometry and focus border stay
/// independent. A static metallic highlight avoids a repeating animation on TV.
class FavoritePosterBorder extends StatefulWidget {
  const FavoritePosterBorder({
    super.key,
    required this.item,
    required this.child,
    required this.borderRadius,
    this.representsShow = true,
  });

  final MediaItem item;
  final Widget child;
  final double borderRadius;
  final bool representsShow;

  @override
  State<FavoritePosterBorder> createState() => _FavoritePosterBorderState();
}

class _FavoritePosterBorderState extends State<FavoritePosterBorder> {
  FavoriteStatus? _status;
  Object? _session;
  String? _targetId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.watch<MultiServerProvider?>();
    _bind();
  }

  @override
  void didUpdateWidget(FavoritePosterBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  void _bind() {
    final item = widget.item;
    final id = widget.representsShow && (item.isShow || item.isEpisode) ? FavoriteStatus.targetId(item) : null;
    final client = id == null || item.isCatalogItem ? null : context.getMediaClientForItemOrNull(item);
    final status = client?.capabilities.userFavorites == true ? FavoriteStatus.forClient(client!) : null;
    final session = status == null ? null : client!.authenticationSessionId;
    final changed = !identical(_session, session) || _targetId != id;
    if (!identical(status, _status)) {
      _status?.removeListener(_changed);
      _status = status;
      _status?.addListener(_changed);
    }
    _session = session;
    _targetId = id;
    if (changed && item.isEpisode && status != null) {
      // A parent lookup is shared across visible cards and menus. It never
      // delays first paint, focus movement or navigation.
      unawaited(status.resolve(client!, item));
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _status?.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final id = _targetId;
    final fallback = widget.item.isShow ? widget.item.isFavorite : null;
    final favorite = id != null && (_status?.value(id, fallback: fallback) ?? fallback) == true;
    return CustomPaint(
      foregroundPainter: favorite ? _GoldPosterPainter(widget.borderRadius) : null,
      child: widget.child,
    );
  }
}

class _GoldPosterPainter extends CustomPainter {
  const _GoldPosterPainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(1.3);
    final shape = RRect.fromRectAndRadius(rect, Radius.circular((radius - 1.3).clamp(0, radius)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFAA833C), Color(0xFFF0D69A), Color(0xFFBE9850), Color(0xFF957039)],
        stops: [0, 0.25, 0.6, 1],
      ).createShader(rect);
    canvas.drawRRect(shape, paint);
  }

  @override
  bool shouldRepaint(_GoldPosterPainter oldDelegate) => radius != oldDelegate.radius;
}
