import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/ad_banner.dart';
import '../../data/models/game.dart';
import '../../data/models/game_detail.dart';
import '../../data/repositories/game_provider.dart';
import '../../data/repositories/saved_games_provider.dart';
import '../../data/services/affiliate_service.dart';
import '../../shelf/box_widgets.dart';
import '../search/search_screen.dart';

// ─── ストアレビュー: 5回目の詳細閲覧でリクエスト ────────────────────────────
class _ReviewService {
  static int _count = 0;
  static bool _requested = false;

  static Future<void> onDetailViewed() async {
    if (_requested) return;
    _count++;
    if (_count >= 5) {
      _requested = true;
      final review = InAppReview.instance;
      if (await review.isAvailable()) {
        await review.requestReview();
      }
    }
  }
}

class GameDetailScreen extends HookConsumerWidget {
  const GameDetailScreen({
    super.key,
    required this.game,
    required this.heroTag,
  });
  final Game game;
  final String heroTag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    // 詳細画面を開くたびにカウント（5回目でストアレビューリクエスト）
    useEffect(() {
      _ReviewService.onDetailViewed();
      return null;
    }, const []);

    final detailAsync = ref.watch(gameDetailProvider(game));
    final detail = detailAsync.maybeWhen(
      data: (d) => d,
      orElse: () => GameDetail(game: game),
    );
    final isLoading = detailAsync.isLoading;
    return Scaffold(
      backgroundColor: const Color(0xFF120900),
      bottomNavigationBar: const AdBannerWidget(),
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // ヘッダー（タイトル・レーティングを内包）
              SliverToBoxAdapter(
                child: _Hero(
                  game: detail.game,
                  heroTag: heroTag,
                ),
              ),
              // スペック
              if (_hasStats(detail))
                SliverToBoxAdapter(child: _StatsRow(detail: detail)),
              // カテゴリ
              if (detail.game.categories.isNotEmpty)
                SliverToBoxAdapter(
                    child: _CategoryRow(categories: detail.game.categories)),
              // 説明
              if (detail.game.description != null &&
                  detail.game.description!.isNotEmpty)
                SliverToBoxAdapter(
                    child: _DescriptionSection(text: detail.game.description!)),
              // 購入
              SliverToBoxAdapter(
                child: _PurchaseSection(game: detail.game),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 48),
              ),
            ],
          ),
          // 戻るボタン（左上）
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: const _BackButton(),
          ),
          // 保存ボタン（右上）
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 60,
            child: _SaveButton(game: detail.game),
          ),
          // シェアボタン（右上）
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _ShareButton(game: detail.game),
          ),
        ],
      ),
    );
  }

  bool _hasStats(GameDetail d) =>
      d.game.playersLabel != '-' ||
      d.game.timeLabel != '-' ||
      d.complexity != null;
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero エリア（ぼかし背景 + ゲームボックス + タイトル + レーティング）
// ─────────────────────────────────────────────────────────────────────────────
class _Hero extends StatelessWidget {
  const _Hero({required this.game, required this.heroTag});
  final Game game;
  final String heroTag;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenW = mq.size.width;
    final boxW = screenW * 0.52;
    final boxH = boxW / game.faceAspect;
    // ヘッダー高さ = ステータスバー + 上余白 + ボックス + タイトルエリア
    final headerH = mq.padding.top + 24 + boxH + 100;

    return SizedBox(
      height: headerH,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── ぼかし背景（thumbnailUrlを優先、なければimageUrl、最後はSwatch）
          Positioned.fill(
            child: ClipRect(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                child: _buildBgImage(game, screenW, headerH),
              ),
            ),
          ),
          // ── グラデーション（上：半透明 → 下：完全に0xFF120900）
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xBB120900), // 上部：ある程度暗く
                    Color(0x22120900), // 中央：画像を透かす
                    Color(0xEE120900), // 下部：ほぼ塗りつぶし
                    Color(0xFF120900), // 最下部：完全に背景色と一致
                  ],
                  stops: [0.0, 0.35, 0.72, 1.0],
                ),
              ),
            ),
          ),
          // ── ゲームボックス（Hero）
          Positioned(
            top: mq.padding.top + 24,
            left: 0,
            right: 0,
            child: Center(
              child: Hero(
                tag: heroTag,
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.65),
                        blurRadius: 48,
                        spreadRadius: -8,
                        offset: const Offset(0, 20),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: GameImage(
                      game: game,
                      fit: BoxFit.cover,
                      width: boxW,
                      height: boxH,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // ── タイトル＋レーティング（グラデーション上に重ねる）
          Positioned(
            bottom: 0,
            left: 20,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  game.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.1,
                    shadows: [
                      Shadow(
                          color: Color(0xFF000000),
                          blurRadius: 20,
                          offset: Offset(0, 2)),
                    ],
                  ),
                ),
                if (game.bggRating != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: Color(0xFFFFCC55), size: 15),
                      const SizedBox(width: 3),
                      Text(
                        game.bggRating!.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Color(0xFFFFCC55),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/ 10  BGGスコア',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.38),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBgImage(Game game, double w, double h) {
    final url = game.thumbnailUrl ?? game.imageUrl;
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: w,
        height: h,
        fadeInDuration: const Duration(milliseconds: 300),
        errorWidget: (_, __, ___) => GameImage(game: game, fit: BoxFit.cover),
      );
    }
    return GameImage(game: game, fit: BoxFit.cover, width: w, height: h);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// スペック行
// ─────────────────────────────────────────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.detail});
  final GameDetail detail;

  @override
  Widget build(BuildContext context) {
    final g = detail.game;
    final items = <_StatItem>[];
    if (g.playersLabel != '-') {
      items.add(_StatItem(
          icon: Icons.group_rounded, value: g.playersLabel, label: 'プレイ人数'));
    }
    if (g.timeLabel != '-') {
      items.add(_StatItem(
          icon: Icons.timer_outlined, value: g.timeLabel, label: 'プレイ時間'));
    }
    if (detail.complexity != null) {
      items.add(_StatItem(
          icon: Icons.psychology_outlined,
          value: detail.complexityLabel,
          label: '難易度'));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0)
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: Colors.white.withValues(alpha: 0.12),
              ),
            _StatWidget(item: items[i]),
          ],
        ],
      ),
    );
  }
}

class _StatItem {
  const _StatItem(
      {required this.icon, required this.value, required this.label});
  final IconData icon;
  final String value;
  final String label;
}

class _StatWidget extends StatelessWidget {
  const _StatWidget({required this.item});
  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(item.icon, color: const Color(0xFFD09248), size: 17),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.value,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Text(item.label,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.38),
                    fontSize: 10)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// カテゴリタグ
// ─────────────────────────────────────────────────────────────────────────────
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({required this.categories});
  final List<String> categories;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        children: [
          for (final c in categories.take(6))
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFD09248).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: const Color(0xFFD09248).withValues(alpha: 0.28),
                    width: 0.7),
              ),
              child: Text(c,
                  style: const TextStyle(
                      color: Color(0xFFD09248),
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 説明文
// ─────────────────────────────────────────────────────────────────────────────
class _DescriptionSection extends StatefulWidget {
  const _DescriptionSection({required this.text});
  final String text;

  @override
  State<_DescriptionSection> createState() => _DescriptionSectionState();
}

class _DescriptionSectionState extends State<_DescriptionSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('ゲーム紹介'),
          const SizedBox(height: 10),
          LayoutBuilder(builder: (ctx, constraints) {
            final tp = TextPainter(
              text: TextSpan(
                  text: widget.text,
                  style: const TextStyle(fontSize: 14, height: 1.75)),
              maxLines: 4,
              textDirection: TextDirection.ltr,
            )..layout(maxWidth: constraints.maxWidth);
            final overflow = tp.didExceedMaxLines;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.text,
                  maxLines: _expanded ? null : 4,
                  overflow:
                      _expanded ? TextOverflow.visible : TextOverflow.fade,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 14,
                      height: 1.75),
                ),
                if (overflow) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Text(_expanded ? '閉じる ▲' : 'もっと見る ▼',
                        style: const TextStyle(
                            color: Color(0xFFD09248),
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 購入ボタン
// ─────────────────────────────────────────────────────────────────────────────
class _PurchaseSection extends StatelessWidget {
  const _PurchaseSection({required this.game});
  final Game game;

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Label('購入する'),
          const SizedBox(height: 12),
          _BuyButton(
            label: 'Amazonで見る',
            sublabel: 'Amazon.co.jp で検索',
            color: const Color(0xFFE07800),
            icon: Icons.shopping_bag_outlined,
            onTap: () => _launch(AffiliateService.buildAmazonSearchUrl(game)),
          ),
          const SizedBox(height: 10),
          _BuyButton(
            label: '楽天で見る',
            sublabel: '楽天市場で検索',
            color: const Color(0xFFBF0000),
            icon: Icons.storefront_outlined,
            onTap: () => _launch(AffiliateService.buildRakutenSearchUrl(game)),
          ),
        ],
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({
    required this.label,
    required this.sublabel,
    required this.color,
    required this.icon,
    required this.onTap,
    this.loading = false,
  });
  final String label;
  final String sublabel;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !loading;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled || loading ? 1.0 : 0.36,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: enabled ? color : Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
                    BoxShadow(
                        color: color.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 5))
                  ]
                : null,
          ),
          child: Row(
            children: [
              const SizedBox(width: 18),
              loading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withValues(alpha: 0.55)))
                  : Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800)),
                    Text(sublabel,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.60),
                            fontSize: 11)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: Colors.white.withValues(alpha: 0.45), size: 13),
              const SizedBox(width: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 共通
// ─────────────────────────────────────────────────────────────────────────────
class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
            color: Colors.white.withValues(alpha: 0.38),
            fontSize: 11,
            fontWeight: FontWeight.w600));
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15), width: 0.7),
            ),
            child: Icon(Icons.arrow_back_ios_new_rounded,
                size: 17, color: Colors.white.withValues(alpha: 0.90)),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 保存ボタン（ブックマーク）
// ─────────────────────────────────────────────────────────────────────────────
class _SaveButton extends ConsumerWidget {
  const _SaveButton({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSaved = ref.watch(savedIdsProvider).contains(game.id);
    return GestureDetector(
      onTap: () => ref.read(savedIdsProvider.notifier).toggle(game.id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: isSaved
                  ? const Color(0xFFD09248).withOpacity(0.85)
                  : Colors.black.withOpacity(0.32),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: Colors.white.withOpacity(isSaved ? 0.30 : 0.14),
                  width: 0.7),
            ),
            child: Icon(
              isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
              size: 18,
              color: isSaved ? Colors.white : Colors.white.withOpacity(0.88),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// シェアボタン
// ─────────────────────────────────────────────────────────────────────────────
class _ShareButton extends StatelessWidget {
  const _ShareButton({required this.game});
  final Game game;

  Future<void> _share(BuildContext context) async {
    final sb = StringBuffer();
    sb.write('「${game.title}」をPocketPlayで発見！');
    if (game.bggRating != null) {
      sb.write('\n⭐ BGGスコア ${game.bggRating!.toStringAsFixed(1)}/10');
    }
    if (game.playersLabel != '-') {
      sb.write('\n👥 ${game.playersLabel}');
    }
    sb.write('\n\n#ボードゲーム #PocketPlay');
    final box = context.findRenderObject() as RenderBox?;
    final origin =
        box != null ? box.localToGlobal(Offset.zero) & box.size : null;
    await Share.share(sb.toString(), sharePositionOrigin: origin);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _share(context),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.40),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15), width: 0.7),
            ),
            child: Icon(Icons.ios_share_rounded,
                size: 17, color: Colors.white.withValues(alpha: 0.90)),
          ),
        ),
      ),
    );
  }
}
