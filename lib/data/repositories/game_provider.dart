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

class ShelfBayConfig {
  const ShelfBayConfig({required this.label, required this.gameIds, required this.seed});
  final String label;
  final List<String> gameIds;
  final int seed;
}

class ShelfRow {
  const ShelfRow({required this.label, required this.gameIds, required this.seed, this.bays = const []});
  final String label;
  final List<String> gameIds;
  final int seed;
  final List<ShelfBayConfig> bays;

  /// bay j の設定を返す。baysが足りない場合は行デフォルトを使用
  ShelfBayConfig bayConfig(int j) {
    if (j < bays.length) return bays[j];
    return ShelfBayConfig(label: label, gameIds: gameIds, seed: seed + j * 17);
  }
}

// フォールバック用: BGGデータが揃うまで使うキュレーション棚
// 4行×4ベイ固定レイアウト
final kShelfRows = [
  ShelfRow(
    label: 'NEW ARRIVAL', seed: 101,
    gameIds: ['wingspan','azul','viticulture','concordia','agricola','kingdomino','carcassonne','7wonders','ticket_ride','dominion','pandemic','catan'],
    bays: const [
      ShelfBayConfig(label: 'NEW ARRIVAL', seed: 101, gameIds: ['wingspan','azul','viticulture','concordia','agricola','kingdomino','carcassonne','7wonders','ticket_ride','dominion','pandemic','catan']),
      ShelfBayConfig(label: 'STRATEGY',    seed: 118, gameIds: ['terraforming','concordia','viticulture','agricola','wingspan','7wonders','gloomhaven','catan','kingdomino','carcassonne','dominion','azul']),
      ShelfBayConfig(label: 'CARD GAMES',  seed: 135, gameIds: ['dominion','7wonders','coup','love_letter','no_thanks','bohnanza','splendor','hanabi','sushi_go','codenames','jaipur','ticket_ride']),
      ShelfBayConfig(label: 'FAMILY',      seed: 152, gameIds: ['kingdomino','carcassonne','catan','pandemic','ticket_ride','azul','dixit','sushi_go','codenames','wingspan','7wonders','splendor']),
    ],
  ),
  ShelfRow(
    label: 'RANKING', seed: 200,
    gameIds: ['gloomhaven','terraforming','wingspan','viticulture','concordia'],
    bays: const [
      ShelfBayConfig(label: 'RANKING',     seed: 200, gameIds: ['gloomhaven','terraforming','wingspan','viticulture','concordia']),
      ShelfBayConfig(label: 'ADVENTURE',   seed: 217, gameIds: ['gloomhaven','arkham','mysterium','dixit','dominion','wingspan','catan','carcassonne']),
      ShelfBayConfig(label: 'PARTY GAMES', seed: 234, gameIds: ['dixit','codenames','sushi_go','skull','coup','hanabi','no_thanks','love_letter','carcassonne','kingdomino','bohnanza','mysterium']),
      ShelfBayConfig(label: '2 PLAYERS',   seed: 251, gameIds: ['patchwork','jaipur','lost_cities','hive','azul','splendor','codenames','bohnanza','love_letter','skull','no_thanks','coup']),
    ],
  ),
  ShelfRow(
    label: 'SMALL BOX', seed: 300,
    gameIds: ['jaipur','splendor','patchwork','lost_cities','sushi_go','love_letter','coup','hanabi','skull','no_thanks','bohnanza','hive'],
    bays: const [
      ShelfBayConfig(label: 'SMALL BOX',   seed: 300, gameIds: ['jaipur','splendor','patchwork','lost_cities','sushi_go','love_letter','coup','hanabi','skull','no_thanks','bohnanza','hive']),
      ShelfBayConfig(label: 'ECONOMICS',   seed: 317, gameIds: ['viticulture','concordia','agricola','terraforming','catan','dominion','splendor','7wonders','ticket_ride','wingspan','kingdomino','bohnanza']),
      ShelfBayConfig(label: 'ABSTRACT',    seed: 334, gameIds: ['azul','hive','patchwork','codenames','skull','no_thanks','coup','love_letter','sushi_go','hanabi','lost_cities','jaipur']),
      ShelfBayConfig(label: 'DEDUCTION',   seed: 351, gameIds: ['codenames','mysterium','coup','hanabi','skull','love_letter','no_thanks','dixit','sushi_go','carcassonne','bohnanza','jaipur']),
    ],
  ),
  ShelfRow(
    label: 'LIGHT & QUICK', seed: 400,
    gameIds: ['patchwork','jaipur','lost_cities','sushi_go','love_letter','coup','hanabi','skull','no_thanks','bohnanza','kingdomino','dixit'],
    bays: const [
      ShelfBayConfig(label: 'LIGHT & QUICK', seed: 400, gameIds: ['patchwork','jaipur','lost_cities','sushi_go','love_letter','coup','hanabi','skull','no_thanks','bohnanza','kingdomino','dixit']),
      ShelfBayConfig(label: 'NEGOTIATION',   seed: 417, gameIds: ['bohnanza','coup','skull','catan','concordia','dixit','no_thanks','love_letter','sushi_go','codenames','hanabi','jaipur']),
      ShelfBayConfig(label: 'PUZZLE',        seed: 434, gameIds: ['azul','patchwork','kingdomino','hive','codenames','lost_cities','hanabi','no_thanks','skull','sushi_go','jaipur','carcassonne']),
      ShelfBayConfig(label: 'ADVENTURE',     seed: 451, gameIds: ['gloomhaven','arkham','mysterium','dixit','dominion','wingspan','catan','carcassonne','7wonders','terraforming','viticulture','concordia']),
    ],
  ),
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

// 4行×4ベイの固定レイアウト定義
const _kBayLayout = [
  ['NEW ARRIVAL',   'STRATEGY',    'CARD GAMES',  'FAMILY'],
  ['RANKING',       'ADVENTURE',   'PARTY GAMES', '2 PLAYERS'],
  ['SMALL BOX',     'ECONOMICS',   'ABSTRACT',    'DEDUCTION'],
  ['LIGHT & QUICK', 'NEGOTIATION', 'PUZZLE',      'ADVENTURE'],
];

/// BGGカテゴリデータがある場合は4行×4ベイの固定レイアウトで棚生成。
/// なければ [kShelfRows] を返す。
List<ShelfRow> buildShelfRows(List<Game> games) {
  final enriched = games.where((g) => g.categories.isNotEmpty).toList();
  if (enriched.length < 10) return kShelfRows;

  final allIds = games.map((g) => g.id).toSet();

  // 評価順ソート
  final byRating = [...enriched]
    ..sort((a, b) => (b.bggRating ?? 0).compareTo(a.bggRating ?? 0));

  // カテゴリバケツ
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

  // 特殊バケツ
  final twoPlayer = enriched
      .where((g) => (g.maxPlayers != null && g.maxPlayers! <= 2) ||
          g.categories.any((c) => c.toLowerCase().contains('2-player')))
      .map((g) => g.id).toSet().toList();

  final light = enriched
      .where((g) => g.playTimeMinutes != null && g.playTimeMinutes! <= 45)
      .map((g) => g.id).toSet().toList();

  final smallBox = enriched
      .where((g) => g.size == BoxSize.tiny || g.size == BoxSize.small)
      .map((g) => g.id).toSet().toList();

  // ラベルに対応するゲームIDリストを返す
  List<String> idsFor(String label) {
    switch (label) {
      case 'NEW ARRIVAL':   return byRating.take(12).map((g) => g.id).where(allIds.contains).toList();
      case 'RANKING':       return byRating.take(5).map((g) => g.id).where(allIds.contains).toList();
      case '2 PLAYERS':     return twoPlayer.where(allIds.contains).toList();
      case 'SMALL BOX':     return smallBox.where(allIds.contains).toList();
      case 'LIGHT & QUICK': return light.where(allIds.contains).toList();
      default:
        return (buckets[label] ?? []).where(allIds.contains).toSet().toList();
    }
  }

  // 4行×4ベイのShelfRowを組み立て
  final rows = <ShelfRow>[];
  int baseSeed = 101;

  for (int r = 0; r < _kBayLayout.length; r++) {
    final bayLabels = _kBayLayout[r];
    final bays = <ShelfBayConfig>[];
    for (int j = 0; j < bayLabels.length; j++) {
      final label = bayLabels[j];
      var ids = idsFor(label);
      // 不足時はフォールバック棚のgameIdsを使用
      if (ids.length < 3 && r < kShelfRows.length && j < kShelfRows[r].bays.length) {
        ids = kShelfRows[r].bays[j].gameIds;
      }
      bays.add(ShelfBayConfig(label: label, gameIds: ids, seed: baseSeed));
      baseSeed += 17;
    }
    rows.add(ShelfRow(
      label: bayLabels[0],
      gameIds: bays[0].gameIds,
      seed: bays[0].seed,
      bays: bays,
    ));
  }

  return rows;
}
