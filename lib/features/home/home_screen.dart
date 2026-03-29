import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../data/models/game.dart';
import '../../data/repositories/game_provider.dart';
import '../../data/repositories/saved_games_provider.dart';
import '../../shelf/shelf_wall.dart';
import '../saved/saved_shelf_screen.dart';
import '../search/search_screen.dart';

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
            colors: [Color(0xCC0C0600), Color(0x99180C00), Color(0xBB1A0E02)],
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
class _StoreContent extends ConsumerStatefulWidget {
  const _StoreContent({required this.games});
  final List<Game> games;
  @override ConsumerState<_StoreContent> createState() => _StoreContentState();
}

class _StoreContentState extends ConsumerState<_StoreContent> {
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
              child: RepaintBoundary(
                child: ShelfWall(
                  games: widget.games,
                  rows: buildShelfRows(widget.games,
                      seedOffset: ref.watch(shelfSeedProvider)),
                  wallWidth: wallW,
                  viewportOffset: _viewportOffset,
                  viewportOffsetY: _viewportOffsetY,
                  viewportWidth:  screenW,
                  viewportHeight: constraints.maxHeight,
                  viewportScale:  _viewportScale,
                ),
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

class _TopBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.of(context).padding.top;
    final savedCount = ref.watch(savedIdsProvider).length;
    return Padding(
      padding: EdgeInsets.only(top: top + 8, right: 16),
      child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _GlassBtn(
          icon: Icons.search_rounded,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SearchScreen())),
        ),
        const SizedBox(width: 8),
        _SavedShelfBtn(count: savedCount),
        const SizedBox(width: 8),
        _GlassBtn(
          icon: Icons.shuffle_rounded,
          onTap: () {
            ref.read(shelfSeedProvider.notifier).state =
                DateTime.now().millisecondsSinceEpoch % 99991;
          },
        ),
        const SizedBox(width: 8),
        _GlassBtn(
          icon: Icons.info_outline_rounded,
          onTap: () => _showInfoSheet(context),
        ),
      ]),
    );
  }

  void _showInfoSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _InfoSheet(),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn({required this.icon, this.onTap});
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: ClipRRect(
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
    ),
  );
}

class _SavedShelfBtn extends StatelessWidget {
  const _SavedShelfBtn({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const SavedShelfScreen())),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.32),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: count > 0
                    ? const Color(0xFFD09248).withOpacity(0.60)
                    : Colors.white.withOpacity(0.14),
                width: 0.7),
          ),
          child: Stack(children: [
            Center(child: Icon(Icons.bookmark_rounded,
                size: 17,
                color: count > 0
                    ? const Color(0xFFD09248)
                    : Colors.white.withOpacity(0.88))),
            if (count > 0)
              Positioned(
                right: 3, top: 3,
                child: Container(
                  width: 13, height: 13,
                  decoration: const BoxDecoration(
                    color: Color(0xFFD09248),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text('$count',
                        style: const TextStyle(
                            fontSize: 7, fontWeight: FontWeight.w800,
                            color: Colors.black, height: 1.0)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Info bottom sheet（プライバシーポリシー・利用規約）
// ─────────────────────────────────────────────────────────────────────────────
class _InfoSheet extends StatelessWidget {
  const _InfoSheet();

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _requestReview(BuildContext context) async {
    Navigator.of(context).pop();
    final review = InAppReview.instance;
    if (await review.isAvailable()) {
      await review.requestReview();
    } else {
      await review.openStoreListing();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E1000),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ハンドル
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Text('PocketPlay',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('v1.0.0',
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.35), fontSize: 12)),
          ]),
          const SizedBox(height: 16),
          _InfoRow(
            icon: Icons.star_rounded,
            label: 'アプリを評価する',
            accent: const Color(0xFFFFCC44),
            onTap: () => _requestReview(context),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.privacy_tip_outlined,
            label: 'プライバシーポリシー',
            onTap: () => _launch(AppConstants.privacyPolicyUrl),
          ),
          const SizedBox(height: 8),
          _InfoRow(
            icon: Icons.description_outlined,
            label: '利用規約',
            onTap: () => _launch(AppConstants.termsOfServiceUrl),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(
      {required this.icon, required this.label, required this.onTap, this.accent});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final iconColor = accent ?? const Color(0xFFD09248);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 0.7),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.35), size: 13),
          ],
        ),
      ),
    );
  }
}
