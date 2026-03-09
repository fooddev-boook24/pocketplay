import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import '../data/repositories/game_provider.dart';
import 'box_widgets.dart';
import 'shelf_engine.dart';
import '../data/models/game.dart';

// ══════════════════════════════════════════════════════════════════
// 寸法（shelf_engine.dart の kRowHeight=210 を本エリアの唯一の基準とする）
// ══════════════════════════════════════════════════════════════════
const double _kPilW    = 26.0;   // 縦柱の幅
const double _kTopH    = 20.0;   // 天板の高さ
const double _kLitH    =  6.0;   // 照明ラインの高さ
// 本エリア = kRowHeight = 210（shelf_engine.dartから）
const double _kBrdH    = 14.0;   // 棚板前面の高さ
const double _kRowH    = _kTopH + _kLitH + kRowHeight + _kBrdH; // 250pt

// 棚の区画幅（柱から次の柱まで）= 画面幅相当
const double _kBayW    = 390.0;  // 1区画の幅（スクリーン幅基準）

// 色（承認済み・変更禁止）
const _cPillarFace = Color(0xFFA26A34);
const _cBoardTop   = Color(0xFFA77239);
const _cBoardFront = Color(0xFFDDD4CB);
const _cLight      = Color(0xFFFDF5DE);

// POP styles
const _popStyles = {
  'FEATURED':    _PS('★\nおすすめ', Color(0xFFFFD800), Color(0xFF1A1000), Color(0xFFAA8800)),
  'STRATEGY':    _PS('戦略\nゲーム', Color(0xFF1E44CC), Colors.white,     Color(0xFF0E2A88)),
  '2 PLAYERS':   _PS('2人\n専用',   Color(0xFFD81830), Colors.white,     Color(0xFF8A0010)),
  'PARTY GAMES': _PS('パーティ',    Color(0xFF18AA44), Colors.white,     Color(0xFF0A6828)),
  'SMALL BOX':   _PS('小箱',        Color(0xFFFF7700), Colors.white,     Color(0xFFAA4400)),
  'NEW & HOT':   _PS('NEW\n話題作', Color(0xFFDD1020), Colors.white,     Color(0xFF880010)),
};
@immutable
class _PS {
  const _PS(this.text, this.bg, this.fg, this.dark);
  final String text; final Color bg, fg, dark;
}

// ══════════════════════════════════════════════════════════════════
// ShelfWall
// ══════════════════════════════════════════════════════════════════
class ShelfWall extends StatelessWidget {
  const ShelfWall({
    super.key,
    required this.games,
    required this.rows,
    required this.wallWidth,
    this.viewportOffset = 0.0,
    this.viewportWidth  = 390.0,
  });
  final List<Game> games;
  final List<ShelfRow> rows;
  final double wallWidth;
  final double viewportOffset;
  final double viewportWidth;

  // 柱の位置リスト（wallWidth全体に等間隔）
  List<double> _pillarPositions() {
    final positions = <double>[];
    double x = 0;
    while (x <= wallWidth) {
      positions.add(x);
      x += _kBayW;
    }
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    final camX = viewportOffset + viewportWidth / 2;
    final pillarXs = _pillarPositions();

    return SizedBox(
      width: wallWidth,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < rows.length; i++)
            _ShelfRow(
              games:     games,
              label:     rows[i].label,
              seed:      rows[i].seed,
              wallWidth: wallWidth,
              camX:      camX,
              pillarXs:  pillarXs,
            ),
          // 最終行の天板
          SizedBox(
            height: _kTopH + _kLitH,
            child: CustomPaint(
              painter: _ShelfPainter(
                wallWidth: wallWidth,
                camX:      camX,
                pillarXs:  pillarXs,
                topOnly:   true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// _ShelfRow
// ══════════════════════════════════════════════════════════════════
class _ShelfRow extends StatelessWidget {
  const _ShelfRow({
    required this.games,
    required this.label,
    required this.seed,
    required this.wallWidth,
    required this.camX,
    required this.pillarXs,
  });
  final List<Game> games;
  final String label;
  final int seed;
  final double wallWidth;
  final double camX;
  final List<double> pillarXs;

  @override
  Widget build(BuildContext context) {
    final boxes = ShelfLayoutEngine.generateRow(
      games: games, row: 0, wallWidth: wallWidth, rng: math.Random(seed),
    );
    final pops = ShelfLayoutEngine.generatePops(
      label: label, seed: seed, wallWidth: wallWidth,
    );

    return SizedBox(
      height: _kRowH,
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        // 棚構造
        Positioned.fill(
          child: CustomPaint(
            painter: _ShelfPainter(
              wallWidth: wallWidth,
              camX:      camX,
              pillarXs:  pillarXs,
              seed:      seed,
            ),
          ),
        ),
        // 本（各区画に配置）
        for (int i = 0; i < pillarXs.length - 1; i++)
          Positioned(
            left:   pillarXs[i] + _kPilW,
            width:  pillarXs[i + 1] - pillarXs[i] - _kPilW,
            top:    _kTopH + _kLitH,
            height: kRowHeight,
            child: ClipRect(child: Stack(
              clipBehavior: Clip.hardEdge,
              children: _buildBoxes(boxes, pillarXs[i], pillarXs[i + 1]),
            )),
          ),
        // POP
        for (int i = 0; i < pillarXs.length - 1; i++)
          Positioned(
            left:   pillarXs[i] + _kPilW,
            width:  pillarXs[i + 1] - pillarXs[i] - _kPilW,
            top:    _kTopH + _kLitH,
            height: kRowHeight + _kBrdH,
            child: Stack(
              clipBehavior: Clip.none,
              children: _buildPops(pops, pillarXs[i], pillarXs[i + 1]),
            ),
          ),
      ]),
    );
  }

  List<Widget> _buildBoxes(List<PlacedBox> boxes, double bayLeft, double bayRight) {
    final bayW = bayRight - bayLeft - _kPilW;
    final bayBoxes = boxes.where((b) => b.x >= 0 && b.x < bayW).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return bayBoxes.map((p) {
      if (p.pose == BoxPose.stack) {
        final top = kRowHeight - p.height - p.stackLayer * (p.height + 1.5);
        return Positioned(
          left: p.x, top: top.clamp(0.0, kRowHeight - p.height),
          width: p.width, height: p.height,
          child: StackBoxWidget(key: ValueKey('s${bayLeft.toInt()}_${p.x.toInt()}_${p.stackLayer}'), p: p),
        );
      }
      return Positioned(
        left: p.x, top: kRowHeight - p.height,
        width: p.width, height: p.height,
        child: p.pose == BoxPose.face
            ? FaceBoxWidget(key: ValueKey('f${bayLeft.toInt()}_${p.x.toInt()}'), p: p)
            : SpineBoxWidget(key: ValueKey('sp${bayLeft.toInt()}_${p.x.toInt()}'), p: p),
      );
    }).toList();
  }

  List<Widget> _buildPops(List<PlacedPop> pops, double bayLeft, double bayRight) {
    final bayW = bayRight - bayLeft - _kPilW;
    return pops.where((p) => p.x >= 0 && p.x < bayW).map((pop) {
      final sz = kPopSize[pop.type]!;
      final st = _popStyles[pop.label] ?? _popStyles['FEATURED']!;
      final left = (pop.x - sz.width / 2).clamp(4.0, bayW - sz.width - 4);
      final top  = kRowHeight - sz.height + (pop.type == PopType.plate ? -2.0 : 0.0);
      return Positioned(left: left, top: top,
          child: _PopWidget(pop: pop, style: st, sz: sz));
    }).toList();
  }
}

// ══════════════════════════════════════════════════════════════════
// _ShelfPainter
// ══════════════════════════════════════════════════════════════════
class _ShelfPainter extends CustomPainter {
  const _ShelfPainter({
    required this.wallWidth,
    required this.camX,
    required this.pillarXs,
    this.seed    = 0,
    this.topOnly = false,
  });
  final double wallWidth;
  final double camX;
  final List<double> pillarXs;
  final int seed;
  final bool topOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;
    final H = topOnly ? _kTopH + _kLitH : _kRowH;

    // 各区画の背景を描く
    for (int i = 0; i < pillarXs.length - 1; i++) {
      final bL = pillarXs[i] + _kPilW;
      final bR = pillarXs[i + 1];
      final bW = bR - bL;
      if (bW <= 0) continue;
      _drawBay(canvas, bL, bR, bW);
    }
    // 最右端の区画（最後の柱〜壁端）
    if (pillarXs.isNotEmpty) {
      final bL = pillarXs.last + _kPilW;
      if (bL < W) _drawBay(canvas, bL, W, W - bL);
    }

    // 柱を最前面に描く
    for (final px in pillarXs) {
      if (px + _kPilW < 0 || px > W) continue;
      _drawPillar(canvas, px, H);
    }
  }

  void _drawBay(Canvas canvas, double bL, double bR, double bW) {
    // 天板
    canvas.drawRect(
      Rect.fromLTWH(bL, 0, bW, _kTopH),
      Paint()..color = _cBoardTop,
    );
    // 天板 奥エッジ（暗い線）
    canvas.drawLine(Offset(bL, _kTopH - 0.5), Offset(bR, _kTopH - 0.5),
        Paint()..color = Colors.black.withOpacity(0.45)..strokeWidth = 1);

    // 照明ライン（天板の直下・細い白い線）
    canvas.drawRect(
      Rect.fromLTWH(bL, _kTopH, bW, _kLitH),
      Paint()..color = _cLight,
    );

    if (topOnly) return;

    // 後壁
    final wy = _kTopH + _kLitH;
    final wallRect = Rect.fromLTWH(bL, wy, bW, kRowHeight);
    canvas.drawRect(wallRect,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFA47850),
          Color(0xFF6E4820),
          Color(0xFF3A1E06),
          Color(0xFF180A02),
          Color(0xFF060100),
        ],
        stops: [0.0, 0.15, 0.45, 0.75, 1.0],
      ).createShader(wallRect));

    // 後壁 木目
    final rng = math.Random(seed ^ bL.toInt());
    final lp = Paint()..strokeWidth = 0.7;
    for (double x = bL; x < bR; x += 14 + rng.nextDouble() * 14) {
      lp.color = Colors.white.withOpacity(0.04);
      canvas.drawLine(Offset(x, wy),
          Offset(x + rng.nextDouble() * 3, wy + kRowHeight), lp);
    }

    // 接地影
    final sRect = Rect.fromLTWH(bL, wy + kRowHeight - 16, bW, 16);
    canvas.drawRect(sRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.bottomCenter, end: Alignment.topCenter,
          colors: [Colors.black.withOpacity(0.65), Colors.transparent],
        ).createShader(sRect));

    // 棚板前面
    final by = wy + kRowHeight;
    final brdRect = Rect.fromLTWH(bL, by, bW, _kBrdH);
    canvas.drawRect(brdRect,
      Paint()..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFFD8CEBE), Color(0xFFC0B09E)],
      ).createShader(brdRect));
  }

  void _drawPillar(Canvas canvas, double px, double H) {
    // 柱の中心X
    final pilCX = px + _kPilW / 2;

    // camXと柱中心の差 → 視線の向き
    // 正: 右から見ている → 左側明・右側暗
    // 負: 左から見ている → 右側明・左側暗
    final dX   = camX - pilCX;
    final norm = (dX / (_kBayW * 0.8)).clamp(-1.0, 1.0);

    // 正面色を視線方向に応じて左右で明暗を変える
    final leftColor  = Color.alphaBlend(
      Colors.white.withOpacity((norm > 0 ? norm * 0.15 : 0.0)), _cPillarFace);
    final rightColor = Color.alphaBlend(
      Colors.black.withOpacity((norm > 0 ? norm * 0.30 : 0.0)), _cPillarFace);
    final leftColor2  = Color.alphaBlend(
      Colors.black.withOpacity((norm < 0 ? (-norm) * 0.30 : 0.0)), _cPillarFace);
    final rightColor2 = Color.alphaBlend(
      Colors.white.withOpacity((norm < 0 ? (-norm) * 0.15 : 0.0)), _cPillarFace);

    final faceRect = Rect.fromLTWH(px, 0, _kPilW, H);
    canvas.drawRect(faceRect,
      Paint()..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          norm >= 0 ? leftColor  : leftColor2,
          norm >= 0 ? rightColor : rightColor2,
        ],
      ).createShader(faceRect));

    // 柱の左右エッジライン
    canvas.drawLine(Offset(px + 0.75, 0), Offset(px + 0.75, H),
        Paint()..color = Colors.white.withOpacity(0.20)..strokeWidth = 1.5);
    canvas.drawLine(Offset(px + _kPilW - 0.75, 0), Offset(px + _kPilW - 0.75, H),
        Paint()..color = Colors.black.withOpacity(0.30)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(_ShelfPainter o) =>
      o.camX != camX || o.seed != seed || o.topOnly != topOnly;
}

// ══════════════════════════════════════════════════════════════════
// POP Widget（変更なし）
// ══════════════════════════════════════════════════════════════════
class _PopWidget extends StatelessWidget {
  const _PopWidget({required this.pop, required this.style, required this.sz});
  final PlacedPop pop; final _PS style; final Size sz;
  @override
  Widget build(BuildContext context) {
    final rng = math.Random(pop.seed);
    final tilt = pop.type == PopType.lean
        ? (rng.nextBool() ? 1 : -1) * (0.12 + rng.nextDouble() * 0.14)
        : (rng.nextDouble() - 0.5) * (pop.type == PopType.plate ? 0.04 : 0.20);
    return Transform.rotate(
      angle: tilt,
      alignment: pop.type == PopType.plate ? Alignment.center : Alignment.bottomCenter,
      child: SizedBox(width: sz.width, height: sz.height,
        child: CustomPaint(
          painter: _PopPainter(style: style, type: pop.type),
          child: _popText(),
        )),
    );
  }
  Widget _popText() {
    final ip = pop.type == PopType.plate;
    return Padding(
      padding: EdgeInsets.fromLTRB(5, ip ? 4 : 10, 5, ip ? 4 : 8),
      child: Center(child: Text(
        ip ? style.text.replaceAll('\n', ' ') : style.text,
        textAlign: TextAlign.center, maxLines: ip ? 1 : 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: style.fg, fontSize: ip ? 11 : 12.0,
          fontWeight: FontWeight.w900, height: 1.4, letterSpacing: 0.5,
          shadows: [Shadow(color: Colors.black.withOpacity(0.22),
              offset: const Offset(0, 1), blurRadius: 3)]),
      )),
    );
  }
}

class _PopPainter extends CustomPainter {
  const _PopPainter({required this.style, required this.type});
  final _PS style; final PopType type;
  @override
  void paint(Canvas canvas, Size s) {
    switch (type) {
      case PopType.stand: _s(canvas, s);
      case PopType.plate: _p(canvas, s);
      case PopType.lean:  _l(canvas, s);
    }
  }
  void _s(Canvas c, Size s) { final b = RRect.fromRectAndRadius(Rect.fromLTWH(0,0,s.width,s.height*.92),const Radius.circular(3)); _sh(c,Path()..addRRect(b)); c.drawRRect(b,Paint()..color=style.bg); _gl(c,s,s.height*.92*.4); c.drawRect(Rect.fromLTWH(0,6,3.5,s.height*.92-12),Paint()..color=style.dark.withOpacity(.55)); _bd(c,Path()..addRRect(b)); c.drawPath(Path()..moveTo(s.width*.35,s.height*.92)..lineTo(s.width*.65,s.height*.92)..lineTo(s.width*.5,s.height)..close(),Paint()..color=style.dark); }
  void _p(Canvas c, Size s) { final b = RRect.fromRectAndRadius(Rect.fromLTWH(0,0,s.width,s.height),Radius.circular(s.height/2)); _sh(c,Path()..addRRect(b)); c.drawRRect(b,Paint()..color=style.bg); _gl(c,s,s.height*.55); _bd(c,Path()..addRRect(b)); c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0,0,6,s.height),Radius.circular(s.height/2)),Paint()..color=style.dark.withOpacity(.7)); }
  void _l(Canvas c, Size s) { final b = Path()..moveTo(3,1)..lineTo(s.width-2,0)..lineTo(s.width-1,s.height-2)..lineTo(1,s.height-1)..close(); _sh(c,b); c.drawPath(b,Paint()..color=style.bg); _gl(c,s,s.height*.38); for(double y=s.height*.65;y<s.height-4;y+=9) c.drawLine(Offset(6,y),Offset(s.width-6,y),Paint()..color=Colors.black.withOpacity(.08)..strokeWidth=.8); _bd(c,b); }
  void _sh(Canvas c, Path p) => c.drawPath(p.shift(const Offset(2.5,4)),Paint()..color=Colors.black.withOpacity(.3)..maskFilter=const MaskFilter.blur(BlurStyle.normal,8));
  void _gl(Canvas c, Size s, double h) => c.drawRect(Rect.fromLTWH(0,0,s.width,h),Paint()..shader=LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.white.withOpacity(.32),Colors.transparent]).createShader(Rect.fromLTWH(0,0,s.width,h)));
  void _bd(Canvas c, Path p) => c.drawPath(p,Paint()..color=Colors.black.withOpacity(.13)..style=PaintingStyle.stroke..strokeWidth=.9);
  @override bool shouldRepaint(_) => false;
}
