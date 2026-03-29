import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ad_banner.dart';
import '../../data/models/game.dart';
import '../../data/repositories/saved_games_provider.dart';
import '../../shelf/box_widgets.dart';
import '../game_detail/game_detail_screen.dart';

class SavedShelfScreen extends ConsumerWidget {
  const SavedShelfScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final savedGames = ref.watch(savedGamesSortedProvider);
    final mq        = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0E00),
      bottomNavigationBar: const AdBannerWidget(),
      body: Stack(children: [
        Positioned.fill(child: _Ambience()),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ヘッダー
          Padding(
            padding: EdgeInsets.fromLTRB(20, mq.padding.top + 12, 20, 12),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: Colors.white.withOpacity(0.80)),
              ),
              const SizedBox(width: 14),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('MY SHELF',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                        letterSpacing: 1.0, color: Colors.white, height: 1.0)),
                const SizedBox(height: 3),
                Text('${savedGames.length}タイトル保存中',
                    style: TextStyle(fontSize: 11,
                        color: Colors.white.withOpacity(0.50))),
              ]),
              const Spacer(),
              if (savedGames.isNotEmpty) const _SortButton(),
            ]),
          ),
          // グリッド or 空状態
          Expanded(
            child: savedGames.isEmpty
                ? _EmptyState()
                : _GameGrid(games: savedGames),
          ),
        ]),
      ]),
    );
  }
}

// ─── 背景ぼかし ───────────────────────────────────────────────────────────
class _Ambience extends StatelessWidget {
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
      Container(decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color(0xF00C0600), Color(0xBB180C00), Color(0xDD1A0E02)],
          stops: [0.0, 0.38, 1.0],
        ),
      )),
    ]);
  }
}

// ─── ゲームグリッド ────────────────────────────────────────────────────────
class _GameGrid extends StatelessWidget {
  const _GameGrid({required this.games});
  final List<Game> games;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 48),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.62,
        mainAxisSpacing: 16,
        crossAxisSpacing: 10,
      ),
      itemCount: games.length,
      itemBuilder: (ctx, i) => _GameCard(game: games[i]),
    );
  }
}

// ─── ゲームカード ─────────────────────────────────────────────────────────
class _GameCard extends StatelessWidget {
  const _GameCard({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => GameDetailScreen(
              game: game, heroTag: 'saved_${game.id}'))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.50),
                  offset: const Offset(0, 6),
                  blurRadius: 12, spreadRadius: -2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: GameImage(
                game: game,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          game.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.80),
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ]),
    );
  }
}

// ─── 空状態 ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.bookmark_border_rounded,
            size: 56, color: Colors.white.withOpacity(0.20)),
        const SizedBox(height: 16),
        Text('まだ保存されていません',
            style: TextStyle(color: Colors.white.withOpacity(0.45),
                fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('ゲーム詳細画面の ★ をタップして保存',
            style: TextStyle(color: Colors.white.withOpacity(0.28),
                fontSize: 12)),
      ]),
    );
  }
}

// ─── 並び替えボタン ────────────────────────────────────────────────────────
class _SortButton extends ConsumerWidget {
  const _SortButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(savedSortOrderProvider);
    final isRating = order == SavedSortOrder.rating;
    return GestureDetector(
      onTap: () => ref.read(savedSortOrderProvider.notifier).state =
          isRating ? SavedSortOrder.added : SavedSortOrder.rating,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isRating
              ? const Color(0xFFD09248).withOpacity(0.20)
              : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isRating
                ? const Color(0xFFD09248).withOpacity(0.50)
                : Colors.white.withOpacity(0.12),
            width: 0.7,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            isRating ? Icons.star_rounded : Icons.access_time_rounded,
            size: 12,
            color: isRating
                ? const Color(0xFFD09248)
                : Colors.white.withOpacity(0.55),
          ),
          const SizedBox(width: 4),
          Text(
            isRating ? '評価順' : '追加順',
            style: TextStyle(
              color: isRating
                  ? const Color(0xFFD09248)
                  : Colors.white.withOpacity(0.55),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
    );
  }
}
