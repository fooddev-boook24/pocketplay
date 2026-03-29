import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../data/models/game.dart';
import 'shelf_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TappableBox — アニメーション付きタップラッパー（既存描画コード不変）
// Phase 1: press-in 80ms (scale 1.0→0.96)
// Phase 2: fly-out 140ms (scale 0.96→1.08, translateY 0→-8px)
// Phase 3: Hero遷移（onTapコールバック呼び出し）
// ─────────────────────────────────────────────────────────────────────────────
class TappableBox extends StatefulWidget {
  const TappableBox({
    super.key,
    required this.heroTag,
    required this.child,
    required this.onTap,
  });
  final String heroTag;
  final Widget child;
  final VoidCallback onTap;

  @override
  State<TappableBox> createState() => _TappableBoxState();
}

class _TappableBoxState extends State<TappableBox>
    with TickerProviderStateMixin {
  // ── タップアニメーション ──────────────────────────────────────────
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _translateY;

  // ── ホバー（長押し）アニメーション ───────────────────────────────
  late final AnimationController _hoverCtrl;
  late final Animation<double> _hoverScale;
  late final Animation<double> _hoverTranslate;
  bool _longPressActive = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 480),
    );
    _scale = TweenSequence<double>([
      // Phase 1: press-in 100ms (weight 21 = 100/480)
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.93)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 21,
      ),
      // Phase 2: hold 80ms
      TweenSequenceItem(
        tween: ConstantTween(0.93),
        weight: 17,
      ),
      // Phase 3: fly-out 300ms (weight 62 = 300/480)
      TweenSequenceItem(
        tween: Tween(begin: 0.93, end: 1.12)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 62,
      ),
    ]).animate(_ctrl);
    _translateY = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 38),
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -14.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 62,
      ),
    ]).animate(_ctrl);

    // ホバー: ゆっくり浮き上がって停止
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _hoverScale = Tween<double>(begin: 1.0, end: 1.06)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_hoverCtrl);
    _hoverTranslate = Tween<double>(begin: 0.0, end: -7.0)
        .chain(CurveTween(curve: Curves.easeOut))
        .animate(_hoverCtrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _hoverCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    _ctrl.animateTo(0.38, duration: const Duration(milliseconds: 180));
  }

  void _onTapUp(TapUpDetails _) {
    _ctrl
        .animateTo(1.0, duration: const Duration(milliseconds: 300))
        .then((_) {
      if (mounted) {
        widget.onTap();
        _ctrl.reset();
      }
    });
  }

  void _onTapCancel() {
    // 長押し認識時は _onTapCancel が発火するが、ホバーに移行するためリセットしない
    if (!_longPressActive) {
      _ctrl.animateTo(0.0, duration: const Duration(milliseconds: 150));
    }
  }

  void _onLongPressStart(LongPressStartDetails _) {
    _longPressActive = true;
    // 押し込み状態からホバー状態へ切り替え
    _ctrl.animateTo(0.0, duration: const Duration(milliseconds: 120));
    _hoverCtrl.forward();
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    _longPressActive = false;
    _hoverCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      child: Hero(
        tag: widget.heroTag,
        child: AnimatedBuilder(
          animation: Listenable.merge([_ctrl, _hoverCtrl]),
          builder: (_, child) {
            // タップアニメーション優先、待機中のみホバーを適用
            final tapActive = _ctrl.value > 0;
            final s  = tapActive ? _scale.value     : _hoverScale.value;
            final ty = tapActive ? _translateY.value : _hoverTranslate.value;
            return Transform.translate(
              offset: Offset(0, ty),
              child: Transform.scale(scale: s, child: child),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

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
        filterQuality: FilterQuality.high,
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
          filterQuality: FilterQuality.high,
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
    final base  = game.spineColor;
    final light = _lt(base, 0.18);
    final dark  = _dk(base, 0.22);

    if (isSpine) {
      // 背表紙フォールバック: 縦グラデ + アクセントライン + タイトル
      return SizedBox(width: w, height: h,
        child: Stack(children: [
          Positioned.fill(child: Container(decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter, end: Alignment.bottomCenter,
              colors: [light, base, dark],
              stops: const [0.0, 0.5, 1.0],
            ),
          ))),
          // 左エッジハイライト
          Positioned(left: 0, top: 0, bottom: 0, width: 1.5,
            child: Container(color: Colors.white.withOpacity(0.25))),
          // 右エッジシャドウ
          Positioned(right: 0, top: 0, bottom: 0, width: 1.5,
            child: Container(color: Colors.black.withOpacity(0.30))),
          // タイトル
          Center(child: RotatedBox(quarterTurns: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(game.title, maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: game.spineTextColor,
                  fontSize: (w * 0.30).clamp(6.5, 11.5),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                  shadows: [Shadow(
                    color: Colors.black.withOpacity(0.50),
                    blurRadius: 3)],
                )),
            ))),
        ]),
      );
    }

    // 正面フォールバック: 対角グラデ + タイトル帯
    return SizedBox(width: w, height: h,
      child: Stack(children: [
        Positioned.fill(child: Container(decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [light, base, dark],
            stops: const [0.0, 0.55, 1.0],
          ),
        ))),
        // 上部暗め帯（奥行き感）
        Positioned(top: 0, left: 0, right: 0, height: h * 0.18,
          child: Container(color: dark.withOpacity(0.45))),
        // タイトル帯
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            padding: EdgeInsets.fromLTRB(5, h * 0.08, 5, 6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black.withOpacity(0.72)],
              ),
            ),
            child: Text(game.title,
              textAlign: TextAlign.center,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: (w * 0.10).clamp(9.0, 14.0),
                fontWeight: FontWeight.w800,
                height: 1.2,
                shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
              )),
          )),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FaceBoxWidget — ライティングオーバーレイ方式
//   天板・側面パネルなし。正面画像のみに光と影を重ねてリアリティを演出。
//   perspFactor: 見下ろし角度（上部ハイライト強度に影響）
//   sideT:       カメラ水平角度（遠い側のAO強度に影響）
//   showRightSide: カメラから見て右側が近い
// ─────────────────────────────────────────────────────────────────────────────
class FaceBoxWidget extends StatelessWidget {
  const FaceBoxWidget({super.key, required this.p, this.onTap,
    this.perspFactor = 1.0, this.sideT = 0.5, this.showRightSide = true});
  final PlacedBox p;
  final VoidCallback? onTap;
  final double perspFactor;
  final double sideT;
  final bool showRightSide;

  @override
  Widget build(BuildContext context) {
    // 見下ろし角度が大きいほど上部ハイライトが強くなる
    final topGlow   = ((perspFactor - 0.5) * 0.05).clamp(0.0, 0.07);
    // カメラ角度が大きいほど遠い側がわずかに暗くなる（AO）
    final sideShade = (sideT * 0.10).clamp(0.0, 0.10);

    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: p.tilt,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: p.width, height: p.height,
          child: Stack(clipBehavior: Clip.none, children: [

            // ── 棚面への影（底部直下のみ・浮かない） ─────────────────
            Positioned(left: 3, right: 3, bottom: -5, height: 10,
              child: Container(decoration: BoxDecoration(
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.50),
                  blurRadius: 10, spreadRadius: 1,
                )],
              ))),

            // ── カバー画像（全面） ────────────────────────────────────
            Positioned.fill(child: ClipRect(child: GameImage(
              game: p.game, fit: BoxFit.cover,
              width: p.width, height: p.height))),

            // ── 縦方向ライティング ────────────────────────────────────
            // 天井光: 上端に薄い白 → 透明 / 棚底: 下端に薄い黒
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withOpacity(0.08 + topGlow),
                  Colors.transparent,
                  Colors.black.withOpacity(0.14),
                ],
                stops: const [0.0, 0.22, 1.0],
              ),
            ))),

            // ── 横方向AO（隣の箱との密着感・左右端を暗く） ──────────
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  Colors.black.withOpacity(0.12),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withOpacity(0.12),
                ],
                stops: const [0.0, 0.20, 0.80, 1.0],
              ),
            ))),

            // ── カメラ角度AO（遠い側をわずかに暗く） ─────────────────
            if (sideShade > 0.01)
              Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: showRightSide
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  end: showRightSide
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  colors: [
                    Colors.black.withOpacity(sideShade),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.32],
                ),
              ))),

            // ── 上端稜線（前面上辺の明るいエッジ） ───────────────────
            Positioned(top: 0, left: 0, right: 0, height: 1.5,
              child: Container(color: Colors.white.withOpacity(0.50))),

          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SpineBoxWidget — spineColor tint + 上部画像 + 大きなタイトルで背表紙らしさを演出
// ─────────────────────────────────────────────────────────────────────────────
class SpineBoxWidget extends StatelessWidget {
  const SpineBoxWidget({super.key, required this.p, this.onTap, this.perspFactor = 1.0});
  final PlacedBox p;
  final VoidCallback? onTap;
  final double perspFactor;

  @override
  Widget build(BuildContext context) {
    final c = p.game.spineColor;
    final baseCapH = (p.width * 0.32).clamp(4.0, 12.0);
    final capH = (baseCapH * perspFactor.clamp(0.15, 2.0)).clamp(1.5, baseCapH * 2.0);

    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: p.tilt,
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: p.width, height: p.height,
          child: Stack(clipBehavior: Clip.none, children: [

            // ドロップシャドウ
            Positioned(left: 1, top: 2, right: -3, bottom: -4,
              child: Container(decoration: BoxDecoration(
                boxShadow: [BoxShadow(
                  color: Colors.black.withOpacity(0.42),
                  offset: const Offset(1, 5),
                  blurRadius: 8, spreadRadius: -2)],
              ))),

            // ① 背景: カバー画像（上部を表示 — ロゴ・タイトルが多い）
            Positioned.fill(
              child: ClipRect(child: GameImage(game: p.game,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                width: p.width, height: p.height)),
            ),

            // ② spineColor カラーコーティング（識別色 + 統一感）
            Positioned.fill(child: Container(color: c.withOpacity(0.68))),

            // ③ 上下グラデーション（立体感・奥行き）
            Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.35),
                  Colors.transparent,
                  Colors.black.withOpacity(0.55),
                ],
                stops: const [0.0, 0.30, 1.0],
              ),
            ))),

            // ④ タイトル（中央配置、全高を活かして大きく）
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Center(child: RotatedBox(quarterTurns: 3,
                  child: Text(p.game.title, maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: p.game.spineTextColor,
                      fontSize: (p.width * 0.36).clamp(7.5, 13.5),
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                      shadows: [
                        Shadow(color: Colors.black.withOpacity(0.75),
                          blurRadius: 6),
                        Shadow(color: Colors.black.withOpacity(0.40),
                          offset: const Offset(0, 1), blurRadius: 2),
                      ],
                    )),
                )),
              ),
            ),

            // ⑤ 左エッジ（ハイライト）
            Positioned(left: 0, top: 0, bottom: 0, width: 1.5,
              child: Container(color: Colors.white.withOpacity(0.28))),
            // ⑥ 右エッジ（シャドウ）
            Positioned(right: 0, top: 0, bottom: 0, width: 1.5,
              child: Container(color: Colors.black.withOpacity(0.48))),

            // ⑦ 天板キャップ
            Positioned(top: -capH, left: 0, right: 0, height: capH,
              child: Container(decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [_lt(c, 0.32), _lt(c, 0.10)],
                ),
              ))),
          ]),
        ),
      ),
    );
  }

  Color _lt(Color c, double d) {
    final h = HSLColor.fromColor(c);
    return h.withLightness((h.lightness + d).clamp(0, 1)).toColor();
  }
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
