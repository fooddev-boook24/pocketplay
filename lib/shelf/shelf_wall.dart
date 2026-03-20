import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import '../data/repositories/game_provider.dart';
import '../features/game_detail/game_detail_screen.dart';
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

// セクションラベル配色
// bg=ラベル本体色, fg=文字色, dark=ボーダー色（セクションカラーのみここで差別化）
const _popStyles = {
  'FEATURED':      _PS('注目作',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFC89048)),
  'NEW ARRIVAL':   _PS('新　着',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFC89048)),
  'NEW & HOT':     _PS('注目作',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFC89048)),
  'STRATEGY':      _PS('戦　略',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF6A8AAA)),
  '2 PLAYERS':     _PS('2 人 用',  Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFB06070)),
  'PARTY GAMES':   _PS('パーティ', Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFD07040)),
  'SMALL BOX':     _PS('小　箱',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF5A8E60)),
  'ADVENTURE':     _PS('冒　険',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF8060B0)),
  'ECONOMICS':     _PS('経　済',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF508080)),
  'CARD GAMES':    _PS('カード',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFB08040)),
  'ABSTRACT':      _PS('抽　象',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF7080A0)),
  'FAMILY':        _PS('家 族',    Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFD0A040)),
  'DEDUCTION':     _PS('推　理',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF506090)),
  'NEGOTIATION':   _PS('交　渉',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFFA04848)),
  'PUZZLE':        _PS('パズル',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF508070)),
  'LIGHT & QUICK': _PS('ライト',   Color(0xFFF2E8D8), Color(0xFF1A0800), Color(0xFF70A050)),
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
    this.viewportOffset  = 0.0,
    this.viewportOffsetY = 0.0,
    this.viewportWidth   = 390.0,
    this.viewportHeight  = 800.0,
    this.viewportScale   = 1.0,
  });
  final List<Game>     games;
  final List<ShelfRow> rows;
  final double         wallWidth;
  final double         viewportOffset;
  final double         viewportOffsetY;
  final double         viewportWidth;
  final double         viewportHeight;
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

    final camX = viewportOffset + viewportWidth / 2;
    final camY = viewportOffsetY + viewportHeight / 2;

    // ── パースペクティブ計算 ──
    // 固定shelfHで仮のY位置を求め、camYとの距離でtopH/undersideHを決定
    const fixedShelfH = _kShelfH; // 49pt（仮計算用）
    const fixedFront  = _kFaceH + _kLightH + _kGlowH; // 15pt（正面要素、固定）

    // nRows+1 個の棚板がある（天井棚板 + 各段の下棚板）
    // 棚板iのtopH[i], undersideH[i] を計算
    final topHs       = <double>[];
    final undersideHs = <double>[];
    final shelfHs     = <double>[];

    for (int i = 0; i <= nRows; i++) {
      // 仮のY位置（固定shelfHベース）
      final approxY = (fixedShelfH + kRowHeight) * i;
      // 棚板の前面中央あたりのY
      final shelfMidY = approxY + _kTopH / 2;

      // dy > 0 → 棚が視点より上 → 見上げ → underside見える
      // dy < 0 → 棚が視点より下 → 見下ろし → top見える
      final dy = camY - shelfMidY;
      // 基準距離：画面高さの半分程度を参照
      final refDist = viewportHeight * 0.6;
      final perspT = (dy / refDist).clamp(-1.5, 1.5);

      // scaleが大きい＝近い＝裏面のパース効果が強まる（天板には影響しない）
      final scaleMul = viewportScale.clamp(0.5, 2.5);

      // undersideH: 視点より上の棚ほど裏面が見える (perspT > 0)
      final tUnder = (perspT * scaleMul).clamp(0.0, 2.0);
      final underH = (_kUndersideH * (0.15 + 0.85 * tUnder)).clamp(1.0, _kUndersideH * 2.5);

      // topH: 視点より下の棚ほど天板が見える (perspT < 0)、scaleの影響なし
      final tTop = (-perspT).clamp(0.0, 1.5);
      final topH = (_kTopH * (0.3 + 0.7 * tTop)).clamp(4.0, _kTopH * 2.0);

      topHs.add(topH);
      undersideHs.add(underH);
      shelfHs.add(topH + fixedFront + underH);
    }

    // Y位置を累積計算
    final shelfYs = <double>[]; // 各棚板の開始Y
    final rowYs   = <double>[]; // 各本エリアの開始Y
    double curY = 0;
    for (int i = 0; i <= nRows; i++) {
      shelfYs.add(curY);
      curY += shelfHs[i];
      if (i < nRows) {
        rowYs.add(curY);
        curY += kRowHeight;
      }
    }
    final totalH = curY;

    return SizedBox(
      width:  wallWidth,
      height: totalH,
      child: Stack(clipBehavior: Clip.hardEdge, children: [
        // 描画のみ（タップ透過）
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _BackAndSidePainter(
                wallW: wallWidth, totalH: totalH, nRows: nRows,
                pilXs: pilXs, bayW: bayW, camX: camX,
                rowYs: rowYs, undersideHs: undersideHs,
              ),
            ),
          ),
        ),
        for (int i = 0; i <= nRows; i++)
          Positioned(
            left: 0, right: 0,
            top:    shelfYs[i],
            height: shelfHs[i],
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ShelfBoardPainter(
                  wallW: wallWidth, pilXs: pilXs,
                  topH: topHs[i], lightH: _kLightH,
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _ShelfUndersidePainter(
                wallW: wallWidth, totalH: totalH,
                pilXs: pilXs, bayW: bayW, camX: camX,
                shelfYs: shelfYs, shelfHs: shelfHs,
                undersideHs: undersideHs, topHs: topHs,
              ),
            ),
          ),
        ),
        for (int i = 0; i < nRows; i++)
          Positioned(
            left: 0, right: 0,
            top:    rowYs[i],
            height: kRowHeight,
            child: _BooksLayer(
              games: games, label: rows[i].label, seed: rows[i].seed,
              wallW: wallWidth, pilXs: pilXs,
            ),
          ),
        // セクションラベル — 各棚板前面エッジに貼り付け（本レイヤーの外・柱の手前）
        for (int i = 0; i < nRows; i++)
          for (int j = 0; j < pilXs.length - 1; j++)
            if (pilXs[j + 1] - pilXs[j] - _kPilW > 40)
              Positioned(
                left: pilXs[j] + _kPilW + 8,
                top:  shelfYs[i] + topHs[i], // 棚板topH面の前縁（faceH開始点）
                child: IgnorePointer(
                  child: _SectionLabel(
                    style: _popStyles[rows[i].label] ?? _popStyles['FEATURED']!,
                    camX: camX,
                    labelCenterX: pilXs[j] + _kPilW + 8 + 42,
                  ),
                ),
              ),
        // 最前面の柱も描画のみ（タップ透過）
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _PillarFacePainter(totalH: totalH, pilXs: pilXs),
            ),
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
    required this.rowYs, required this.undersideHs,
  });
  final double wallW, totalH, bayW, camX;
  final int    nRows;
  final List<double> pilXs;
  final List<double> rowYs;
  final List<double> undersideHs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, wallW, totalH),
      Paint()..color = const Color(0xFF100602),
    );

    for (int i = 0; i < nRows; i++) {
      final top  = rowYs[i];
      final rect = Rect.fromLTWH(0, top, wallW, kRowHeight);
      final uH   = undersideHs[i]; // この棚板の裏面高さ

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

        final sideRect = Rect.fromLTWH(sideX, top - uH, actualW, kRowHeight + uH);
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
  bool shouldRepaint(_BackAndSidePainter o) => true;
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
    required this.camX,
    required this.shelfYs, required this.shelfHs,
    required this.undersideHs, required this.topHs,
  });
  final double wallW, totalH, bayW, camX;
  final List<double> pilXs;
  final List<double> shelfYs, shelfHs, undersideHs, topHs;

  @override
  void paint(Canvas canvas, Size size) {
    for (int si = 0; si < shelfYs.length; si++) {
      final y  = shelfYs[si];
      final uH = undersideHs[si];
      final uY = y + topHs[si] + _kFaceH + _kLightH + _kGlowH;

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
        path.lineTo(x2 - sr, uY + uH);
        path.lineTo(x1 + sl, uY + uH);
        path.close();

        final rect = Rect.fromLTWH(x1, uY, x2 - x1, uH);
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
    }
  }

  @override
  bool shouldRepaint(_ShelfUndersidePainter o) => true;
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
                  p.x >= pilXs[i] + _kPilW &&
                  p.x < pilXs[i + 1])
                .map((p) {
                  final localX = p.x - (pilXs[i] + _kPilW);
                  final posePrefix = p.pose == BoxPose.face
                      ? 'f'
                      : p.pose == BoxPose.stack
                          ? 's'
                          : 'sp';
                  final heroTag = p.pose == BoxPose.stack
                      ? 'game_box_s_${seed}_${p.x.toInt()}_${p.stackLayer}'
                      : 'game_box_${posePrefix}_${seed}_${p.x.toInt()}';
                  void navigateToDetail() {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GameDetailScreen(
                          game: p.game,
                          heroTag: heroTag,
                        ),
                      ),
                    );
                  }
                  if (p.pose == BoxPose.stack) {
                    final t = (kRowHeight - p.height
                        - p.stackLayer * (p.height + 1.5))
                        .clamp(0.0, kRowHeight - p.height);
                    return Positioned(
                      left: localX, top: t,
                      width: p.width, height: p.height,
                      child: TappableBox(
                        key: ValueKey(heroTag),
                        heroTag: heroTag,
                        onTap: navigateToDetail,
                        child: StackBoxWidget(p: p),
                      ),
                    );
                  }
                  return Positioned(
                    left: localX, bottom: 0,
                    width: p.width, height: p.height,
                    child: TappableBox(
                      key: ValueKey(heroTag),
                      heroTag: heroTag,
                      onTap: navigateToDetail,
                      child: p.pose == BoxPose.face
                          ? FaceBoxWidget(p: p)
                          : SpineBoxWidget(p: p),
                    ),
                  );
                }),
            ]),
          ),
        ),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
// セクションラベル — 棚板直下・ベイ左上に固定
// 実店舗（すごろくや等）のサインカード再現
// ══════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.style, required this.camX, required this.labelCenterX,
  });
  final _PS style;
  final double camX;
  final double labelCenterX;

  static const _w = 84.0;
  static const _h = 28.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _w, height: _h,
      child: CustomPaint(
        painter: _SectionLabelPainter(
            style: style, camX: camX, centerX: labelCenterX),
      ),
    );
  }
}

class _SectionLabelPainter extends CustomPainter {
  const _SectionLabelPainter({
    required this.style, required this.camX, required this.centerX,
  });
  final _PS style;
  final double camX, centerX;

  @override
  void paint(Canvas c, Size s) {
    const r = Radius.circular(2);

    // 影（薄く、下方向のみ）
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 2, s.width, s.height), r),
      Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 本体（クリーム地）
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width, s.height), r),
      Paint()..color = style.bg,
    );

    // セクションカラーの下ボーダー（2pt）で区別
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, s.height - 2.5, s.width, 2.5), r),
      Paint()..color = style.dark,
    );

    // 上端：LEDの光を受けた細いハイライト
    c.drawLine(
      const Offset(2, 0.5), Offset(s.width - 2, 0.5),
      Paint()..color = Colors.white.withValues(alpha: 0.70)..strokeWidth = 1.0,
    );

    // テキスト（横書き・中央揃え）
    final tp = TextPainter(
      text: TextSpan(
        text: style.text,
        style: TextStyle(
          color: style.fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: s.width - 8);
    tp.paint(c, Offset(
      (s.width - tp.width) / 2,
      (s.height - 2.5 - tp.height) / 2,
    ));

    // 横スクロールで側面エッジが覗く
    final dX = camX - centerX;
    final sideW = (dX.abs() / 280.0).clamp(0.0, 1.0) * 2.0;
    if (sideW > 0.3) {
      final showLeft = dX > 0;
      c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(showLeft ? 0 : s.width - sideW, 0, sideW, s.height), r),
        Paint()..color = Colors.black.withValues(alpha: 0.50),
      );
    }
  }

  @override
  bool shouldRepaint(_SectionLabelPainter o) =>
      o.camX != camX || o.centerX != centerX || o.style.dark != style.dark;
}
