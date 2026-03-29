import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/repositories/game_provider.dart' show ShelfRow, ShelfBayConfig;
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

// ランクPOPサイズ定数
const double _kRankPopW = 64.0;
const double _kRankPopH = 28.0;

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
  'RANKING':       _PS('ランキング', Color(0xFFD09248), Color(0xFFFFF8E8), Color(0xFFFFD060)),
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
    this.showPillars     = true,
  });
  final List<Game>     games;
  final List<ShelfRow> rows;
  final double         wallWidth;
  final double         viewportOffset;
  final double         viewportOffsetY;
  final double         viewportWidth;
  final double         viewportHeight;
  final double         viewportScale;
  final bool           showPillars;

  @override
  Widget build(BuildContext context) {
    final nRows = rows.length.clamp(0, 4);
    final bayW  = wallWidth / 4;

    final camX = viewportOffset + viewportWidth / 2;
    final camY = viewportOffsetY + viewportHeight / 2;

    // showPillars=falseの場合は単一ベイ（区切りなし）
    final pilXs = showPillars
        ? [0.0, bayW, bayW * 2, bayW * 3, wallWidth - _kPilW]
        : <double>[-_kPilW, wallWidth];

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

    // パッケージ3D用パースペクティブ係数 (topHs[i] / _kTopH)
    // 見下ろし行 > 1.0、見上げ行 < 1.0
    final perspFactors = List.generate(nRows, (i) => topHs[i] / _kTopH);

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

    // 行ごとのベイ設定を事前計算
    final rowBayConfigs = <List<ShelfBayConfig>>[];
    final rowSkipBays   = <int?>[];
    // ランクPOPの配置情報: [(left絶対座標, rank番号)]
    final rowRankPopPositions = <List<({double left, int rank})>>[];

    for (int i = 0; i < nRows; i++) {
      final bcs = List.generate(pilXs.length - 1, (j) => rows[i].bayConfig(j));
      rowBayConfigs.add(bcs);
      int? skip;
      for (int j = 0; j < bcs.length; j++) {
        if (bcs[j].label == 'RANKING') { skip = j; break; }
      }
      rowSkipBays.add(skip);

      // RANKINGベイがあればランクPOP位置を計算
      if (skip != null) {
        final bayLeft = pilXs[skip] + _kPilW;
        final bayW    = pilXs[skip + 1] - pilXs[skip] - _kPilW;
        final (:dims, :spacing) = _RankingBayOverlay.computeLayout(
          bcs[skip].gameIds, games, bayW,
        );
        // カテゴリPOPは left=22, width=84 → 右端 106 + 余白8 = 114px
        const sectionLabelEnd = 22.0 + 84.0 + 8.0;
        double cursor = spacing;
        final pops = <({double left, int rank})>[];
        for (int r = 0; r < dims.length; r++) {
          final w       = dims[r].$2;
          final centerX = cursor + w / 2;    // ベイ内相対X
          // 重なる場合はカテゴリPOP右端に寄せて必ず表示
          final popLeft = (centerX - _kRankPopW / 2).clamp(sectionLabelEnd, double.infinity);
          pops.add((left: bayLeft + popLeft, rank: r + 1));
          cursor += w + spacing;
        }
        rowRankPopPositions.add(pops);
      } else {
        rowRankPopPositions.add([]);
      }
    }

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
                showPillars: showPillars,
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
                showPillars: showPillars,
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
              games: games,
              label: rows[i].label,
              seed: rows[i].seed,
              wallW: wallWidth,
              pilXs: pilXs,
              bayConfigs: rowBayConfigs[i],
              skipBay: rowSkipBays[i],
              rowIdx: i,
              totalRows: nRows,
              camY: camY,
              rowBottomY: rowYs[i] + kRowHeight,
              viewportH: viewportHeight,
              camX: camX,
              viewportW: viewportWidth,
              perspFactor: perspFactors[i],
            ),
          ),
        // セクションラベル — 全ベイ表示（RANKINGも "ランキング" POP を表示）
        for (int i = 0; i < nRows; i++)
          for (int j = 0; j < pilXs.length - 1; j++)
            if (pilXs[j + 1] - pilXs[j] - _kPilW > 40)
              Positioned(
                left: pilXs[j] + _kPilW + 22,
                top:  shelfYs[i] + topHs[i],
                child: IgnorePointer(
                  child: _SectionLabel(
                    style: _popStyles[rowBayConfigs[i][j].label] ?? _popStyles['FEATURED']!,
                    camX: camX,
                    labelCenterX: pilXs[j] + _kPilW + 22 + 42,
                    tiltSeed: j * 7 + i * 13,
                  ),
                ),
              ),
        // RANKINGオーバーレイ — 該当ベイのみ、収まらないゲームはスキップ
        for (int i = 0; i < nRows; i++)
          if (rowSkipBays[i] != null)
            Positioned(
              left:   pilXs[rowSkipBays[i]!] + _kPilW,
              top:    rowYs[i],
              width:  pilXs[rowSkipBays[i]! + 1] - pilXs[rowSkipBays[i]!] - _kPilW,
              height: kRowHeight,
              child: _RankingBayOverlay(
                gameIds:  rowBayConfigs[i][rowSkipBays[i]!].gameIds,
                allGames: games,
                bayWidth: pilXs[rowSkipBays[i]! + 1] - pilXs[rowSkipBays[i]!] - _kPilW,
                rowIndex: i,
                camY: camY,
                rowBottomY: rowYs[i] + kRowHeight,
                viewportH: viewportHeight,
                camX: camX,
                viewportW: viewportWidth,
                perspFactor: perspFactors[i],
                bayAbsLeft: pilXs[rowSkipBays[i]!] + _kPilW,
              ),
            ),
        // ランクPOP — カテゴリPOPと同じ棚板レベルに配置、"ランキング"POPと重ならないよう左を空ける
        for (int i = 0; i < nRows; i++)
          for (final (:left, :rank) in rowRankPopPositions[i])
            Positioned(
              left:   left,
              top:    shelfYs[i] + topHs[i],
              width:  _kRankPopW,
              height: _kRankPopH,
              child: IgnorePointer(child: _RankPop(rank: rank)),
            ),
        // 最前面の柱も描画のみ（タップ透過）。showPillars=falseのとき非表示
        if (showPillars)
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
    this.showPillars = true,
  });
  final double wallW, totalH, bayW, camX;
  final int    nRows;
  final List<double> pilXs;
  final List<double> rowYs;
  final List<double> undersideHs;
  final bool showPillars;

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
      if (showPillars) for (final px in pilXs) {
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
    this.showPillars = true,
  });
  final double wallW, totalH, bayW, camX;
  final List<double> pilXs;
  final List<double> shelfYs, shelfHs, undersideHs, topHs;
  final bool showPillars;

  @override
  void paint(Canvas canvas, Size size) {
    for (int si = 0; si < shelfYs.length; si++) {
      final y  = shelfYs[si];
      final uH = undersideHs[si];
      final uY = y + topHs[si] + _kFaceH + _kLightH + _kGlowH;

      // 区切りなしモードはシンプルな全幅グラデーション
      if (!showPillars) {
        final rect = Rect.fromLTWH(0, uY, wallW, uH);
        canvas.drawRect(rect, Paint()..shader = const LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xFFB87840), Color(0xFF7A4A2A)],
        ).createShader(rect));
        continue;
      }

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
// _RankingBayOverlay — RANKINGベイにランキング1〜5位を正面表示
// ・収まらないゲームはスキップ（クリップ禁止）
// ・ランクPOPはパッケージではなく棚板レベルに貼り付け
// ══════════════════════════════════════════════════════════════════
class _RankingBayOverlay extends StatelessWidget {
  const _RankingBayOverlay({
    required this.gameIds,
    required this.allGames,
    required this.bayWidth,
    required this.rowIndex,
    this.camY        = 400.0,
    this.rowBottomY  = 0.0,
    this.viewportH   = 800.0,
    this.camX        = 0.0,
    this.viewportW   = 390.0,
    this.perspFactor = 1.0,
    this.bayAbsLeft  = 0.0,
  });
  final List<String> gameIds;
  final List<Game>   allGames;
  final double       bayWidth;
  final int          rowIndex;
  final double       camY, rowBottomY, viewportH;
  final double       camX, viewportW, perspFactor, bayAbsLeft;

  double get _floorSink {
    final dy = camY - rowBottomY;
    final refDist = viewportH * 0.6;
    final tSink = (-dy / refDist).clamp(0.0, 1.5);
    return (_kTopH * 0.40 * tSink).clamp(0.0, _kTopH * 0.55);
  }

  static double _faceH(BoxSize s) {
    switch (s) {
      case BoxSize.tiny:   return kRowHeight * 0.50;
      case BoxSize.small:  return kRowHeight * 0.62;
      case BoxSize.medium: return kRowHeight * 0.74;
      case BoxSize.large:  return kRowHeight * 0.84;
    }
  }

  /// 配置座標を計算（ShelfWallからのランクPOP配置にも使用）
  static ({List<(Game, double, double)> dims, double spacing}) computeLayout(
    List<String> gameIds, List<Game> allGames, double bayWidth,
  ) {
    final games = gameIds
        .map((id) => allGames.firstWhere((g) => g.id == id,
            orElse: () => allGames.first))
        .take(5)
        .toList();

    final all = games.map((g) {
      final h = _faceH(g.size);
      final w = (h * g.faceAspect).clamp(50.0, 160.0);
      return (g, w, h);
    }).toList();

    // 収まる数を計算（収まらないゲームは除外）
    const minSpacing = 8.0;
    for (int n = all.length; n > 0; n--) {
      final totalW = all.take(n).fold(0.0, (s, d) => s + d.$2);
      if (totalW + minSpacing * (n + 1) <= bayWidth) {
        final spacing = ((bayWidth - totalW) / (n + 1)).clamp(minSpacing, 60.0);
        return (dims: all.take(n).toList(), spacing: spacing);
      }
    }
    return (dims: [], spacing: minSpacing);
  }

  @override
  Widget build(BuildContext context) {
    final (:dims, :spacing) = computeLayout(gameIds, allGames, bayWidth);
    if (dims.isEmpty) return const SizedBox.shrink();

    double cursor = spacing;
    final widgets = <Widget>[];

    for (int i = 0; i < dims.length; i++) {
      final (game, w, h) = dims[i];
      final rank    = i + 1;
      final heroTag = 'ranking_${game.id}_$rank';
      final pb = PlacedBox(
        game: game, pose: BoxPose.face,
        x: 0, row: rowIndex, width: w, height: h,
      );

      // パッケージ本体（カメラ位置で側面を動的に表示）
      final absBoxCenterX = bayAbsLeft + cursor + w / 2;
      final dXBox  = camX - absBoxCenterX;
      final sideT  = (dXBox.abs() / (viewportW * 0.5)).clamp(0.0, 1.0);
      final showRight = dXBox < 0;
      widgets.add(Positioned(
        left: cursor, bottom: -_floorSink,
        width: w, height: h,
        child: TappableBox(
          key: ValueKey(heroTag), heroTag: heroTag,
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) =>
              GameDetailScreen(game: game, heroTag: heroTag))),
          child: FaceBoxWidget(p: pb, perspFactor: perspFactor, sideT: sideT, showRightSide: showRight),
        ),
      ));

      cursor += w + spacing;
    }

    return Stack(clipBehavior: Clip.none, children: widgets);
  }
}

/// ランクPOP — フラット配色 + 手書きフォントで目を引く
class _RankPop extends StatelessWidget {
  const _RankPop({required this.rank});
  final int rank;

  static const _bgColors = [
    Color(0xFFC8860A), // 1位: ゴールド
    Color(0xFF6A6A7E), // 2位: シルバー
    Color(0xFF9A5018), // 3位: ブロンズ
    Color(0xFF5A4430), // 4位
    Color(0xFF5A4430), // 5位
  ];

  @override
  Widget build(BuildContext context) {
    final idx = (rank - 1).clamp(0, _bgColors.length - 1);
    final bg  = _bgColors[idx];

    return Container(
      width: _kRankPopW,
      height: _kRankPopH,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        boxShadow: const [
          BoxShadow(color: Color(0x88000000), blurRadius: 3, offset: Offset(0, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank位',
        style: GoogleFonts.kleeOne(
          color: Colors.white,
          fontSize: rank <= 3 ? 13.5 : 12.0,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// 2. _BooksLayer
// ══════════════════════════════════════════════════════════════════
class _BooksLayer extends StatelessWidget {
  const _BooksLayer({
    required this.games, required this.label, required this.seed,
    required this.wallW, required this.pilXs,
    this.bayConfigs,
    this.skipBay,
    this.rowIdx      = 0,
    this.totalRows   = 4,
    this.camY        = 400.0,
    this.rowBottomY  = 0.0,
    this.viewportH   = 800.0,
    this.camX        = 0.0,
    this.viewportW   = 390.0,
    this.perspFactor = 1.0,
  });
  final List<Game> games;
  final String label;
  final int seed;
  final double wallW;
  final List<double> pilXs;
  /// ベイごとの設定（nullなら行デフォルトのgames/seedを使用）
  final List<ShelfBayConfig>? bayConfigs;
  /// このベイインデックスは空にする（RANKINGオーバーレイが上に乗るため）
  final int? skipBay;
  /// 段インデックス（0=最上段）— 立体感演出の強度に使用
  final int rowIdx;
  final int totalRows;
  /// 棚板の視線計算用（柱側面と同じアプローチ）
  final double camY, rowBottomY, viewportH;
  /// パッケージ3D用カメラ情報
  final double camX, viewportW, perspFactor;

  /// 棚板側面と同様の視線ベース計算でパッケージが棚に"乗る"量を算出
  double get _floorSink {
    final dy = camY - rowBottomY;  // 負 = カメラが行下端より上 = 見下ろし
    final refDist = viewportH * 0.6;
    final tSink = (-dy / refDist).clamp(0.0, 1.5); // 見下ろし強度
    return (_kTopH * 0.40 * tSink).clamp(0.0, _kTopH * 0.55);
  }

  @override
  Widget build(BuildContext context) {
    // Clip.none: パッケージが棚板top面エリアに沈み込めるよう下方オーバーフローを許可
    return Stack(clipBehavior: Clip.none, children: [
      for (int bayIdx = 0; bayIdx < pilXs.length - 1; bayIdx++)
        _buildBay(context, bayIdx),
    ]);
  }

  Widget _buildBay(BuildContext context, int bayIdx) {
    final bayX = pilXs[bayIdx] + _kPilW;
    final bayW = (pilXs[bayIdx + 1] - pilXs[bayIdx] - _kPilW).clamp(0.0, wallW);
    if (bayW < 20) return const SizedBox.shrink();

    // このベイのゲームリストとシードを決定
    List<Game> bayGames = games;
    int baySeed = seed + bayIdx * 997;

    final bc = (bayConfigs != null && bayIdx < bayConfigs!.length)
        ? bayConfigs![bayIdx]
        : null;

    // RANKINGベイは空にする（_RankingBayOverlayが上に描画）
    if (bc?.label == 'RANKING' || skipBay == bayIdx) {
      return Positioned(
        left: bayX, top: 0, width: bayW, height: kRowHeight,
        child: const SizedBox.shrink(),
      );
    }
    if (bc != null && bc.gameIds.isNotEmpty) {
      final mapped = bc.gameIds
          .map((id) => games.firstWhere((g) => g.id == id,
              orElse: () => games[bayIdx % games.length]))
          .toList();
      if (mapped.isNotEmpty) {
        bayGames = mapped;
        baySeed  = bc.seed;
      }
    }

    // ベイ単体でgenerateRow（pilXs 2要素）
    final boxes = ShelfLayoutEngine.generateRow(
      games: bayGames, row: 0, wallWidth: wallW,
      rng: math.Random(baySeed),
      pilXs: [pilXs[bayIdx], pilXs[bayIdx + 1]],
    );
    final sorted = [...boxes]..sort((a, b) => a.zIndex.compareTo(b.zIndex));

    final sink = _floorSink;
    return Positioned(
      left: bayX, top: 0, width: bayW, height: kRowHeight,
      child: Stack(clipBehavior: Clip.none, children: [
        ...sorted
          .where((p) => p.x >= bayX && p.x < pilXs[bayIdx + 1])
          .map((p) {
            final localX = p.x - bayX;
            final posePrefix = p.pose == BoxPose.face
                ? 'f' : p.pose == BoxPose.stack ? 's' : 'sp';
            final heroTag = p.pose == BoxPose.stack
                ? 'game_box_s_${baySeed}_${p.x.toInt()}_${p.stackLayer}'
                : 'game_box_${posePrefix}_${baySeed}_${p.x.toInt()}';
            void navigateToDetail() {
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => GameDetailScreen(game: p.game, heroTag: heroTag),
              ));
            }
            if (p.pose == BoxPose.stack) {
              final t = (kRowHeight - p.height
                  - p.stackLayer * (p.height + 1.5))
                  .clamp(0.0, kRowHeight - p.height);
              return Positioned(
                left: localX, top: t, width: p.width, height: p.height,
                child: _wrap3D(
                  pose: p.pose,
                  child: TappableBox(
                    key: ValueKey(heroTag), heroTag: heroTag, onTap: navigateToDetail,
                    child: StackBoxWidget(p: p),
                  ),
                ),
              );
            }
            // face/spine: 視線角度に応じて棚板top面に沈み込む + 横角度で側面表示
            final absBoxCenterX = p.x + p.width / 2;
            final dXBox = camX - absBoxCenterX;
            // viewportW*0.5: ビューポートの端に来た時点でフル側面表示
            final sideT = (dXBox.abs() / (viewportW * 0.5)).clamp(0.0, 1.0);
            final showRight = dXBox < 0;
            return Positioned(
              left: localX, bottom: -sink, width: p.width, height: p.height,
              child: _wrap3D(
                pose: p.pose,
                child: TappableBox(
                  key: ValueKey(heroTag), heroTag: heroTag, onTap: navigateToDetail,
                  child: p.pose == BoxPose.face
                      ? FaceBoxWidget(p: p, perspFactor: perspFactor, sideT: sideT, showRightSide: showRight)
                      : SpineBoxWidget(p: p, perspFactor: perspFactor),
                ),
              ),
            );
          }),
      ]),
    );
  }

  /// 3DはFaceBoxWidget/SpineBoxWidgetのフラットパネルが担当
  Widget _wrap3D({required BoxPose pose, required Widget child}) => child;
}

// ══════════════════════════════════════════════════════════════════
// セクションラベル — 棚板直下・ベイ左上に固定
// 実店舗（すごろくや等）のサインカード再現
// ══════════════════════════════════════════════════════════════════
class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.style, required this.camX, required this.labelCenterX,
    this.tiltSeed = 0,
    this.width = 84.0,
  });
  final _PS style;
  final double camX;
  final double labelCenterX;
  final int tiltSeed;
  final double width;

  static const _h = 28.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width, height: _h,
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

    // ── 影（薄く、下方向のみ）────────────────────────────────
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 2, s.width, s.height), r),
      Paint()
        ..color = const Color(0x88000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // ── 本体（クリーム地）────────────────────────────────────
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, s.width, s.height), r),
      Paint()..color = style.bg,
    );

    // ── 左アクセントバー（セクションカラー）──────────────────
    c.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, 3.5, s.height), r),
      Paint()..color = style.dark,
    );

    // ── 下ボーダー（セクションカラー）────────────────────────
    c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, s.height - 2.5, s.width, 2.5), r),
      Paint()..color = style.dark,
    );

    // ── 上端ハイライト（LEDの光）─────────────────────────────
    c.drawLine(
      const Offset(2, 0.5), Offset(s.width - 2, 0.5),
      Paint()..color = Colors.white.withValues(alpha: 0.70)..strokeWidth = 1.0,
    );

    // ── テキスト（横書き・中央揃え）──────────────────────────
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
    )..layout(maxWidth: s.width - 12);
    tp.paint(c, Offset(
      5 + (s.width - 12 - tp.width) / 2 + 1,
      (s.height - 2.5 - tp.height) / 2,
    ));

    // ── 横スクロールで側面エッジが覗く ───────────────────────
    final dX = camX - centerX;
    final sideW = (dX.abs() / 280.0).clamp(0.0, 1.0) * 2.5;
    if (sideW > 0.3) {
      final showLeft = dX > 0;
      c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(showLeft ? 0 : s.width - sideW, 0, sideW, s.height), r),
        Paint()..color = Colors.black.withValues(alpha: 0.45),
      );
    }
  }

  @override
  bool shouldRepaint(_SectionLabelPainter o) =>
      o.camX != camX || o.centerX != centerX || o.style.dark != style.dark;
}
