import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game.dart';
import '../models/game_detail.dart';
import '../services/data_pipeline_service.dart';

/// 棚表示用: Firestore（なければシードデータ）からゲームリストを返す
final gamesProvider = FutureProvider<List<Game>>((ref) async {
  // バッチ完了後にinvalidateして棚を再描画
  DataPipelineService.instance.onBatchComplete = () => ref.invalidateSelf();
  return DataPipelineService.instance.getGames();
});

/// 詳細画面用: gamesProviderから対応するゲームを検索して返す
final gameDetailProvider = FutureProvider.family<GameDetail, Game>((ref, game) async {
  final games = await ref.watch(gamesProvider.future);
  final enriched = games.firstWhere((g) => g.id == game.id, orElse: () => game);
  return GameDetail(game: enriched);
});

/// 楽天アフィリエイトURL: Firestoreキャッシュ優先 → APIフォールバック
final rakutenUrlProvider = FutureProvider.family<String?, Game>((ref, game) async {
  // すでにFirestoreから取得済みならそのまま返す
  if (game.rakutenAffUrl != null && game.rakutenAffUrl!.isNotEmpty) {
    return game.rakutenAffUrl;
  }
  // APIで取得（キー未設定時はnullを返す）
  return DataPipelineService.instance.getOrFetchRakutenUrl(game);
});

/// Yahoo!ショッピングURL: Firestoreキャッシュ優先 → APIフォールバック
final yahooUrlProvider = FutureProvider.family<String?, Game>((ref, game) async {
  return DataPipelineService.instance.getOrFetchYahooUrl(game);
});

class ShelfRow {
  const ShelfRow({required this.label, required this.gameIds, required this.seed});
  final String label;
  final List<String> gameIds;
  final int seed;
}

// フォールバック用: BGGデータが揃うまで使うキュレーション棚（変更禁止）
const kShelfRows = [
  ShelfRow(label: 'NEW ARRIVAL',  seed: 101, gameIds: ['wingspan','azul','viticulture','concordia','agricola','kingdomino','carcassonne','7wonders','ticket_ride','dominion','pandemic','catan']),
  ShelfRow(label: 'STRATEGY',     seed: 202, gameIds: ['terraforming','concordia','viticulture','agricola','wingspan','7wonders','gloomhaven','catan','kingdomino','carcassonne','dominion','azul']),
  ShelfRow(label: '2 PLAYERS',    seed: 303, gameIds: ['patchwork','jaipur','lost_cities','hive','azul','splendor','codenames','bohnanza','love_letter','skull','no_thanks','coup']),
  ShelfRow(label: 'PARTY GAMES',  seed: 404, gameIds: ['dixit','codenames','sushi_go','skull','coup','hanabi','no_thanks','love_letter','carcassonne','kingdomino','bohnanza','mysterium']),
  ShelfRow(label: 'SMALL BOX',    seed: 505, gameIds: ['jaipur','splendor','patchwork','lost_cities','sushi_go','love_letter','coup','hanabi','skull','no_thanks','bohnanza','hive']),
  ShelfRow(label: 'ADVENTURE',    seed: 606, gameIds: ['mysterium','gloomhaven','arkham','wingspan','catan','terraforming','pandemic','7wonders','dixit','azul','dominion','viticulture']),
];

// ─── BGGデータが揃ったら動的に棚を構成 ──────────────────────────────────────
/// カテゴリキーワード → 棚ラベル のマッピング
const _kCategoryBuckets = <String, String>{
  'Strategy':      'STRATEGY',
  'Economic':      'ECONOMICS',
  'Party Game':    'PARTY GAMES',
  'Card Game':     'CARD GAMES',
  'Fantasy':       'ADVENTURE',
  'Adventure':     'ADVENTURE',
  'Horror':        'ADVENTURE',
  'Abstract':      'ABSTRACT',
  'Family':        'FAMILY',
  'Deduction':     'DEDUCTION',
  'Negotiation':   'NEGOTIATION',
  'Puzzle':        'PUZZLE',
};

/// BGGカテゴリデータがある場合は動的棚生成。なければ [kShelfRows] を返す。
/// - 左上 (先頭行) = NEW ARRIVAL（高評価かつ最近人気のタイトル）
/// - 以降はカテゴリごとに棚を構成
/// - 1棚あたり最低8タイトル揃わなければスキップ（POP映え確保）
List<ShelfRow> buildShelfRows(List<Game> games) {
  // カテゴリデータが揃っていなければフォールバック
  final enriched = games.where((g) => g.categories.isNotEmpty).toList();
  if (enriched.length < 10) return kShelfRows;

  final allIds = games.map((g) => g.id).toSet();

  // ── 先頭行: NEW ARRIVAL（評価順 上位12件）─────────────────────────────
  final byRating = [...enriched]
    ..sort((a, b) => (b.bggRating ?? 0).compareTo(a.bggRating ?? 0));
  final newArrival = byRating.take(12).map((g) => g.id).toList();

  // ── 2P専用棚（maxPlayers==2 or 2P向けカテゴリ）─────────────────────
  final twoPlayer = enriched
      .where((g) => (g.maxPlayers != null && g.maxPlayers! <= 2) ||
          g.categories.any((c) => c.toLowerCase().contains('2-player')))
      .map((g) => g.id)
      .toList();

  // ── LIGHT & QUICK（プレイ時間 45分以下）──────────────────────────────
  final light = enriched
      .where((g) => g.playTimeMinutes != null && g.playTimeMinutes! <= 45)
      .map((g) => g.id)
      .toList();

  // ── カテゴリバケツ ─────────────────────────────────────────────────
  final buckets = <String, List<String>>{};
  for (final game in enriched) {
    for (final cat in game.categories) {
      final label = _kCategoryBuckets.entries
          .firstWhere(
            (e) => cat.contains(e.key),
            orElse: () => const MapEntry('', ''),
          )
          .value;
      if (label.isEmpty) continue;
      buckets.putIfAbsent(label, () => []).add(game.id);
    }
  }

  // ── 棚リスト組み立て（先頭は必ず NEW ARRIVAL）────────────────────────
  final rows = <ShelfRow>[
    ShelfRow(
      label: 'NEW ARRIVAL',
      seed: 101,
      gameIds: newArrival.where(allIds.contains).toList(),
    ),
  ];

  int seed = 202;

  // カテゴリ棚（8件以上あるものだけ追加）
  final seen = <String>{};
  for (final entry in buckets.entries) {
    final ids = entry.value.where(allIds.contains).toSet().toList();
    if (ids.length >= 8 && !seen.contains(entry.key)) {
      seen.add(entry.key);
      rows.add(ShelfRow(label: entry.key, seed: seed, gameIds: ids));
      seed += 101;
    }
  }

  // 2P棚（8件以上）
  if (twoPlayer.length >= 8) {
    rows.add(ShelfRow(
      label: '2 PLAYERS',
      seed: seed,
      gameIds: twoPlayer.where(allIds.contains).toList(),
    ));
    seed += 101;
  }

  // LIGHT棚（8件以上）
  if (light.length >= 8) {
    rows.add(ShelfRow(
      label: 'LIGHT & QUICK',
      seed: seed,
      gameIds: light.where(allIds.contains).toList(),
    ));
  }

  // 6行未満ならフォールバック棚で補完
  while (rows.length < 6) {
    final idx = rows.length;
    if (idx < kShelfRows.length) rows.add(kShelfRows[idx]);
    else break;
  }

  return rows;
}
