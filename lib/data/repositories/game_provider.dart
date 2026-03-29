import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game.dart';
import '../models/game_detail.dart';
import '../repositories/bgg_repository.dart';
import '../repositories/game_data_repository.dart';
import '../services/data_pipeline_service.dart';
import '../services/translation_service.dart';

/// 棚表示用: Firestore（なければシードデータ）からゲームリストを返す
final gamesProvider = FutureProvider<List<Game>>((ref) async {
  // バッチ完了後にinvalidateして棚を再描画
  DataPipelineService.instance.onBatchComplete = () => ref.invalidateSelf();
  return DataPipelineService.instance.getGames();
});

/// 詳細画面用: Firestoreデータ + カテゴリ/説明がなければBGGから取得してFirestoreに保存
final gameDetailProvider = FutureProvider.family<GameDetail, Game>((ref, game) async {
  final games = await ref.watch(gamesProvider.future);
  final base = games.firstWhere((g) => g.id == game.id, orElse: () => game);

  // カテゴリや説明文があればそのまま返す
  if (base.categories.isNotEmpty && base.description != null) {
    return GameDetail(game: base);
  }

  // なければBGGから詳細取得（stats=1）
  final detail = await BggRepository.instance.fetchDetail(base);

  // 説明文が英語なら日本語に翻訳
  Game enriched = detail.game;
  final desc = enriched.description;
  if (desc != null && desc.isNotEmpty && !TranslationService.isJapanese(desc)) {
    final translated = await TranslationService.toJapanese(desc);
    if (translated != null) {
      enriched = enriched.copyWith(description: translated);
    }
  }

  // Firestoreに保存（次回から即表示・再翻訳不要）
  if (enriched.categories.isNotEmpty || enriched.description != null) {
    try {
      await GameDataRepository.instance.saveGame(enriched);
    } catch (_) {}
  }

  return GameDetail(
    game: enriched,
    mechanics: detail.mechanics,
    designers: detail.designers,
    yearPublished: detail.yearPublished,
    complexity: detail.complexity,
  );
});

/// 棚シャッフル用シード（変更するとbuildShelfRowsが別の並び順を返す）
final shelfSeedProvider = StateProvider<int>((ref) => 0);


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
    gameIds: ['everdell','cascadia','brass_birm','great_western','root','scythe','spirit_island','clank','barrage','orleans','istanbul','power_grid'],
    bays: const [
      ShelfBayConfig(label: 'NEW ARRIVAL', seed: 101, gameIds: ['everdell','cascadia','brass_birm','great_western','root','scythe','spirit_island','clank','barrage','orleans','istanbul','power_grid']),
      ShelfBayConfig(label: 'STRATEGY',    seed: 118, gameIds: ['terraforming','concordia','viticulture','agricola','brass_birm','great_western','power_grid','scythe','orleans','barrage','7wonders','wingspan']),
      ShelfBayConfig(label: 'CARD GAMES',  seed: 135, gameIds: ['dominion','7wonders_duel','coup','love_letter','no_thanks','bohnanza','splendor','hanabi','sushi_go','codenames','jaipur','regicide']),
      ShelfBayConfig(label: 'FAMILY',      seed: 152, gameIds: ['kingdomino','carcassonne','catan','pandemic','ticket_ride','azul','dixit','cascadia','codenames','wingspan','everdell','istanbul']),
    ],
  ),
  ShelfRow(
    label: 'RANKING', seed: 200,
    gameIds: ['gloomhaven','terraforming','wingspan','viticulture','concordia','brass_birm','scythe','spirit_island','root','great_western','barrage','everdell'],
    bays: const [
      ShelfBayConfig(label: 'RANKING',     seed: 200, gameIds: ['gloomhaven','terraforming','wingspan','viticulture','concordia','brass_birm','scythe','spirit_island','root','great_western','barrage','everdell']),
      ShelfBayConfig(label: 'ADVENTURE',   seed: 217, gameIds: ['gloomhaven','arkham','mysterium','root','blood_rage','dead_winter','spirit_island','scythe','dominion','clank','catan','carcassonne']),
      ShelfBayConfig(label: 'PARTY GAMES', seed: 234, gameIds: ['dixit','codenames','just_one','dobble','skull','coup','hanabi','wavelength','no_thanks','love_letter','bohnanza','insider']),
      ShelfBayConfig(label: '2 PLAYERS',   seed: 251, gameIds: ['patchwork','jaipur','lost_cities','hive','7wonders_duel','hanamikoji','fox_forest','azul','splendor','codenames','regicide','cant_stop']),
    ],
  ),
  ShelfRow(
    label: 'SMALL BOX', seed: 300,
    gameIds: ['jaipur','splendor','patchwork','7wonders_duel','hanamikoji','fox_forest','cockroach','for_sale','coloretto','biblios','regicide','cant_stop'],
    bays: const [
      ShelfBayConfig(label: 'SMALL BOX',   seed: 300, gameIds: ['jaipur','splendor','patchwork','7wonders_duel','hanamikoji','fox_forest','cockroach','for_sale','coloretto','biblios','regicide','cant_stop']),
      ShelfBayConfig(label: 'ECONOMICS',   seed: 317, gameIds: ['viticulture','concordia','agricola','terraforming','power_grid','brass_birm','dominion','splendor','great_western','orleans','istanbul','ticket_ride']),
      ShelfBayConfig(label: 'ABSTRACT',    seed: 334, gameIds: ['azul','hive','patchwork','cascadia','hanamikoji','for_sale','coloretto','biblios','cant_stop','skull','no_thanks','lost_cities']),
      ShelfBayConfig(label: 'DEDUCTION',   seed: 351, gameIds: ['codenames','mysterium','coup','hanabi','skull','insider','wavelength','dixit','just_one','cockroach','bohnanza','jaipur']),
    ],
  ),
  ShelfRow(
    label: 'LIGHT & QUICK', seed: 400,
    gameIds: ['the_mind','dobble','just_one','wavelength','skull_king','exploding_kit','insider','love_letter','coup','hanabi','skull','no_thanks'],
    bays: const [
      ShelfBayConfig(label: 'LIGHT & QUICK', seed: 400, gameIds: ['the_mind','dobble','just_one','wavelength','skull_king','exploding_kit','insider','love_letter','coup','hanabi','skull','no_thanks']),
      ShelfBayConfig(label: 'NEGOTIATION',   seed: 417, gameIds: ['bohnanza','coup','skull','catan','concordia','dixit','no_thanks','love_letter','sushi_go','codenames','for_sale','coloretto']),
      ShelfBayConfig(label: 'PUZZLE',        seed: 434, gameIds: ['azul','patchwork','kingdomino','cascadia','hive','lost_cities','hanamikoji','cant_stop','coloretto','biblios','sushi_go','carcassonne']),
      ShelfBayConfig(label: 'EPIC',          seed: 451, gameIds: ['gloomhaven','arkham','blood_rage','dead_winter','spirit_island','scythe','root','terraforming','7wonders','viticulture','concordia','wingspan']),
    ],
  ),
];

// ─── 棚レイアウト構築 ────────────────────────────────────────────────────────

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
  ['LIGHT & QUICK', 'NEGOTIATION', 'PUZZLE',      'EPIC'],
];

/// 全ゲームを使って4行×4ベイの棚を構成する。
/// カテゴリがあればそれを優先し、なければシード別シャッフルで全ゲームを均等配布。
/// これにより1000件あれば各ベイに異なる60+件が並ぶ。
List<ShelfRow> buildShelfRows(List<Game> games, {int seedOffset = 0}) {
  if (games.isEmpty) return kShelfRows;

  // 評価順でソート（評価なしは後ろ）
  final sorted = [...games]
    ..sort((a, b) => (b.bggRating ?? 0).compareTo(a.bggRating ?? 0));
  final sortedIds = sorted.map((g) => g.id).toList();

  // カテゴリバケツ（カテゴリ情報があるゲームのみ）
  final buckets = <String, List<String>>{};
  for (final game in games) {
    if (game.categories.isEmpty) continue;
    for (final cat in game.categories) {
      final label = _kCategoryBuckets.entries
          .firstWhere((e) => cat.contains(e.key),
              orElse: () => const MapEntry('', ''))
          .value;
      if (label.isEmpty) continue;
      buckets.putIfAbsent(label, () => []).add(game.id);
    }
  }

  // 特殊フィルタ
  final twoPlayer = games
      .where((g) => (g.maxPlayers != null && g.maxPlayers! <= 2) ||
          g.categories.any((c) => c.toLowerCase().contains('2-player')))
      .map((g) => g.id)
      .toList();
  final light = games
      .where((g) => g.playTimeMinutes != null && g.playTimeMinutes! <= 45)
      .map((g) => g.id)
      .toList();
  final smallBox = games
      .where((g) => g.size == BoxSize.tiny || g.size == BoxSize.small)
      .map((g) => g.id)
      .toList();
  final epic = games
      .where((g) => g.size == BoxSize.large ||
          (g.playTimeMinutes != null && g.playTimeMinutes! >= 90))
      .map((g) => g.id)
      .toList();

  // bgg_プレフィックスのゲームをbggId降順（新しいゲームが前）＋シードゲームを後ろ
  final newArrivalIds = [
    ...( games
          .where((g) => g.id.startsWith('bgg_'))
          .toList()
          ..sort((a, b) => b.bggId.compareTo(a.bggId))
        ).map((g) => g.id),
    ...games
          .where((g) => !g.id.startsWith('bgg_'))
          .map((g) => g.id),
  ];

  // ベイのラベルとシードに対応するゲームIDリストを返す
  List<String> idsForBay(String label, int seed) {
    List<String>? filtered;
    switch (label) {
      case 'RANKING':
        // bggRating降順・固定。シャッフルしない＝ランキングは事実
        return sortedIds;
      case 'NEW ARRIVAL':
        // 動的取得ゲーム（bggId降順）を前に、固定ゲームを後ろに
        // シャッフルしない＝新着順は変えない
        return newArrivalIds;
      case '2 PLAYERS':
        if (twoPlayer.length >= 10) filtered = twoPlayer;
      case 'SMALL BOX':
        if (smallBox.length >= 10) filtered = smallBox;
      case 'LIGHT & QUICK':
        if (light.length >= 10) filtered = light;
      case 'EPIC':
        if (epic.length >= 10) filtered = epic;
      default:
        final bucket = buckets[label];
        if (bucket != null && bucket.length >= 10) {
          filtered = bucket.toSet().toList();
        }
    }
    // フィルタが足りなければ全ゲームを使用
    final base = filtered ?? sortedIds;
    // ベイごとにシードを変えてシャッフル → 各ベイが異なる並び順になる
    return _seededShuffle(base, seed);
  }

  final rows = <ShelfRow>[];
  int baseSeed = 101 + seedOffset;

  for (final bayLabels in _kBayLayout) {
    final bays = <ShelfBayConfig>[];
    for (final label in bayLabels) {
      final ids = idsForBay(label, baseSeed);
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

/// シード値で決定論的にシャッフル（同じseedなら常に同じ並び順）
List<String> _seededShuffle(List<String> ids, int seed) {
  final list = [...ids];
  var s = seed & 0xFFFFFFFF;
  for (int i = list.length - 1; i > 0; i--) {
    s = ((s * 1664525) + 1013904223) & 0xFFFFFFFF;
    final j = s % (i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}
