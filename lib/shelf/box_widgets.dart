import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/models/game.dart';
import 'shelf_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// GameImage — network → local asset → spine placeholder
// ─────────────────────────────────────────────────────────────────────────────
class GameImage extends StatelessWidget {
  const GameImage({
    super.key, required this.game, required this.fit,
    this.alignment = Alignment.center, this.width, this.height,
  });
  final Game game;
  final BoxFit fit;
  final Alignment alignment;
  final double? width, height;

  @override
  Widget build(BuildContext context) {
    final url   = game.imageUrl;
    final local = game.localAsset;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url, fit: fit, alignment: alignment,
        width: width, height: height,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => _localOrSwatch(local),
        errorWidget: (_, __, ___) => _localOrSwatch(local),
      );
    }
    return _localOrSwatch(local);
  }

  Widget _localOrSwatch(String? path) {
    if (path != null && path.isNotEmpty) {
      return Image.asset(path, fit: fit, alignment: alignment,
          width: width, height: height,
          errorBuilder: (_, __, ___) => _Swatch(game: game,
              w: width ?? 30, h: height ?? 90));
    }
    return _Swatch(game: game, w: width ?? 30, h: height ?? 90);
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.game, required this.w, required this.h});
  final Game game;
  final double w, h;

  Color _lt(Color c, double d) {
    final s = HSLColor.fromColor(c);
    return s.withLightness((s.lightness + d).clamp(0, 1)).toColor();
  }
  Color _dk(Color c, double d) {
    final s = HSLColor.fromColor(c);
    return s.withLightness((s.lightness - d).clamp(0, 1)).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final isSpine = w < 50;
    return Container(
      width: w, height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [_lt(game.spineColor, 0.10), game.spineColor,
            _dk(game.spineColor, 0.14)],
        ),
      ),
      child: isSpine
          ? Center(child: RotatedBox(quarterTurns: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Text(game.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: game.spineTextColor,
                        fontSize: (w * 0.28).clamp(6.0, 11.0),
                        fontWeight: FontWeight.w700)),
              )))
          : Align(alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent,
                      Colors.black.withOpacity(0.60)]),
                ),
                child: Text(game.title, textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white,
                        fontSize: (w * 0.09).clamp(8.0, 13.0),
                        fontWeight: FontWeight.w800, height: 1.2)),
              )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceBoxWidget
// ─────────────────────────────────────────────────────────────────────────────
class FaceBoxWidget extends StatelessWidget {
  const FaceBoxWidget({super.key, required this.p, this.onTap});
  final PlacedBox p;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Transform.rotate(
      angle: p.tilt,
      alignment: Alignment.bottomCenter,
      child: Stack(clipBehavior: Clip.none, children: [
        // Shadow
        Positioned(left: 3, top: 5, right: -5, bottom: -4,
          child: Container(decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.45),
              offset: const Offset(4, 10),
              blurRadius: 16, spreadRadius: -3)],
          ))),
        // Cover image
        ClipRRect(
          borderRadius: BorderRadius.circular(1.5),
          child: SizedBox(width: p.width, height: p.height,
            child: GameImage(game: p.game, fit: BoxFit.cover,
                width: p.width, height: p.height)),
        ),
        // Right depth strip
        Positioned(right: -3.5, top: 3, bottom: -3, width: 4,
          child: Container(
            decoration: BoxDecoration(color: _dk(p.game.spineColor, 0.24)))),
      ]),
    ),
  );

  Color _dk(Color c, double d) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - d).clamp(0, 1)).toColor();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SpineBoxWidget — shows real cover image clipped to spine width
// ─────────────────────────────────────────────────────────────────────────────
class SpineBoxWidget extends StatelessWidget {
  const SpineBoxWidget({super.key, required this.p, this.onTap});
  final PlacedBox p;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Transform.rotate(
      angle: p.tilt,
      alignment: Alignment.bottomCenter,
      child: SizedBox(width: p.width, height: p.height,
        child: Stack(children: [
          // Image as full background
          Positioned.fill(
            child: ClipRect(child: GameImage(game: p.game,
                fit: BoxFit.cover, alignment: Alignment.center,
                width: p.width, height: p.height)),
          ),
          // Dark gradient for readability
          Positioned(bottom: 0, left: 0, right: 0, height: p.height * 0.45,
            child: Container(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent,
                  Colors.black.withOpacity(0.65)]),
            ))),
          // Title
          Positioned(bottom: 2, left: 0, right: 0,
            child: Center(child: RotatedBox(quarterTurns: 3,
              child: Text(p.game.title, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white,
                      fontSize: (p.width * 0.25).clamp(5.5, 10.5),
                      fontWeight: FontWeight.w800,
                      shadows: const [Shadow(color: Colors.black,
                          offset: Offset(0, 1), blurRadius: 3)]))))),
          // Edge highlights
          Positioned(left: 0, top: 0, bottom: 0, width: 1.2,
              child: Container(color: Colors.white.withOpacity(0.18))),
          Positioned(right: 0, top: 0, bottom: 0, width: 2,
              child: Container(color: Colors.black.withOpacity(0.32))),
        ]),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// StackBoxWidget
// ─────────────────────────────────────────────────────────────────────────────
class StackBoxWidget extends StatelessWidget {
  const StackBoxWidget({super.key, required this.p, this.onTap});
  final PlacedBox p;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isTop = p.stackLayer == p.stackTotal - 1;
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: p.tilt, alignment: Alignment.center,
        child: Stack(children: [
          if (isTop)
            Positioned(left: 1, top: 2, right: -2, bottom: -3,
                child: Container(decoration: BoxDecoration(boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.28),
                      offset: const Offset(0, 3), blurRadius: 7)]))),
          Positioned.fill(child: ClipRect(child: GameImage(
              game: p.game, fit: BoxFit.cover,
              alignment: Alignment.topCenter))),
          Positioned(right: 0, top: 0, bottom: 0, width: 5,
              child: Container(decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    p.game.spineColor, _dk(p.game.spineColor, 0.28)])))),
          if (isTop)
            Positioned(top: 0, left: 0, right: 0, height: 1.5,
                child: Container(color: Colors.white.withOpacity(0.28))),
          Positioned(bottom: 0, left: 0, right: 0, height: 1.5,
              child: Container(color: Colors.black.withOpacity(0.28))),
        ]),
      ),
    );
  }

  Color _dk(Color c, double d) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness - d).clamp(0, 1)).toColor();
  }
}
