import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/painting.dart';
import '../data/repositories/game_provider.dart';
import 'box_widgets.dart';
import 'shelf_engine.dart';
import '../data/models/game.dart';

// ══════════════════════════════════════════════════════════════════
// 本棚の木材構造
//
// 物理法則:
//   縦板（柱）が主構造 → 横板（棚板）が縦板に刺さる
//   → 縦板は横板より「手前」に来る（Z軸で上）
//   → 接合部では縦板が横板を覆う
//
// 描画順（奥→手前）:
//   1. 後壁（背板）
//   2. 本（後壁より手前）
//   3. 横板（棚板）← 本より手前
//   4. 縦板の側面（横板と同じ深さ）
//   5. 縦板の正面（最手前、横板を覆う）
//
// 寸法:
//   柱数: 最大5本（4区画）
//   棚行: 最大4行
//   柱正面幅 _kPilW = 20pt
//   柱側面最大幅 = _kPilW * 2 = 40pt（camXで動的）
//   棚板厚み _kShelfH = 24pt
//     上面（天板面）: 14pt  明るい茶色
//     正面（前エッジ）: 10pt  やや暗い（奥行き）
//   bayW = wallWidth / 4 = 可変
// ══════════════════════════════════════════════════════════════════

const int    _kMaxPillars = 5;   // 最大柱本数
const int    _kMaxRows    = 4;   // 最大棚行数
const double _kPilW    = 20.0;   // 柱正面幅
const double _kPilSDMax = _kPilW * 2.0;  // 側面最大幅 = 柱幅の2倍
const double _kShelfH  = 24.0;   // 棚板総厚み
const double _kShelfTopH = 14.0; // 棚板上面高さ（明るい）
const double _kShelfFaceH = 10.0;// 棚板正面高さ（暗い、奥行き）

// 色
const _cPillar    = Color(0xFFA86030);  // 柱・棚板の茶色
const _cShelfTop  = Color(0xFFB87038);  // 棚板上面（明るめ）
const _cShelfFace = Color(0xFF7A3E14);  // 棚板正面（暗い）
const _cWallTop   = Color(0xFF9A6438);  // 後壁上（照明直下）
const _cWallBot   = Color(0xFF160600);  // 後壁下

// POP
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
  final List<Game>     games;
  final List<ShelfRow> rows;
  final double wallWidth;
  final double viewportOffset;
  final double viewportWidth;

  @override
  Widget build(BuildContext context) {
    final nRows  = rows.length.clamp(0, _kMaxRows);
    final nPils  = _kMaxPillars;           // 5本
    final bayW   = wallWidth / (nPils - 1);// 区画幅
    final totalH = kRowHeight * nRows + _kShelfH * (nRows + 1);
    final camX   = viewportOffset + viewportWidth / 2;

    // 柱のx座標（正面左端）
    final pilXs = List.generate(nPils, (i) => bayW * i);

    return SizedBox(
      width:  wallWidth,
      height: totalH,
      child: Stack(clipBehavior: Clip.hardEdge, children: [

        // ① 後壁（背板）全面
        Positioned.fill(
          child: CustomPaint(
            painter: _BackWallPainter(
              wallW:  wallWidth,
              totalH: totalH,
              nRows:  nRows,
              shelfH: _kShelfH,
              rowH:   kRowHeight,
            ),
          ),
        ),

        // ② 本（各段・柱の後ろで後壁より手前）
        for (int i = 0; i < nRows; i++)
          Positioned(
            left: 0, right: 0,
            top:  _kShelfH + (_kShelfH + kRowHeight) * i,
            height: kRowHeight,
            child: _BooksLayer(
              games:  games,
              label:  rows[i].label,
              seed:   rows[i].seed,
              wallW:  wallWidth,
            ),
          ),

        // ③ 棚板（横板）上面＋正面エッジ
        for (int i = 0; i <= nRows; i++)
          Positioned(
            left: 0, right: 0,
            top:  (_kShelfH + kRowHeight) * i,
            height: _kShelfH,
            child: CustomPaint(
              painter: _ShelfBoardPainter(
                wallW:  wallWidth,
                pilXs:  pilXs,
                pilW:   _kPilW,
              ),
            ),
          ),

        // ④⑤ 柱（縦板）：側面→正面の順で描く（正面が最手前）
        Positioned.fill(
          child: CustomPaint(
            painter: _PillarsPainter(
              wallW:   wallWidth,
              totalH:  totalH,
              camX:    camX,
              pilXs:   pilXs,
              bayW:    bayW,
            ),
          ),
        ),
      ]),
    );
  }
}

// ══════════════════════════════════════════════════════════════════
// _BackWallPainter
// ══════════════════════════════════════════════════════════════════
class _BackWallPainter extends CustomPainter {
  const _BackWallPainter({
    required this.wallW,
    required this.totalH,
    required this.nRows,
    required this.shelfH,
    required this.rowH,
  });
  final double wallW, totalH, shelfH, rowH;
  final int nRows;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Rect.fromLTWH(0, 0, wallW, totalH),
        Paint()..color = _cWallBot);

    for (int i = 0; i < nRows; i++) {
      final top  = shelfH + (shelfH + rowH) * i;
      final rect = Rect.fromLTWH(0, top, wallW, rowH);
      // 後壁グラデ（棚板直下が明るい）
      canvas.drawRect(rect,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: const [
            Color(0xFF9A6438),
            Color(0xFF6A3E1C),
            Color(0xFF3A1A06),
            Color(0xFF160600),
          ],
          stops: const [0.0, 0.18, 0.60, 1.0],
        ).createShader(rect),
      );
      // 棚板直下の照明グロー
      final glow = Rect.fromLTWH(0, top, wallW, rowH * 0.25);
      canvas.drawRect(glow,
        Paint()..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.38),
            Colors.transparent,
          ],
        ).createShader(glow),
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ══════════════════════════════════════════════════════════════════
// _BooksLayer
// ══════════════════════════════════════════════════════════════════
class _BooksLayer extends StatelessWidget {
  const _BooksLayer({
    required this.games,
    required this.label,
    required this.seed,
    required this.wallW,
  });
  final List<Game> games;
  final String label;
  final int seed;
  final double wallW;

  @override
  Widget build(BuildContext context) {
    final boxes = ShelfLayoutEngine.generateRow(
      games: games, row: 0, wallWidth: wallW, rng: math.Random(seed),
    );
    final pops = ShelfLayoutEngine.generatePops(
      label: label, seed: seed, wallWidth: wallW,
    );
    final sorted = [...boxes]..sort((a,b) => a.zIndex.compareTo(b.zIndex));

    return Stack(clipBehavior: Clip.hardEdge, children: [
      ...sorted.map((p) {
        if (p.pose == BoxPose.stack) {
          final top = (kRowHeight - p.height - p.stackLayer*(p.height+1.5))
              .clamp(0.0, kRowHeight-p.height);
          return Positioned(left:p.x, top:top, width:p.width, height:p.height,
              child:StackBoxWidget(key:ValueKey('s${seed}_${p.x.toInt()}'),p:p));
        }
        return Positioned(
          left: p.x,
          bottom: 0,  // 棚板上面にぴったり
          width: p.width, height: p.height,
          child: p.pose == BoxPose.face
              ? FaceBoxWidget(key:ValueKey('f${seed}_${p.x.toInt()}'),p:p)
              : SpineBoxWidget(key:ValueKey('sp${seed}_${p.x.toInt()}'),p:p),
        );
      }),
      ...pops.map((pop) {
        final sz = kPopSize[pop.type]!;
        final st = _popStyles[pop.label] ?? _popStyles['FEATURED']!;
        return Positioned(
          left: pop.x - sz.width/2,
          bottom: 0,
          child: _PopWidget(pop:pop, style:st, sz:sz),
        );
      }),
    ]);
  }
}

// ══════════════════════════════════════════════════════════════════
// _ShelfBoardPainter — 棚板（横板）の立体表現
//
// 物理的な棚板の見た目:
//   上面（天板面）: 明るい茶色、奥から手前へ若干グラデ
//   正面エッジ: 下側の暗い面（奥行き）
//   上面前端ハイライト: 最も明るい1px
//   柱との接合部: 柱が横板を左右から挟んでいる
//     → 柱の正面で横板の端を覆う（_PillarsPainterで処理）
// ══════════════════════════════════════════════════════════════════
class _ShelfBoardPainter extends CustomPainter {
  const _ShelfBoardPainter({
    required this.wallW,
    required this.pilXs,
    required this.pilW,
  });
  final double wallW, pilW;
  final List<double> pilXs;

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width;

    // 棚板の上面（明るい面）
    // 奥（上）が暗く、手前（下端）が明るい（視点から最も近い面）
    final topRect = Rect.fromLTWH(0, 0, W, _kShelfTopH);
    canvas.drawRect(topRect,
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
        colors: const [
          Color(0xFF8A5022),   // 奥（暗め）
          Color(0xFFB87038),   // 手前（明るい）
          Color(0xFFCC8848),   // 前端ハイライト
        ],
        stops: const [0.0, 0.75, 1.0],
      ).createShader(topRect),
    );
    // 前端の白いハイライトライン（棚板の一番手前の角）
    canvas.drawLine(
      Offset(0, _kShelfTopH - 0.5),
      Offset(W, _kShelfTopH - 0.5),
      Paint()..color = Colors.white.withOpacity(0.55)..strokeWidth = 1.5,
    );

    // 棚板の正面（下面・暗い）= 奥行きを示す最重要エッジ
    final faceRect = Rect.fromLTWH(0, _kShelfTopH, W, _kShelfFaceH);
    canvas.drawRect(faceRect,
      Paint()..shader = LinearGradient(
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
        colors: const [
          Color(0xFF5A2A08),   // 上端（棚板上面との境）
          Color(0xFF2A0E02),   // 下端（影・最暗）
        ],
      ).createShader(faceRect),
    );
    // 上端の影ライン（上面と正面の境の角）
    canvas.drawLine(
      Offset(0, _kShelfTopH + 0.5),
      Offset(W, _kShelfTopH + 0.5),
      Paint()..color = Colors.black.withOpacity(0.50)..strokeWidth = 1.0,
    );
  }

  @override
  bool shouldRepaint(_) => false;
}

// ══════════════════════════════════════════════════════════════════
// _PillarsPainter — 縦板（柱）全本数
//
// 描画順（1本の柱につき）:
//   A. 側面（暗い面）← 本より手前、横板より手前
//   B. 正面（明るい面）← 最手前、横板の端を覆う
//
// 側面の幅:
//   sideW = _kPilSDMax * clamp(|dX| / (bayW*0.5), 0, 1)
//   ← bayWの半分スクロールで最大幅
//
// 本との重なり:
//   側面は本より手前（_PillarsPainterはBooksLayerより上のZ）
//   ただし本エリア内（後壁面）に描く側面は半透明にしない
//   → Stackの順序で制御（柱レイヤーが本レイヤーより上）
//
// 横板との接合（物理的正確性）:
//   縦板は横板に刺さる → 正面が横板の端を覆う
//   → 柱の正面はtotalH全体に描く（横板の高さも含む）
//   → 横板の端部（柱幅内）は柱正面で上書きされる
// ══════════════════════════════════════════════════════════════════
class _PillarsPainter extends CustomPainter {
  const _PillarsPainter({
    required this.wallW,
    required this.totalH,
    required this.camX,
    required this.pilXs,
    required this.bayW,
  });
  final double wallW, totalH, camX, bayW;
  final List<double> pilXs;

  @override
  void paint(Canvas canvas, Size size) {
    for (final px in pilXs) {
      final cx = px + _kPilW / 2;
      final dX = camX - cx;
      final t  = (dX.abs() / (bayW * 0.5)).clamp(0.0, 1.0);
      final sideW = _kPilSDMax * t;

      // A. 側面（正面の前に描く）
      if (sideW >= 0.5) {
        final sideX     = dX > 0 ? px + _kPilW : px - sideW;
        final gradBegin = dX > 0 ? Alignment.centerLeft  : Alignment.centerRight;
        final gradEnd   = dX > 0 ? Alignment.centerRight : Alignment.centerLeft;
        final sideRect  = Rect.fromLTWH(sideX, 0, sideW, totalH);
        canvas.drawRect(sideRect,
          Paint()..shader = LinearGradient(
            begin: gradBegin, end: gradEnd,
            colors: const [
              Color(0xFF160600),  // 接合エッジ（最暗）
              Color(0xFF3C1A06),  // 中間
              Color(0xFF704020),  // 外端
            ],
            stops: const [0.0, 0.35, 1.0],
          ).createShader(sideRect),
        );
        // 接合エッジの影ライン（正面と側面の境）
        final edgeX = dX > 0 ? px + _kPilW : px;
        canvas.drawLine(
          Offset(edgeX, 0), Offset(edgeX, totalH),
          Paint()..color = Colors.black.withOpacity(0.55)..strokeWidth = 1.2,
        );
      }

      // B. 正面（最手前・横板の端を覆う）
      final faceRect = Rect.fromLTWH(px, 0, _kPilW, totalH);
      // 柱正面グラデ（左から右へ: 左が明るく右が暗い = 光源が左上）
      canvas.drawRect(faceRect,
        Paint()..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end:   Alignment.centerRight,
          colors: const [
            Color(0xFFBE7840),  // 左（明るい）
            Color(0xFFA06030),  // 中央
            Color(0xFF884820),  // 右（やや暗い）
          ],
        ).createShader(faceRect),
      );
      // 前エッジ（柱の一番手前の角）白いライン
      canvas.drawLine(
        Offset(px + 0.5, 0), Offset(px + 0.5, totalH),
        Paint()..color = Colors.white.withOpacity(0.28)..strokeWidth = 1.0,
      );
      // 後エッジ（奥の角）暗いライン
      canvas.drawLine(
        Offset(px + _kPilW - 0.5, 0), Offset(px + _kPilW - 0.5, totalH),
        Paint()..color = Colors.black.withOpacity(0.32)..strokeWidth = 0.8,
      );

      // 横板との接合部の強調
      // 柱正面上に横板の端が見えないよう、接合部に影を追加
      // （柱正面が横板を完全に覆うのでこれは不要だが、接合部のリアリティ強化）
      // → 棚板が柱に刺さっている溝のような暗い線
      // totalH全体に一定間隔で横線（棚板ピッチで）
      // ※ここでは単純に正面グラデのみで十分
    }
  }

  @override
  bool shouldRepaint(_PillarsPainter o) => o.camX != camX;
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
        ? (rng.nextBool()?1:-1)*(0.12+rng.nextDouble()*0.14)
        : (rng.nextDouble()-0.5)*(pop.type==PopType.plate?0.04:0.20);
    return Transform.rotate(
      angle: tilt,
      alignment: pop.type==PopType.plate?Alignment.center:Alignment.bottomCenter,
      child: SizedBox(width:sz.width, height:sz.height,
        child:CustomPaint(painter:_PopPainter(style:style,type:pop.type),child:_popText())),
    );
  }
  Widget _popText() {
    final ip=pop.type==PopType.plate;
    return Padding(padding:EdgeInsets.fromLTRB(5,ip?4:10,5,ip?4:8),
      child:Center(child:Text(ip?style.text.replaceAll('\n',' '):style.text,
        textAlign:TextAlign.center,maxLines:ip?1:3,overflow:TextOverflow.ellipsis,
        style:TextStyle(color:style.fg,fontSize:ip?11:12.0,fontWeight:FontWeight.w900,
          height:1.4,letterSpacing:0.5,
          shadows:[Shadow(color:Colors.black.withOpacity(0.22),
              offset:const Offset(0,1),blurRadius:3)]))));
  }
}
class _PopPainter extends CustomPainter {
  const _PopPainter({required this.style, required this.type});
  final _PS style; final PopType type;
  @override
  void paint(Canvas canvas, Size s) {
    switch(type){case PopType.stand:_s(canvas,s);case PopType.plate:_p(canvas,s);case PopType.lean:_l(canvas,s);}
  }
  void _s(Canvas c,Size s){final b=RRect.fromRectAndRadius(Rect.fromLTWH(0,0,s.width,s.height*.92),const Radius.circular(3));_sh(c,Path()..addRRect(b));c.drawRRect(b,Paint()..color=style.bg);_gl(c,s,s.height*.92*.4);c.drawRect(Rect.fromLTWH(0,6,3.5,s.height*.92-12),Paint()..color=style.dark.withOpacity(.55));_bd(c,Path()..addRRect(b));c.drawPath(Path()..moveTo(s.width*.35,s.height*.92)..lineTo(s.width*.65,s.height*.92)..lineTo(s.width*.5,s.height)..close(),Paint()..color=style.dark);}
  void _p(Canvas c,Size s){final b=RRect.fromRectAndRadius(Rect.fromLTWH(0,0,s.width,s.height),Radius.circular(s.height/2));_sh(c,Path()..addRRect(b));c.drawRRect(b,Paint()..color=style.bg);_gl(c,s,s.height*.55);_bd(c,Path()..addRRect(b));c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0,0,6,s.height),Radius.circular(s.height/2)),Paint()..color=style.dark.withOpacity(.7));}
  void _l(Canvas c,Size s){final b=Path()..moveTo(3,1)..lineTo(s.width-2,0)..lineTo(s.width-1,s.height-2)..lineTo(1,s.height-1)..close();_sh(c,b);c.drawPath(b,Paint()..color=style.bg);_gl(c,s,s.height*.38);for(double y=s.height*.65;y<s.height-4;y+=9)c.drawLine(Offset(6,y),Offset(s.width-6,y),Paint()..color=Colors.black.withOpacity(.08)..strokeWidth=.8);_bd(c,b);}
  void _sh(Canvas c,Path p)=>c.drawPath(p.shift(const Offset(2.5,4)),Paint()..color=Colors.black.withOpacity(.3)..maskFilter=const MaskFilter.blur(BlurStyle.normal,8));
  void _gl(Canvas c,Size s,double h)=>c.drawRect(Rect.fromLTWH(0,0,s.width,h),Paint()..shader=LinearGradient(begin:Alignment.topCenter,end:Alignment.bottomCenter,colors:[Colors.white.withOpacity(.32),Colors.transparent]).createShader(Rect.fromLTWH(0,0,s.width,h)));
  void _bd(Canvas c,Path p)=>c.drawPath(p,Paint()..color=Colors.black.withOpacity(.13)..style=PaintingStyle.stroke..strokeWidth=.9);
  @override bool shouldRepaint(_)=>false;
}
