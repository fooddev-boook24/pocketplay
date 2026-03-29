import 'package:flutter/material.dart';

enum BoxSize { tiny, small, medium, large }

class Game {
  const Game({
    required this.id,
    required this.bggId,
    required this.title,
    required this.spineColor,
    required this.spineTextColor,
    this.size = BoxSize.medium,
    this.faceAspect = 0.88,
    this.imageUrl,
    this.localAsset,
    // Phase 2拡張フィールド
    this.thumbnailUrl,
    this.minPlayers,
    this.maxPlayers,
    this.playTimeMinutes,
    this.bggRating,
    this.categories = const [],
    this.description,
    this.isAvailableInJapan = false,
    // Phase 4: アフィリエイト
    this.rakutenAffUrl,
  });

  final String id;
  final int bggId;
  final String title;
  final Color spineColor;
  final Color spineTextColor;
  final BoxSize size;
  final double faceAspect;
  final String? imageUrl;
  final String? localAsset;

  // Phase 2拡張
  final String? thumbnailUrl;
  final int? minPlayers;
  final int? maxPlayers;
  final int? playTimeMinutes;
  final double? bggRating;
  final List<String> categories;
  final String? description;
  final bool isAvailableInJapan;

  // Phase 4
  final String? rakutenAffUrl;

  Game copyWith({
    String? imageUrl,
    String? localAsset,
    String? thumbnailUrl,
    BoxSize? size,
    int? minPlayers,
    int? maxPlayers,
    int? playTimeMinutes,
    double? bggRating,
    List<String>? categories,
    String? description,
    bool? isAvailableInJapan,
    String? rakutenAffUrl,
  }) =>
      Game(
        id: id,
        bggId: bggId,
        title: title,
        spineColor: spineColor,
        spineTextColor: spineTextColor,
        size: size ?? this.size,
        faceAspect: faceAspect,
        imageUrl: imageUrl ?? this.imageUrl,
        localAsset: localAsset ?? this.localAsset,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        minPlayers: minPlayers ?? this.minPlayers,
        maxPlayers: maxPlayers ?? this.maxPlayers,
        playTimeMinutes: playTimeMinutes ?? this.playTimeMinutes,
        bggRating: bggRating ?? this.bggRating,
        categories: categories ?? this.categories,
        description: description ?? this.description,
        isAvailableInJapan: isAvailableInJapan ?? this.isAvailableInJapan,
        rakutenAffUrl: rakutenAffUrl ?? this.rakutenAffUrl,
      );

  String? get bestImage => imageUrl ?? localAsset;
  bool get hasImage => bestImage != null && bestImage!.isNotEmpty;

  String get playersLabel {
    if (minPlayers == null && maxPlayers == null) return '-';
    if (minPlayers == maxPlayers) return '$minPlayers人';
    return '${minPlayers ?? "?"}〜${maxPlayers ?? "?"}人';
  }

  String get timeLabel {
    if (playTimeMinutes == null) return '-';
    if (playTimeMinutes! >= 60) {
      final h = playTimeMinutes! ~/ 60;
      final m = playTimeMinutes! % 60;
      return m == 0 ? '$h時間' : '$h時間$m分';
    }
    return '$playTimeMinutes分';
  }
}

// ─── 65 real BGG games for variety ────────────────────────────────────────────
const List<Game> kSeedGames = [
  // Large boxes
  Game(id:'catan',         bggId:13,     title:'カタン',             spineColor:Color(0xFF2D6A3F), spineTextColor:Colors.white,        size:BoxSize.large,  faceAspect:0.95, localAsset:'assets/boxes/catan.jpg'),
  Game(id:'wingspan',      bggId:266192, title:'ウイングスパン',     spineColor:Color(0xFF2A5F8A), spineTextColor:Colors.white,        size:BoxSize.large,  faceAspect:1.03, localAsset:'assets/boxes/wingspan.jpg'),
  Game(id:'mysterium',     bggId:181304, title:'ミステリウム',       spineColor:Color(0xFF18083A), spineTextColor:Color(0xFFCCAAFF),   size:BoxSize.large,  faceAspect:1.00, localAsset:'assets/boxes/mysterium.jpg'),
  Game(id:'pandemic',      bggId:30549,  title:'パンデミック',       spineColor:Color(0xFF003070), spineTextColor:Colors.white,        size:BoxSize.large,  faceAspect:0.93),
  Game(id:'terraforming',  bggId:167791, title:'テラフォーミング',   spineColor:Color(0xFFAA3300), spineTextColor:Colors.white,        size:BoxSize.large,  faceAspect:0.88),
  Game(id:'7wonders',      bggId:68448,  title:'7ワンダーズ',        spineColor:Color(0xFF7A5000), spineTextColor:Colors.white,        size:BoxSize.large,  faceAspect:1.08),
  Game(id:'gloomhaven',    bggId:174430, title:'グルームヘイヴン',   spineColor:Color(0xFF2A1A0A), spineTextColor:Color(0xFFDDAA77),   size:BoxSize.large,  faceAspect:0.80),
  Game(id:'arkham',        bggId:15987,  title:'アーカムホラー',     spineColor:Color(0xFF1A1A2A), spineTextColor:Color(0xFFAABBCC),   size:BoxSize.large,  faceAspect:0.73),
  Game(id:'root',          bggId:237182, title:'ルート',             spineColor:Color(0xFF4A7A30), spineTextColor:Colors.white,        size:BoxSize.large,  faceAspect:0.88),
  Game(id:'scythe',        bggId:169786, title:'サイズ',             spineColor:Color(0xFF1A2A3A), spineTextColor:Color(0xFFCCBB88),   size:BoxSize.large,  faceAspect:0.88),
  Game(id:'spirit_island', bggId:162886, title:'スピリットアイランド',spineColor:Color(0xFF1A4A30),spineTextColor:Color(0xFFAADDBB),  size:BoxSize.large,  faceAspect:0.80),
  Game(id:'blood_rage',    bggId:170216, title:'ブラッドレイジ',     spineColor:Color(0xFF6A0A0A), spineTextColor:Color(0xFFFFBB44),   size:BoxSize.large,  faceAspect:0.80),
  Game(id:'dead_winter',   bggId:150376, title:'デッドオブウィンター',spineColor:Color(0xFF1A2A3A),spineTextColor:Color(0xFFCCDDEE),  size:BoxSize.large,  faceAspect:0.80),

  // Medium boxes
  Game(id:'azul',          bggId:230802, title:'アズール',           spineColor:Color(0xFF0E5C80), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:1.00, localAsset:'assets/boxes/azul.jpg'),
  Game(id:'dixit',         bggId:39856,  title:'ディクシット',       spineColor:Color(0xFF6A2F8F), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.90, localAsset:'assets/boxes/dixit.jpg'),
  Game(id:'codenames',     bggId:178900, title:'コードネーム',       spineColor:Color(0xFFAA1A00), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.67, localAsset:'assets/boxes/codenames.jpg'),
  Game(id:'ticket_ride',   bggId:9209,   title:'チケットトゥライド', spineColor:Color(0xFF8B2000), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:1.05),
  Game(id:'dominion',      bggId:36218,  title:'ドミニオン',         spineColor:Color(0xFF4A3000), spineTextColor:Color(0xFFFFDDA0),   size:BoxSize.medium, faceAspect:0.88),
  Game(id:'carcassonne',   bggId:822,    title:'カルカソンヌ',       spineColor:Color(0xFF5A8020), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:1.00),
  Game(id:'kingdomino',    bggId:204583, title:'キングドミノ',       spineColor:Color(0xFF1A4A8A), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:1.00),
  Game(id:'agricola',      bggId:31260,  title:'アグリコラ',         spineColor:Color(0xFF6B4A10), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.93),
  Game(id:'viticulture',   bggId:128621, title:'ヴィティカルチャー', spineColor:Color(0xFF5A1A40), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.88),
  Game(id:'concordia',     bggId:124361, title:'コンコルディア',     spineColor:Color(0xFF003858), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.88),
  Game(id:'everdell',      bggId:199792, title:'エバーデール',       spineColor:Color(0xFF5A3A1A), spineTextColor:Color(0xFFFFDDA0),   size:BoxSize.medium, faceAspect:0.88),
  Game(id:'cascadia',      bggId:295947, title:'カスカディア',       spineColor:Color(0xFF2A6A50), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.88),
  Game(id:'brass_birm',    bggId:224517, title:'ブラス・バーミンガム',spineColor:Color(0xFF1A1A2A),spineTextColor:Color(0xFFCCBB88),  size:BoxSize.medium, faceAspect:0.88),
  Game(id:'great_western', bggId:193738, title:'グレートウェスタントレイル',spineColor:Color(0xFF7A4A18),spineTextColor:Colors.white, size:BoxSize.medium, faceAspect:0.88),
  Game(id:'istanbul',      bggId:148949, title:'イスタンブール',     spineColor:Color(0xFFAA5500), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:1.00),
  Game(id:'power_grid',    bggId:2651,   title:'電力会社',           spineColor:Color(0xFF2A3A50), spineTextColor:Color(0xFFFFEE88),   size:BoxSize.medium, faceAspect:0.93),
  Game(id:'orleans',       bggId:164928, title:'オルレアン',         spineColor:Color(0xFF5A3A20), spineTextColor:Color(0xFFFFDDA0),   size:BoxSize.medium, faceAspect:0.88),
  Game(id:'clank',         bggId:201808, title:'クランク！',         spineColor:Color(0xFF1A3A5A), spineTextColor:Colors.white,        size:BoxSize.medium, faceAspect:0.88),
  Game(id:'barrage',       bggId:251247, title:'バラージ',           spineColor:Color(0xFF1A2A3A), spineTextColor:Color(0xFF88BBCC),   size:BoxSize.medium, faceAspect:0.88),

  // Small boxes
  Game(id:'splendor',      bggId:148228, title:'スプレンダー',       spineColor:Color(0xFF8B1818), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.83, localAsset:'assets/boxes/splendor.jpg'),
  Game(id:'patchwork',     bggId:163412, title:'パッチワーク',       spineColor:Color(0xFF3D7055), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.88, localAsset:'assets/boxes/patchwork.jpg'),
  Game(id:'jaipur',        bggId:54043,  title:'ジャイプル',         spineColor:Color(0xFFC07010), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.71, localAsset:'assets/boxes/jaipur.jpg'),
  Game(id:'lost_cities',   bggId:50,     title:'ロストシティ',       spineColor:Color(0xFF1E3A7A), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:1.00, localAsset:'assets/boxes/lost_cities.jpg'),
  Game(id:'sushi_go',      bggId:133473, title:'寿司Go！',           spineColor:Color(0xFFEE4488), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.88),
  Game(id:'hive',          bggId:2655,   title:'ハイヴ',             spineColor:Color(0xFF1A1A1A), spineTextColor:Color(0xFFFFFF88),   size:BoxSize.small,  faceAspect:0.93),
  Game(id:'7wonders_duel', bggId:173346, title:'7ワンダーズ デュエル',spineColor:Color(0xFF7A4A00),spineTextColor:Colors.white,       size:BoxSize.small,  faceAspect:0.83),
  Game(id:'hanamikoji',    bggId:158600, title:'花見小路',           spineColor:Color(0xFFCC4488), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.67),
  Game(id:'fox_forest',    bggId:221965, title:'キツネの森',         spineColor:Color(0xFF2A6A30), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.67),
  Game(id:'cockroach',     bggId:150145, title:'ゴキブリポーカー',   spineColor:Color(0xFF1A3A00), spineTextColor:Color(0xFFAAFF44),   size:BoxSize.small,  faceAspect:0.67),
  Game(id:'for_sale',      bggId:172,    title:'フォーセール',       spineColor:Color(0xFF3A5A00), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.75),
  Game(id:'coloretto',     bggId:5782,   title:'カラレット',         spineColor:Color(0xFFCC6600), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.67),
  Game(id:'biblios',       bggId:34219,  title:'ビブリオス',         spineColor:Color(0xFF8B6800), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.75),
  Game(id:'regicide',      bggId:307002, title:'レジサイド',         spineColor:Color(0xFF3A0A50), spineTextColor:Color(0xFFDD99FF),   size:BoxSize.small,  faceAspect:0.67),
  Game(id:'cant_stop',     bggId:41,     title:'キャントストップ',   spineColor:Color(0xFFAA2200), spineTextColor:Colors.white,        size:BoxSize.small,  faceAspect:0.88),

  // Tiny boxes
  Game(id:'love_letter',   bggId:129622, title:'ラブレター',         spineColor:Color(0xFFCC2244), spineTextColor:Colors.white,        size:BoxSize.tiny,   faceAspect:0.67),
  Game(id:'coup',          bggId:131357, title:'クー',               spineColor:Color(0xFF332200), spineTextColor:Color(0xFFFFCC44),   size:BoxSize.tiny,   faceAspect:0.75),
  Game(id:'bohnanza',      bggId:11,     title:'ボーナンザ',         spineColor:Color(0xFF558800), spineTextColor:Colors.white,        size:BoxSize.tiny,   faceAspect:0.55),
  Game(id:'hanabi',        bggId:98778,  title:'花火',               spineColor:Color(0xFF000060), spineTextColor:Color(0xFFFFEE44),   size:BoxSize.tiny,   faceAspect:0.67),
  Game(id:'skull',         bggId:120510, title:'スカル',             spineColor:Color(0xFF1A0000), spineTextColor:Color(0xFFFF4422),   size:BoxSize.tiny,   faceAspect:0.88),
  Game(id:'no_thanks',     bggId:12942,  title:'ノーサンクス',       spineColor:Color(0xFF004488), spineTextColor:Colors.white,        size:BoxSize.tiny,   faceAspect:0.75),
  Game(id:'the_mind',      bggId:244992, title:'ザ・マインド',       spineColor:Color(0xFF000A1A), spineTextColor:Color(0xFF44AAFF),   size:BoxSize.tiny,   faceAspect:0.67),
  Game(id:'dobble',        bggId:63268,  title:'ドブル',             spineColor:Color(0xFFDD3300), spineTextColor:Colors.white,        size:BoxSize.tiny,   faceAspect:1.00),
  Game(id:'just_one',      bggId:254640, title:'ジャストワン',       spineColor:Color(0xFFFFAA00), spineTextColor:Color(0xFF1A0800),   size:BoxSize.tiny,   faceAspect:0.75),
  Game(id:'wavelength',    bggId:262543, title:'ウェーブレングス',   spineColor:Color(0xFF1A3A5A), spineTextColor:Color(0xFF88DDFF),   size:BoxSize.tiny,   faceAspect:0.88),
  Game(id:'exploding_kit', bggId:172225, title:'エクスプローディングキトゥンズ',spineColor:Color(0xFFFFAA00),spineTextColor:Color(0xFF1A0800), size:BoxSize.tiny, faceAspect:0.88),
  Game(id:'insider',       bggId:206823, title:'インサイダーゲーム', spineColor:Color(0xFF222222), spineTextColor:Color(0xFFFFDD00),   size:BoxSize.tiny,   faceAspect:0.75),
  Game(id:'skull_king',    bggId:227628, title:'スカルキング',       spineColor:Color(0xFF0A1A3A), spineTextColor:Color(0xFFFFCC44),   size:BoxSize.tiny,   faceAspect:0.75),
];
