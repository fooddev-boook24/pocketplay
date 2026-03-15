import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import '../data/repositories/game_provider.dart';
import 'box_widgets.dart';
import 'shelf_engine.dart';
import '../data/models/game.dart';

// ══════════════════════════════════════════════════════════════════
// librub実測値（DPR=2、画像1450x740px）
//
// 柱正面幅:   24pt  (49px÷2)  ← kPillarW=26ptに近い→26pt使用
// 天板高さ:   17pt  (33px÷2)
// LEDライン:   3pt  (5px÷2)   ← 非常に細い
// LEDグロー:   4pt  (前後合計)
// 横柱底面:   8pt   (後壁と同化するグラデ)
// 棚板計:     32pt
//
// 天板色: RGB(165,110,54)=#A56E36 均一（木目テクスチャ由来の揺らぎ）
// LED色:  RGB(255,249,227)=#FFF9E3 白ピーク
// 前エッジ: y=47〜50 RGB(171,129,88)=#AB8158 ← グロー裾野と一体
// 横柱底面: RGB(143,99,64)=#8F6340 → 急速に暗く → 後壁色へ
//
// 柱正面グラデ:
//   x=0〜48（24pt）で RGB(175,140,59)→RGB(161,101,51)
//   右端ほど少し暗い（黄み→茶色）
//
// 側面（初期表示で見える）:
//   librubでは初期表示でも約20pt側面が見える
//   色: RGB(97,62,34)=#613E22（天板より大幅に暗い）
//   接合部エッジ: RGB(32,25,17)≈黒（強い影）
//
// レイヤー順（奥→手前）:
//   1. _BackAndSidePainter  後壁 + 柱側面
//   2. _BooksLayer          本
//   3. _ShelfBoardPainter   棚板
//   4. _PillarFacePainter   柱正面
// ══════════════════════════════════════════════════════════════════

const double _kTopH       = kPillarW; // ① 上面：縦柱と同じ26pt（固定）
const double _kFaceH      =  6.0;     // ② 前面エッジ
const double _kLightH     =  5.0;     // ③ LED
const double _kGlowH      =  4.0;     // LEDグロー
const double _kUndersideH =  8.0;     // 後壁なじみ（_BackAndSideと共用）
const double _kShelfH     = _kTopH + _kFaceH + _kLightH + _kGlowH + _kUndersideH; // 49pt

const double _kPilW  = kPillarW; // 26pt（shelf_engine定数）
const double _kPilSD = 60.0;     // 柱側面MAX幅（拡大）

// POP スタイル
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
  final String text;
  final Color bg, fg, dark;
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
    this.viewportScale  = 1.0,
  });
  final List<Game>     games;
  final List<ShelfRow> rows;
  final double         wallWidth;
  final double         viewportOffset;
  final double         viewportWidth;
  final double         viewportScale;

  @override
  Widget build(BuildContext context) {
    final nRows = rows.length.clamp(0, 4);
    final bayW  = wallWidth / 4;
    final pilXs = [
      0.0,
      bayW,
      bayW * 2,
      bayW * 3,
      wallWidth - _kPilW,
    ];

    // ① 上面は固定（縦柱と同じ太さ、scaleで変わらない）
    const topH   = _kTopH;
    const lightH = _kLightH;
    const shelfH = _kShelfH;

    final totalH = shelfH * (nRows + 1) + kRowHeight * nRows;
    final camX   = viewportOffset + viewportWidth / 2;

    return SizedBox(
      width:  wallWidth,
      height: totalH,
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _BackAndSidePainter(
              wallW: wallWidth, totalH: totalH, nRows: nRows,
              pilXs: pilXs, bayW: bayW, camX: camX,
              shelfH: shelfH,
            ),
          ),
        ),
        for (int i = 0; i <= nRows; i++)
          Positioned(
            left: 0, right: 0,
            top:    (shelfH + kRowHeight) * i,
            height: shelfH,
            child: CustomPaint(
              painter: _ShelfBoardPainter(
                wallW: wallWidth, pilXs: pilXs,
                topH: topH, lightH: lightH,
              ),
            ),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: _ShelfUndersidePainter(
              wallW: wallWidth, totalH: totalH,
              pilXs: pilXs, bayW: bayW, camX: camX,
              shelfH: shelfH,
            ),
          ),
        ),
        for (int i = 0; i < nRows; i++)
          Positioned(
            left: 0, right: 0,
            top:    shelfH + (shelfH + kRowHeight) * i,
            height: kRowHeight,
            child: _BooksLayer(
              games: games, label: rows[i].label, seed: rows[i].seed,
              wallW: wallWidth, pilXs: pilXs,
            ),
          ),
        Positioned.fill(
          child: CustomPaint(
            painter: _PillarFacePainter(totalH: totalH, pilXs: pilXs),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 1. _BackAndSidePainter
// ══════════════════════════════════════════════════════════════════
class _BackAndSidePainter extends CustomPainter {
  const _BackAndSidePainter({
    required this.wallW, required this.totalH, required this.nRows,
    required this.pilXs, required this.bayW,   required this.camX,
    required this.shelfH,
  });
  final double wallW, totalH, bayW, camX, shelfH;
  final int    nRows;
  final List<double> pilXs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, wallW, totalH),
      Paint()..color = const Color(0xFF100602),
    );

    for (int i = 0; i < nRows; i++) {
      final top  = shelfH + (shelfH + kRowHeight) * i;
      final rect = Rect.fromLTWH(0, top, wallW, kRowHeight);

      // 後壁グラデ: 棚板直下が明るく、本エリア上部まで光が届く
      canvas.drawRect(rect,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: const [
            Color(0xFFB87840), // 直下（明るい暖色）
            Color(0xFF8B5228), // 上部1/4
            Color(0xFF4A2410), // 中間
            Color(0xFF241008), // 下部
            Color(0xFF100602), // 底
          ],
          stops: [0.0, 0.18, 0.45, 0.75, 1.0],
        ).createShader(rect),
      );

      // 柱側面
      for (final px in pilXs) {
        final cx    = px + _kPilW / 2;
        final dX    = camX - cx;
        final showLeft = dX < 0; // 実機確認済み
        final t     = (dX.abs() / (bayW * 0.30)).clamp(0.0, 1.0);
        final sideW = _kPilSD * t;
        if (sideW < 0.5) continue;

        double sideX = showLeft ? px - sideW : px + _kPilW;
        double actualW = sideW;
        if (showLeft) {
          if (sideX < 0) { actualW += sideX; sideX = 0; }
        } else {
          if (sideX + actualW > wallW) actualW = wallW - sideX;
        }
        if (actualW < 0.5) continue;

        final sideRect = Rect.fromLTWH(sideX, top - _kUndersideH, actualW, kRowHeight + _kUndersideH);
        final gradBegin = showLeft ? Alignment.centerRight : Alignment.centerLeft;
        final gradEnd   = showLeft ? Alignment.centerLeft  : Alignment.centerRight;

        // librub実測: 側面 RGB(97,62,34)≒#613E22、接合部 RGB(32,25,17)≒黒
        canvas.drawRect(sideRect,
          Paint()..shader = LinearGradient(
            begin: gradBegin, end: gradEnd,
            colors: const [
              Color(0xFF201008),
              Color(0xFF4A2810),
              Color(0xFF6B3E22),
              Color(0xFF7A4A2A),
            ],
            stops: const [0.0, 0.15, 0.55, 1.0],
          ).createShader(sideRect),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BackAndSidePainter o) => o.camX != camX || o.shelfH != shelfH;
}

// ══════════════════════════════════════════════════════════════════
// 3. _ShelfBoardPainter — ①上面 ②前面エッジ ③LED
// ══════════════════════════════════════════════════════════════════
class _ShelfBoardPainter extends CustomPainter {
  const _ShelfBoardPainter({
    required this.wallW, required this.pilXs,
    required this.topH, required this.lightH,
  });
  final double wallW, topH, lightH;
  final List<double> pilXs;

  @override
  void paint(Canvas canvas, Size size) {
    for (int i = 0; i < pilXs.length - 1; i++) {
      final x1 = pilXs[i] + _kPilW;
      final x2 = pilXs[i + 1];
      if (x2 <= x1) continue;
      final w = x2 - x1;

      double y = 0;

      // ① 上面：明るい木色（縦柱トンマナ）
      final topRect = Rect.fromLTWH(x1, y, w, topH);
      canvas.drawRect(topRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: const [
            Color(0xFF8A6828),
            Color(0xFFA87C3A),
            Color(0xFFBF9448),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(topRect),
      );
      y += topH;

      // ② 前面エッジ：暗い帯
      final faceRect = Rect.fromLTWH(x1, y, w, _kFaceH);
      canvas.drawRect(faceRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: const [
            Color(0xFF3A2008),
            Color(0xFF28160A),
          ],
          stops: const [0.0, 1.0],
        ).createShader(faceRect),
      );
      y += _kFaceH;

      // ③ LED：グラデで立体感（中央最明、白に近いクリーム）
      final ledRect = Rect.fromLTWH(x1, y, w, lightH);
      canvas.drawRect(ledRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: const [
            Color(0xFFE0CC90),
            Color(0xFFFFFAF0),
            Color(0xFFE8D498),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(ledRect),
      );
      canvas.drawRect(
        Rect.fromLTWH(x1, y, w, lightH),
        Paint()
          ..color = Colors.white.withOpacity(0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      y += lightH;

      // LED下グロー→後壁なじみ
      final glowRect = Rect.fromLTWH(x1, y, w, _kGlowH);
      canvas.drawRect(glowRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: const [
            Color(0xFF8B5828),
            Color(0xFF5A3018),
          ],
          stops: const [0.0, 1.0],
        ).createShader(glowRect),
      );
    }
  }

  @override
  bool shouldRepaint(_ShelfBoardPainter o) =>
      o.topH != topH || o.lightH != lightH;
}

// ══════════════════════════════════════════════════════════════════
// 3b. _ShelfUndersidePainter — ④裏面
//   縦柱側面と全く同じtで計算、L字結合
//   _BackAndSidePainterと同レイヤー構造だが棚板のY位置に描く
// ══════════════════════════════════════════════════════════════════
class _ShelfUndersidePainter extends CustomPainter {
  const _ShelfUndersidePainter({
    required this.wallW, required this.totalH,
    required this.pilXs, required this.bayW,
    required this.camX,  required this.shelfH,
  });
  final double wallW, totalH, bayW, camX, shelfH;
  final List<double> pilXs;

  @override
  void paint(Canvas canvas, Size size) {
    int nShelves = 0;
    double y = 0;
    while (y < totalH) {
      final uY = y + _kTopH + _kFaceH + _kLightH + _kGlowH;

      for (int bi = 0; bi < pilXs.length - 1; bi++) {
        final x1 = pilXs[bi] + _kPilW;
        final x2 = pilXs[bi + 1];
        if (x2 <= x1) continue;

        final dXLeft  = camX - (pilXs[bi]     + _kPilW / 2);
        final dXRight = camX - (pilXs[bi + 1] + _kPilW / 2);
        final tLeft   = (dXLeft.abs()  / (bayW * 0.30)).clamp(0.0, 1.0);
        final tRight  = (dXRight.abs() / (bayW * 0.30)).clamp(0.0, 1.0);
        // 左柱：右側面が見える時(dXLeft>0)のみsl>0
        final sl = dXLeft  > 0 ? (_kPilSD * tLeft).clamp(0.0,  (x2 - x1) / 2) : 0.0;
        // 右柱：左側面が見える時(dXRight<0)のみsr>0
        final sr = dXRight < 0 ? (_kPilSD * tRight).clamp(0.0, (x2 - x1) / 2) : 0.0;

        // 台形：上辺全幅、下辺は両端をsl/srだけ内側
        final path = Path();
        path.moveTo(x1,      uY);
        path.lineTo(x2,      uY);
        path.lineTo(x2 - sr, uY + _kUndersideH);
        path.lineTo(x1 + sl, uY + _kUndersideH);
        path.close();

        final rect = Rect.fromLTWH(x1, uY, x2 - x1, _kUndersideH);
        canvas.drawPath(path,
          Paint()..shader = LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: const [
              Color(0xFFB87840), // 上端：後壁グラデ上端色と統一
              Color(0xFF7A4A2A), // 下端：側面色と統一
            ],
          ).createShader(rect),
        );
      }

      nShelves++;
      y += shelfH + kRowHeight;
      if (nShelves > 10) break;
    }
  }

  @override
  bool shouldRepaint(_ShelfUndersidePainter o) => o.camX != camX;
}

// ══════════════════════════════════════════════════════════════════
// 4. _PillarFacePainter — 柱正面
//   librub実測: x=0〜48で RGB(175,140,59)→RGB(161,101,51)
//   左端やや黄み、右端やや茶色（微差）
// ══════════════════════════════════════════════════════════════════
class _PillarFacePainter extends CustomPainter {
  const _PillarFacePainter({required this.totalH, required this.pilXs});
  final double totalH;
  final List<double> pilXs;

  @override
  void paint(Canvas canvas, Size size) {
    for (final px in pilXs) {
      final faceRect = Rect.fromLTWH(px, 0, _kPilW, totalH);
      // librub実測: 左 RGB(175,140,59)→右 RGB(161,101,51)
      canvas.drawRect(faceRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end:   Alignment.centerRight,
          colors: const [
            Color(0xFFAF8C3B), // 左（やや黄み） RGB(175,140,59)
            Color(0xFFA56E36), // 中央 RGB(165,110,54)
            Color(0xFF916533), // 右（やや暗）   RGB(145,101,51)
          ],
          stops: const [0.0, 0.4, 1.0],
        ).createShader(faceRect),
      );
      canvas.drawLine(
        Offset(px + 0.5, 0), Offset(px + 0.5, totalH),
        Paint()..color = Colors.white.withOpacity(0.20)..strokeWidth = 1.0,
      );
      canvas.drawLine(
        Offset(px + _kPilW - 0.5, 0), Offset(px + _kPilW - 0.5, totalH),
        Paint()..color = Colors.black.withOpacity(0.30)..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ══════════════════════════════════════════════════════════════════
// 2. _BooksLayer
// ══════════════════════════════════════════════════════════════════
class _BooksLayer extends StatelessWidget {
  const _BooksLayer({
    required this.games, required this.label, required this.seed,
    required this.wallW, required this.pilXs,
  });
  final List<Game> games;
  final String label;
  final int seed;
  final double wallW;
  final List<double> pilXs;

  @override
  Widget build(BuildContext context) {
    final boxes  = ShelfLayoutEngine.generateRow(
      games: games, row: 0, wallWidth: wallW,
      rng: math.Random(seed), pilXs: pilXs,
    );
    final pops   = ShelfLayoutEngine.generatePops(
      label: label, seed: seed, wallWidth: wallW,
    );
    final sorted = [...boxes]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return Stack(clipBehavior: Clip.hardEdge, children: [
      for (int i = 0; i < pilXs.length - 1; i++)
        Positioned(
          left:   pilXs[i] + _kPilW,
          top:    0,
          width:  (pilXs[i + 1] - pilXs[i] - _kPilW).clamp(0.0, wallW),
          height: kRowHeight,
          child: ClipRect(
            child: Stack(clipBehavior: Clip.hardEdge, children: [
              ...sorted
                .where((p) =>
                  p.x + p.width > pilXs[i] + _kPilW &&
                  p.x < pilXs[i + 1])
                .map((p) {
                  final localX = p.x - (pilXs[i] + _kPilW);
                  if (p.pose == BoxPose.stack) {
                    final t = (kRowHeight - p.height
                        - p.stackLayer * (p.height + 1.5))
                        .clamp(0.0, kRowHeight - p.height);
                    return Positioned(
                      left: localX, top: t,
                      width: p.width, height: p.height,
                      child: StackBoxWidget(
                          key: ValueKey('s${seed}_${p.x.toInt()}'), p: p),
                    );
                  }
                  return Positioned(
                    left: localX, bottom: 0,
                    width: p.width, height: p.height,
                    child: p.pose == BoxPose.face
                        ? FaceBoxWidget(
                            key: ValueKey('f${seed}_${p.x.toInt()}'), p: p)
                        : SpineBoxWidget(
                            key: ValueKey('sp${seed}_${p.x.toInt()}'), p: p),
                  );
                }),
            ]),
          ),
        ),
      ...pops.map((pop) {
        final sz = kPopSize[pop.type]!;
        final st = _popStyles[pop.label] ?? _popStyles['FEATURED']!;
        return Positioned(
          left:   pop.x - sz.width / 2,
          bottom: 0,
          child:  _PopWidget(pop: pop, style: st, sz: sz),
        );
      }),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
// POP Widget
// ══════════════════════════════════════════════════════════════════
class _PopWidget extends StatelessWidget {
  const _PopWidget({required this.pop, required this.style, required this.sz});
  final PlacedPop pop; final _PS style; final Size sz;

  @override
  Widget build(BuildContext context) {
    final rng  = math.Random(pop.seed);
    final tilt = pop.type == PopType.lean
        ? (rng.nextBool() ? 1 : -1) * (0.12 + rng.nextDouble() * 0.14)
        : (rng.nextDouble() - 0.5) * (pop.type == PopType.plate ? 0.04 : 0.20);
    return Transform.rotate(
      angle: tilt,
      alignment: pop.type == PopType.plate ? Alignment.center : Alignment.bottomCenter,
      child: SizedBox(width: sz.width, height: sz.height,
        child: CustomPaint(
          painter: _PopPainter(style: style, type: pop.type),
          child: _popText())),
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
          shadows: [Shadow(
            color: Colors.black.withOpacity(0.22),
            offset: const Offset(0, 1), blurRadius: 3)]))));
  }
}

class _PopPainter extends CustomPainter {
  const _PopPainter({required this.style, required this.type});
  final _PS style; final PopType type;
  @override
  void paint(Canvas canvas, Size s) {
    switch (type) {
      case PopType.stand: _drawStand(canvas, s);
      case PopType.plate: _drawPlate(canvas, s);
      case PopType.lean:  _drawLean(canvas, s);
    }
  }
  void _drawStand(Canvas c, Size s) {
    final b = RRect.fromRectAndRadius(Rect.fromLTWH(0,0,s.width,s.height*.92), const Radius.circular(3));
    _sh(c,Path()..addRRect(b)); c.drawRRect(b, Paint()..color=style.bg);
    _gl(c,s,s.height*.92*.4);
    c.drawRect(Rect.fromLTWH(0,6,3.5,s.height*.92-12), Paint()..color=style.dark.withOpacity(.55));
    _bd(c,Path()..addRRect(b));
    c.drawPath(Path()..moveTo(s.width*.35,s.height*.92)..lineTo(s.width*.65,s.height*.92)..lineTo(s.width*.5,s.height)..close(), Paint()..color=style.dark);
  }
  void _drawPlate(Canvas c, Size s) {
    final b = RRect.fromRectAndRadius(Rect.fromLTWH(0,0,s.width,s.height), Radius.circular(s.height/2));
    _sh(c,Path()..addRRect(b)); c.drawRRect(b, Paint()..color=style.bg);
    _gl(c,s,s.height*.55); _bd(c,Path()..addRRect(b));
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0,0,6,s.height),Radius.circular(s.height/2)), Paint()..color=style.dark.withOpacity(.7));
  }
  void _drawLean(Canvas c, Size s) {
    final b = Path()..moveTo(3,1)..lineTo(s.width-2,0)..lineTo(s.width-1,s.height-2)..lineTo(1,s.height-1)..close();
    _sh(c,b); c.drawPath(b, Paint()..color=style.bg); _gl(c,s,s.height*.38);
    for (double y=s.height*.65; y<s.height-4; y+=9)
      c.drawLine(Offset(6,y),Offset(s.width-6,y), Paint()..color=Colors.black.withOpacity(.08)..strokeWidth=.8);
    _bd(c,b);
  }
  void _sh(Canvas c, Path p) => c.drawPath(p.shift(const Offset(2.5,4)),
      Paint()..color=Colors.black.withOpacity(.3)..maskFilter=const MaskFilter.blur(BlurStyle.normal,8));
  void _gl(Canvas c, Size s, double h) => c.drawRect(Rect.fromLTWH(0,0,s.width,h),
      Paint()..shader=LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,
          colors:[Colors.white.withOpacity(.32),Colors.transparent]).createShader(Rect.fromLTWH(0,0,s.width,h)));
  void _bd(Canvas c, Path p) => c.drawPath(p,
      Paint()..color=Colors.black.withOpacity(.13)..style=PaintingStyle.stroke..strokeWidth=.9);
  @override bool shouldRepaint(_) => false;
}

