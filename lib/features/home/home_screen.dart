import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/game.dart';
import '../../data/repositories/game_provider.dart';
import '../../shelf/shelf_wall.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    final gamesAsync = ref.watch(gamesProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF1A0E00),
      body: Stack(
        children: [
          const Positioned.fill(child: _StoreAmbience()),
          const Positioned.fill(child: _CeilingLights()),
          Positioned.fill(
            child: gamesAsync.when(
              loading: () => const _LoadingView(),
              error:   (_, __) => _StoreContent(games: kSeedGames),
              data:    (games) => _StoreContent(games: games),
            ),
          ),
          Positioned(top: 0, left: 0, right: 0, child: _TopBar()),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Store ambience
// ─────────────────────────────────────────────────────────────────────────────
class _StoreAmbience extends StatelessWidget {
  const _StoreAmbience();
  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
        child: Image.asset('assets/store/store_background.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: const Color(0xFF3D2000))),
      ),
      Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xF00C0600), Color(0xBB180C00), Color(0xDD1A0E02)],
            stops: [0.0, 0.38, 1.0],
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ceiling pendant lights — fixed to screen
// ─────────────────────────────────────────────────────────────────────────────
class _CeilingLights extends StatelessWidget {
  const _CeilingLights();
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return Stack(children: [
      _PendantLight(x: w * 0.15, cordLen: 72),
      _PendantLight(x: w * 0.48, cordLen: 58),
      _PendantLight(x: w * 0.80, cordLen: 80),
    ]);
  }
}

class _PendantLight extends StatelessWidget {
  const _PendantLight({required this.x, required this.cordLen});
  final double x, cordLen;
  @override
  Widget build(BuildContext context) => Positioned(
    left: x - 80, top: 0,
    child: SizedBox(width: 160, height: cordLen + 160,
        child: CustomPaint(painter: _PendantPainter(cordLen: cordLen))),
  );
}

class _PendantPainter extends CustomPainter {
  const _PendantPainter({required this.cordLen});
  final double cordLen;
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    canvas.drawLine(Offset(cx, 0), Offset(cx, cordLen),
        Paint()..color = Colors.white.withOpacity(0.22)..strokeWidth = 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx, cordLen + 5), width: 10, height: 7),
        const Radius.circular(2)),
      Paint()..color = const Color(0xFF887860),
    );
    final bulb = Offset(cx, cordLen + 16);
    canvas.drawCircle(bulb, 18,
        Paint()..color = const Color(0xFFFFEE88).withOpacity(0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12));
    canvas.drawCircle(bulb, 9.5,
        Paint()..color = const Color(0xFFFFEE99)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    canvas.drawCircle(bulb, 5, Paint()..color = Colors.white);
    for (int i = 0; i < 5; i++) {
      final r  = 50.0 + i * 40;
      final oy = cordLen + 16 + 30 + i * 25;
      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, oy), width: r * 2.0, height: r * 0.45),
        Paint()..color = const Color(0xFFFFCC44).withOpacity(0.09 - i * 0.014)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22),
      );
    }
  }
  @override bool shouldRepaint(_) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Store content
// ─────────────────────────────────────────────────────────────────────────────
class _StoreContent extends StatefulWidget {
  const _StoreContent({required this.games});
  final List<Game> games;
  @override State<_StoreContent> createState() => _StoreContentState();
}

class _StoreContentState extends State<_StoreContent> {
  final _tc = TransformationController();
  bool _initialized = false;
  double _viewportOffset = 0.0;
  double _viewportOffsetY = 0.0;
  double _viewportScale  = 1.0;

  @override
  void initState() {
    super.initState();
    _tc.addListener(_onTransform);
  }

  @override
  void dispose() { _tc.removeListener(_onTransform); _tc.dispose(); super.dispose(); }

  void _onTransform() {
    final tx = -_tc.value.getTranslation().x;
    final ty = -_tc.value.getTranslation().y;
    final scale = _tc.value.getMaxScaleOnAxis();
    final offset = tx / scale;
    final offsetY = ty / scale;
    if ((offset - _viewportOffset).abs() > 0.5 ||
        (offsetY - _viewportOffsetY).abs() > 0.5 ||
        (scale - _viewportScale).abs() > 0.01) {
      setState(() {
        _viewportOffset = offset;
        _viewportOffsetY = offsetY;
        _viewportScale  = scale;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad  = MediaQuery.of(context).padding.top;
    final screenW = MediaQuery.of(context).size.width;
    final wallW   = screenW * 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(20, topPad + 50, 20, 16),
          child: _AppTitle(),
        ),
        Expanded(
          child: LayoutBuilder(builder: (ctx, constraints) {
            if (!_initialized) {
              _initialized = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _tc.value = Matrix4.identity();
              });
            }
            return InteractiveViewer(
              transformationController: _tc,
              minScale: 0.38,
              maxScale: 2.8,
              constrained: false,
              boundaryMargin: const EdgeInsets.symmetric(
                  horizontal: 0, vertical: 60),
              child: ShelfWall(
                games: widget.games,
                rows: kShelfRows,
                wallWidth: wallW,
                viewportOffset: _viewportOffset,
                viewportOffsetY: _viewportOffsetY,
                viewportWidth:  screenW,
                viewportHeight: constraints.maxHeight,
                viewportScale:  _viewportScale,
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _AppTitle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisSize: MainAxisSize.min,
    children: [
      const Text('PocketPlay',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900,
              letterSpacing: -0.5, color: Colors.white, height: 1.0)),
      const SizedBox(height: 4),
      Text('棚から見つける、ボードゲームの世界',
          style: TextStyle(fontSize: 11.5,
              color: Colors.white.withOpacity(0.55))),
      const SizedBox(height: 10),
      Row(children: [
        Icon(Icons.open_with_rounded, size: 11,
            color: Colors.white.withOpacity(0.32)),
        const SizedBox(width: 4),
        Text('ドラッグ・ピンチで棚を探索',
            style: TextStyle(fontSize: 10,
                color: Colors.white.withOpacity(0.32))),
      ]),
    ],
  );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(width: 22, height: 22,
          child: CircularProgressIndicator(strokeWidth: 2,
              color: Color(0xFFFFD080))),
      const SizedBox(height: 14),
      Text('棚を準備中...', style: TextStyle(
          color: Colors.white.withOpacity(0.45),
          fontSize: 11, letterSpacing: 1.5)),
    ]),
  );
}

class _TopBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, right: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _GlassBtn(icon: Icons.search_rounded),
        const SizedBox(width: 8),
        _GlassBtn(icon: Icons.bookmark_border_rounded),
      ]),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({required this.icon});
  final IconData icon;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(10),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.32),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withOpacity(0.14), width: 0.7),
        ),
        child: Icon(icon, size: 17, color: Colors.white.withOpacity(0.88)),
      ),
    ),
  );
}
