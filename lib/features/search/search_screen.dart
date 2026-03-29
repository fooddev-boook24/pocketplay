import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/ad_banner.dart';
import '../../data/models/game.dart';
import '../../data/repositories/game_provider.dart';
import '../../shelf/box_widgets.dart';
import '../game_detail/game_detail_screen.dart';

// ─── 難易度（プレイ時間ベース）──────────────────────────────────────────────
enum _Difficulty { light, medium, heavy }

extension _DifficultyLabel on _Difficulty {
  String get label {
    switch (this) {
      case _Difficulty.light:  return 'ライト';
      case _Difficulty.medium: return 'ミドル';
      case _Difficulty.heavy:  return 'ヘビー';
    }
  }
  bool matches(int? minutes) {
    if (minutes == null) return this == _Difficulty.medium;
    switch (this) {
      case _Difficulty.light:  return minutes <= 30;
      case _Difficulty.medium: return minutes > 30 && minutes <= 90;
      case _Difficulty.heavy:  return minutes > 90;
    }
  }
}

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialCategory});
  final String? initialCategory;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  String _query = '';
  int? _playerCount;        // null = 指定なし
  _Difficulty? _difficulty; // null = 指定なし
  String? _category;        // null = 指定なし

  @override
  void initState() {
    super.initState();
    if (widget.initialCategory != null) {
      _category = widget.initialCategory;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasFilter =>
      _playerCount != null || _difficulty != null || _category != null;

  List<Game> _filter(List<Game> games) {
    var result = games;

    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      result = result.where((g) =>
          g.title.toLowerCase().contains(q) ||
          g.categories.any((c) => c.toLowerCase().contains(q))).toList();
    }

    if (_playerCount != null) {
      result = result.where((g) {
        if (g.minPlayers == null && g.maxPlayers == null) return true;
        final min = g.minPlayers ?? 1;
        final max = g.maxPlayers ?? 99;
        if (_playerCount! >= 5) return max >= 5;
        return min <= _playerCount! && max >= _playerCount!;
      }).toList();
    }

    if (_difficulty != null) {
      result = result
          .where((g) => _difficulty!.matches(g.playTimeMinutes))
          .toList();
    }

    if (_category != null) {
      result = result
          .where((g) => g.categories.contains(_category))
          .toList();
    }

    return result;
  }

  // ゲームリストから頻出カテゴリ上位12件を抽出
  List<String> _topCategories(List<Game> games) {
    final counts = <String, int>{};
    for (final g in games) {
      for (final c in g.categories) {
        counts[c] = (counts[c] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(12).map((e) => e.key).toList();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    final mq = MediaQuery.of(context);
    final gamesAsync = ref.watch(gamesProvider);
    final allGames =
        gamesAsync.maybeWhen(data: (g) => g, orElse: () => kSeedGames);
    final results = _filter(allGames);
    final categories = _topCategories(allGames);

    return Scaffold(
      backgroundColor: const Color(0xFF1A0E00),
      bottomNavigationBar: const AdBannerWidget(),
      body: Stack(children: [
        Positioned.fill(child: _SearchAmbience()),
        Column(children: [
          // ── 検索フィールド ──────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, mq.padding.top + 10, 16, 0),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Icon(Icons.arrow_back_ios_new_rounded,
                    size: 20, color: Colors.white.withOpacity(0.80)),
              ),
              const SizedBox(width: 12),
              Expanded(child: _SearchField(
                controller: _controller,
                onChanged: (v) => setState(() => _query = v),
                onClear: () {
                  _controller.clear();
                  setState(() => _query = '');
                },
              )),
            ]),
          ),

          // ── フィルター ──────────────────────────────────────────────────────
          _FilterSection(
            playerCount: _playerCount,
            difficulty: _difficulty,
            category: _category,
            categories: categories,
            onPlayerCount: (v) => setState(() =>
                _playerCount = _playerCount == v ? null : v),
            onDifficulty: (v) => setState(() =>
                _difficulty = _difficulty == v ? null : v),
            onCategory: (v) => setState(() =>
                _category = _category == v ? null : v),
            onClear: () => setState(() {
              _playerCount = null;
              _difficulty = null;
              _category = null;
            }),
            hasFilter: _hasFilter,
          ),

          // ── 件数 ────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _query.isEmpty && !_hasFilter
                    ? '全${allGames.length}タイトル'
                    : '${results.length}件',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.40),
                    fontSize: 11, letterSpacing: 0.5),
              ),
            ),
          ),

          // ── グリッド ────────────────────────────────────────────────────────
          Expanded(
            child: results.isEmpty
                ? _NoResults(query: _query, hasFilter: _hasFilter)
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.62,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 10,
                    ),
                    itemCount: results.length,
                    itemBuilder: (ctx, i) => _SearchCard(game: results[i]),
                  ),
          ),
        ]),
      ]),
    );
  }
}

// ─── 検索フィールド ────────────────────────────────────────────────────────
class _SearchField extends StatelessWidget {
  const _SearchField(
      {required this.controller, required this.onChanged, required this.onClear});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.18), width: 0.5),
          ),
          child: Row(children: [
            const SizedBox(width: 10),
            Icon(Icons.search_rounded,
                size: 18, color: Colors.white.withOpacity(0.50)),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'ゲームを検索...',
                  hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.35), fontSize: 15),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: onChanged,
              ),
            ),
            if (controller.text.isNotEmpty)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.close_rounded,
                      size: 16, color: Colors.white.withOpacity(0.50)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

// ─── フィルターセクション ──────────────────────────────────────────────────
class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.playerCount,
    required this.difficulty,
    required this.category,
    required this.categories,
    required this.onPlayerCount,
    required this.onDifficulty,
    required this.onCategory,
    required this.onClear,
    required this.hasFilter,
  });
  final int? playerCount;
  final _Difficulty? difficulty;
  final String? category;
  final List<String> categories;
  final ValueChanged<int> onPlayerCount;
  final ValueChanged<_Difficulty> onDifficulty;
  final ValueChanged<String> onCategory;
  final VoidCallback onClear;
  final bool hasFilter;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),

        // 人数 ＋ 難易度
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            _FilterLabel('人数'),
            const SizedBox(width: 6),
            for (final p in [1, 2, 3, 4, 5])
              _Chip(
                label: p == 5 ? '5人+' : '$p人',
                selected: playerCount == p,
                onTap: () => onPlayerCount(p),
              ),
            const SizedBox(width: 12),
            _FilterLabel('難易度'),
            const SizedBox(width: 6),
            for (final d in _Difficulty.values)
              _Chip(
                label: d.label,
                selected: difficulty == d,
                onTap: () => onDifficulty(d),
              ),
            if (hasFilter) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('クリア',
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.50),
                          fontSize: 11)),
                ),
              ),
            ],
          ]),
        ),

        // カテゴリ（ゲームにカテゴリデータがある場合のみ表示）
        if (categories.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              _FilterLabel('カテゴリ'),
              const SizedBox(width: 6),
              for (final c in categories)
                _Chip(
                  label: c,
                  selected: category == c,
                  onTap: () => onCategory(c),
                ),
            ]),
          ),
        ],
        const SizedBox(height: 4),
      ],
    );
  }
}

class _FilterLabel extends StatelessWidget {
  const _FilterLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: Colors.white.withOpacity(0.35),
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5));
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFD09248).withOpacity(0.85)
              : Colors.white.withOpacity(0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? const Color(0xFFD09248)
                : Colors.white.withOpacity(0.15),
            width: 0.7,
          ),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.white.withOpacity(0.70),
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
      ),
    );
  }
}

// ─── 背景 ──────────────────────────────────────────────────────────────────
class _SearchAmbience extends StatelessWidget {
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

// ─── ゲームカード ──────────────────────────────────────────────────────────
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.game});
  final Game game;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => GameDetailScreen(
              game: game, heroTag: 'search_${game.id}'))),
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
              child: GameImage(game: game, fit: BoxFit.cover,
                  alignment: Alignment.topCenter),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(game.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Colors.white.withOpacity(0.80),
                fontSize: 10, fontWeight: FontWeight.w600, height: 1.3)),
      ]),
    );
  }
}

// ─── 検索結果なし ─────────────────────────────────────────────────────────
class _NoResults extends StatelessWidget {
  const _NoResults({required this.query, required this.hasFilter});
  final String query;
  final bool hasFilter;

  Future<void> _launchBgg() async {
    final encoded = Uri.encodeComponent(query);
    final uri = Uri.parse(
        'https://boardgamegeek.com/search?q=$encoded&objecttype=boardgame');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.search_off_rounded,
            size: 56, color: Colors.white.withOpacity(0.20)),
        const SizedBox(height: 16),
        Text(
          query.isNotEmpty ? '「$query」は見つかりませんでした' : '条件に一致するゲームがありません',
          style: TextStyle(color: Colors.white.withOpacity(0.45),
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text('フィルターを変えてみてください',
            style: TextStyle(color: Colors.white.withOpacity(0.28),
                fontSize: 12)),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _launchBgg,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.white.withOpacity(0.15), width: 0.7),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.open_in_new_rounded,
                    size: 14, color: Colors.white.withOpacity(0.55)),
                const SizedBox(width: 8),
                Text('BGGで「$query」を検索',
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.60),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
