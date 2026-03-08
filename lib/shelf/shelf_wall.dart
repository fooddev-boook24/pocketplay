import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/repositories/game_provider.dart';
import 'box_widgets.dart';
import 'shelf_engine.dart';
import '../data/models/game.dart';

const _cBoardTop  = Color(0xFFD09248);
const _cBoardMid  = Color(0xFFB87830);
const _cBoardEdge = Color(0xFF7A4E18);
const _cPillarLit = Color(0xFFBE8838);
const _cPillarMid = Color(0xFF9A6220);
const _cPillarShd = Color(0xFF5A3A08);

// ─────────────────────────────────────────────────────────────────────────────
// Category POP data — color + text per category
// ─────────────────────────────────────────────────────────────────────────────
const _popColors = {
  'FEATURED':    _PopStyle(Color(0xFFFFD800), Color(0xFF1A1000), Color(0xFFAA8800), '★\nおすすめ'),
  'STRATEGY':    _PopStyle(Color(0xFF1E44CC), Colors.white,     Color(0xFF0E2A88), '戦略\nゲーム'),
  '2 PLAYERS':   _PopStyle(Color(0xFFD81830), Colors.white,     Color(0xFF8A0010), '2人\n専用'),
  'PARTY GAMES': _PopStyle(Color(0xFF18AA44), Colors.white,     Color(0xFF0A6828), 'パーティ'),
  'SMALL BOX':   _PopStyle(Color(0xFFFF7700), Colors.white,     Color(0xFFAA4400), '小箱'),
  'NEW & HOT':   _PopStyle(Color(0xFFDD1020), Colors.white,     Color(0xFF880010), 'NEW\n話題作'),
};

@immutable
class _PopStyle {
  const _PopStyle(this.bg, this.fg, this.dark, this.text);
  final Color bg, fg, dark;
  final String text;
}

// ─────────────────────────────────────────────────────────────────────────────
// ShelfWall
// ─────────────────────────────────────────────────────────────────────────────
class ShelfWall extends StatelessWidget {
  const ShelfWall({
    super.key, required this.games, required this.rows, required this.wallWidth,
  });
  final List<Game> games;
  final List<ShelfRow> rows;
  final double wallWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: wallWidth,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (int i = 0; i < rows.length; i++)
          _ShelfRow(
            games: games,
            label: rows[i].label,
            seed:  rows[i].seed,
            wallWidth: wallWidth,
          ),
        _EmptyShelfRow(),
      ]),
    );
  }
}

class _EmptyShelfRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const h = 90.0;
    return SizedBox(height: h + kBoardH + 4,
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned(left: kPillarW, right: kPillarW, top: 0, height: h,
            child: const _BackWall()),
        Positioned(left: 0, right: 0, top: h, height: kBoardH + 4,
            child: const _ShelfBoard()),
        Positioned(left: 0, top: 0, bottom: 0, width: kPillarW,
            child: const _Pillar(isLeft: true)),
        Positioned(right: 0, top: 0, bottom: 0, width: kPillarW,
            child: const _Pillar(isLeft: false)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ShelfRow — generates its own boxes + POPs
// ─────────────────────────────────────────────────────────────────────────────
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.games, required this.label,
    required this.seed,  required this.wallWidth,
  });
  final List<Game> games;
  final String label;
  final int seed;
  final double wallWidth;

  @override
  Widget build(BuildContext context) {
    final boxes = ShelfLayoutEngine.generateRow(
      games: games, row: 0, wallWidth: wallWidth,
      rng: math.Random(seed),
    );
    final pops = ShelfLayoutEngine.generatePops(
      label: label, seed: seed, wallWidth: wallWidth,
    );

    return SizedBox(
      height: kRowHeight + kBoardH + 4,
      child: Stack(clipBehavior: Clip.hardEdge, children: [

        // Back wall
        Positioned(left: kPillarW, right: kPillarW, top: 0, height: kRowHeight,
            child: const _BackWall()),

        // Boxes
        Positioned(
          left: kPillarW, right: kPillarW, top: 0, height: kRowHeight,
          child: ClipRect(child: Stack(
            clipBehavior: Clip.hardEdge,
            children: _buildBoxWidgets(boxes),
          )),
        ),

        // Shadow pool at base
        Positioned(
          left: kPillarW, right: kPillarW,
          top: kRowHeight - 32, height: 32,
          child: IgnorePointer(child: DecoratedBox(
            decoration: BoxDecoration(gradient: LinearGradient(
              begin: Alignment.bottomCenter, end: Alignment.topCenter,
              colors: [Colors.black.withOpacity(0.45), Colors.transparent],
            )),
          )),
        ),

        // POP cards — rendered ABOVE boxes, inside shelf area
        Positioned(
          left: kPillarW, right: kPillarW, top: 0, height: kRowHeight + kBoardH,
          child: Stack(
            clipBehavior: Clip.none,  // allow sticking above shelf top
            children: _buildPopWidgets(pops),
          ),
        ),

        // Shelf board
        Positioned(left: 0, right: 0, top: kRowHeight, height: kBoardH + 4,
            child: const _ShelfBoard()),

        // Pillars
        Positioned(left: 0, top: 0, bottom: 0, width: kPillarW,
            child: const _Pillar(isLeft: true)),
        Positioned(right: 0, top: 0, bottom: 0, width: kPillarW,
            child: const _Pillar(isLeft: false)),
      ]),
    );
  }

  List<Widget> _buildBoxWidgets(List<PlacedBox> boxes) {
    final sorted = [...boxes]..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return sorted.map((p) {
      if (p.pose == BoxPose.stack) {
        final top = kRowHeight - p.height - (p.stackLayer * (p.height + 1.5));
        return Positioned(
          left: p.x, top: top.clamp(0.0, kRowHeight - p.height),
          width: p.width, height: p.height,
          child: StackBoxWidget(key: ValueKey('s_${p.x.toInt()}_${p.stackLayer}'), p: p),
        );
      }
      return Positioned(
        left: p.x, top: kRowHeight - p.height,
        width: p.width, height: p.height,
        child: p.pose == BoxPose.face
            ? FaceBoxWidget(key: ValueKey('f_${p.x.toInt()}'), p: p)
            : SpineBoxWidget(key: ValueKey('sp_${p.x.toInt()}'), p: p),
      );
    }).toList();
  }

  List<Widget> _buildPopWidgets(List<PlacedPop> pops) {
    return pops.map((pop) {
      final sz = kPopSize[pop.type]!;
      final style = _popColors[pop.label] ?? _popColors['FEATURED']!;

      double left, top;
      switch (pop.type) {
        case PopType.stand:
          // Vertical card inserted between books, bottom on shelf
          left = pop.x - sz.width / 2;
          top  = kRowHeight - sz.height;
          break;
        case PopType.plate:
          // Wide flat card sitting on shelf board, in front of books
          left = pop.x - sz.width / 2;
          top  = kRowHeight - sz.height - 2; // sits just above board
          break;
        case PopType.lean:
          // Portrait card leaning against adjacent book
          left = pop.x - sz.width / 2;
          top  = kRowHeight - sz.height;
          break;
      }

      return Positioned(
        left: left.clamp(4.0, wallWidth - kPillarW * 2 - sz.width - 4),
        top: top,
        child: _PopWidget(pop: pop, style: style, sz: sz),
      );
    }).toList();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PopWidget — renders the physical POP card
// Each type has a distinct physical form
// ─────────────────────────────────────────────────────────────────────────────
class _PopWidget extends StatelessWidget {
  const _PopWidget({required this.pop, required this.style, required this.sz});
  final PlacedPop pop;
  final _PopStyle style;
  final Size sz;

  @override
  Widget build(BuildContext context) {
    final rng   = math.Random(pop.seed);

    // Tilt: stand/lean have more, plate has almost none
    final maxTilt = pop.type == PopType.plate ? 0.04 : 0.20;
    final tilt = (rng.nextDouble() - 0.5) * maxTilt;

    // lean type tilts more aggressively in one direction (leaning on a book)
    final finalTilt = pop.type == PopType.lean
        ? (rng.nextBool() ? 1 : -1) * (0.12 + rng.nextDouble() * 0.14)
        : tilt;

    return Transform.rotate(
      angle: finalTilt,
      alignment: pop.type == PopType.plate
          ? Alignment.center
          : Alignment.bottomCenter,
      child: SizedBox(
        width: sz.width, height: sz.height,
        child: CustomPaint(
          painter: _PopPainter(style: style, type: pop.type, sz: sz),
          child: _popText(sz),
        ),
      ),
    );
  }

  Widget _popText(Size sz) {
    final isPlate = pop.type == PopType.plate;
    return Padding(
      padding: EdgeInsets.fromLTRB(5, isPlate ? 4 : 10, 5, isPlate ? 4 : 8),
      child: Center(
        child: Text(
          isPlate ? style.text.replaceAll('\n', ' ') : style.text,
          textAlign: TextAlign.center,
          maxLines: isPlate ? 1 : 3,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.notoSansJp(textStyle: TextStyle(
            color: style.fg,
            fontSize: isPlate ? 11.0 : 12.0,
            fontWeight: FontWeight.w900,
            height: 1.4,
            letterSpacing: 0.5,
            shadows: [Shadow(
              color: Colors.black.withOpacity(0.22),
              offset: const Offset(0, 1), blurRadius: 3,
            )],
          )),
        ),
      ),
    );
  }
}

class _PopPainter extends CustomPainter {
  const _PopPainter({required this.style, required this.type, required this.sz});
  final _PopStyle style;
  final PopType type;
  final Size sz;

  @override
  void paint(Canvas canvas, Size s) {
    switch (type) {
      case PopType.stand:  _paintStand(canvas, s);  break;
      case PopType.plate:  _paintPlate(canvas, s);  break;
      case PopType.lean:   _paintLean(canvas, s);   break;
    }
  }

  // Stand: vertical card with small triangular bottom notch (like a real shelf talker)
  void _paintStand(Canvas canvas, Size s) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width, s.height * 0.92),
        const Radius.circular(3));

    _drawShadow(canvas, Path()..addRRect(body));
    canvas.drawRRect(body, Paint()..color = style.bg);
    _drawGloss(canvas, s, s.height * 0.92 * 0.40);
    _drawThicknessEdge(canvas, s, s.height * 0.92);
    _drawBorder(canvas, Path()..addRRect(body));

    // Small base tab
    final tab = Path()
      ..moveTo(s.width * 0.35, s.height * 0.92)
      ..lineTo(s.width * 0.65, s.height * 0.92)
      ..lineTo(s.width * 0.50, s.height)
      ..close();
    canvas.drawPath(tab, Paint()..color = style.dark);
  }

  // Plate: wide horizontal card with rounded ends, like a shelf edge label
  void _paintPlate(Canvas canvas, Size s) {
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width, s.height),
        Radius.circular(s.height / 2));

    _drawShadow(canvas, Path()..addRRect(body));
    canvas.drawRRect(body, Paint()..color = style.bg);
    _drawGloss(canvas, s, s.height * 0.55);
    _drawBorder(canvas, Path()..addRRect(body));

    // Left accent stripe
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, 6, s.height), Radius.circular(s.height / 2)),
      Paint()..color = style.dark.withOpacity(0.70),
    );
  }

  // Lean: portrait card, slightly worn corners (like a hand-written POP)
  void _paintLean(Canvas canvas, Size s) {
    // Slightly irregular corners for hand-cut feel
    final body = Path()
      ..moveTo(3, 1)
      ..lineTo(s.width - 2, 0)
      ..lineTo(s.width - 1, s.height - 2)
      ..lineTo(1, s.height - 1)
      ..close();

    _drawShadow(canvas, body);
    canvas.drawPath(body, Paint()..color = style.bg);
    _drawGloss(canvas, s, s.height * 0.38);

    // Handwritten ruled lines at bottom
    for (double y = s.height * 0.65; y < s.height - 4; y += 9) {
      canvas.drawLine(
        Offset(6, y), Offset(s.width - 6, y),
        Paint()..color = Colors.black.withOpacity(0.08)..strokeWidth = 0.8,
      );
    }
    _drawBorder(canvas, body);
  }

  void _drawShadow(Canvas canvas, Path path) {
    canvas.drawPath(path.shift(const Offset(2.5, 4.0)),
        Paint()..color = Colors.black.withOpacity(0.30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawPath(path.shift(const Offset(1, 1.5)),
        Paint()..color = Colors.black.withOpacity(0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
  }

  void _drawGloss(Canvas canvas, Size s, double h) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s.width, h),
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [Colors.white.withOpacity(0.32), Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, s.width, h)),
    );
  }

  void _drawThicknessEdge(Canvas canvas, Size s, double h) {
    canvas.drawRect(Rect.fromLTWH(0, 6, 3.5, h - 12),
        Paint()..color = style.dark.withOpacity(0.55));
  }

  void _drawBorder(Canvas canvas, Path path) {
    canvas.drawPath(path,
        Paint()..color = Colors.black.withOpacity(0.13)
          ..style = PaintingStyle.stroke..strokeWidth = 0.9);
  }

  @override bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Back wall — lit from pendant above
// ─────────────────────────────────────────────────────────────────────────────
class _BackWall extends StatelessWidget {
  const _BackWall();
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      colors: [
        Color(0xFF160800),
        Color(0xFF4A2608),
        Color(0xFF6E3C10),
        Color(0xFF5A3010),
        Color(0xFF1A0A02),
      ],
      stops: [0.0, 0.20, 0.48, 0.75, 1.0],
    )),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shelf board
// ─────────────────────────────────────────────────────────────────────────────
class _ShelfBoard extends StatelessWidget {
  const _ShelfBoard();
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min,
    children: [
      Expanded(child: Container(
        decoration: const BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [_cBoardTop, _cBoardMid],
        )),
        child: Stack(children: [
          Positioned(top: 0, left: 0, right: 0, height: 2.5,
            child: Container(decoration: BoxDecoration(gradient: LinearGradient(
              colors: [Colors.white.withOpacity(0.65),
                Colors.white.withOpacity(0.20)])))),
          Positioned.fill(child: CustomPaint(painter: _GrainPainter())),
        ]),
      )),
      Container(height: 4, color: _cBoardEdge),
    ],
  );
}

class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final p = Paint()..color = Colors.white.withOpacity(0.04)..strokeWidth = 0.5;
    for (double x = 14; x < s.width; x += 18 + (x.toInt() % 9)) {
      canvas.drawLine(Offset(x, 0), Offset(x + 4, s.height), p);
    }
  }
  @override bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Pillar
// ─────────────────────────────────────────────────────────────────────────────
class _Pillar extends StatelessWidget {
  const _Pillar({required this.isLeft});
  final bool isLeft;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(gradient: LinearGradient(
      begin: isLeft ? Alignment.centerLeft  : Alignment.centerRight,
      end:   isLeft ? Alignment.centerRight : Alignment.centerLeft,
      colors: const [_cPillarLit, _cPillarMid, _cPillarShd],
      stops: const [0.0, 0.55, 1.0],
    )),
    child: Stack(children: [
      Positioned(
        left: isLeft ? 0 : null, right: isLeft ? null : 0,
        top: 0, bottom: 0, width: 2,
        child: Container(color: Colors.white.withOpacity(isLeft ? 0.32 : 0.06))),
      Positioned(
        left: isLeft ? null : 0, right: isLeft ? 0 : null,
        top: 0, bottom: 0, width: 7,
        child: Container(decoration: BoxDecoration(gradient: LinearGradient(
          begin: isLeft ? Alignment.centerRight : Alignment.centerLeft,
          end:   isLeft ? Alignment.centerLeft  : Alignment.centerRight,
          colors: [Colors.black.withOpacity(0.25), Colors.transparent],
        )))),
    ]),
  );
}
