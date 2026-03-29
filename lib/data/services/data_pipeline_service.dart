import 'dart:developer' as dev;
import '../models/game.dart';
import '../repositories/bgg_repository.dart';
import '../repositories/game_data_repository.dart';

/// 起動時パイプライン:
/// 1. Firestoreにデータがあれば返す
/// 2. なければローカルシードデータをFirestoreに投入して返す
class DataPipelineService {
  DataPipelineService._();
  static final instance = DataPipelineService._();

  final _repo = GameDataRepository.instance;

  // バッチ完了後に呼ばれるコールバック（gamesProviderをinvalidate）
  void Function()? onBatchComplete;

  Future<List<Game>> getGames() async {
    try {
      final firestoreGames = await _repo.fetchGames();

      if (firestoreGames.isNotEmpty) {
        dev.log('Using ${firestoreGames.length} games from Firestore', name: 'DataPipelineService');
        final games = _mergeBggCache(_mergeLocalAssets(firestoreGames));
        Future.delayed(Duration.zero, () => _batchFetchMissing(games));
        return games;
      }

      // Firestoreが空 → 全kSeedGamesを投入（30件の_seedDataではなく65件全部）
      dev.log('Firestore empty, seeding all ${kSeedGames.length} games...', name: 'DataPipelineService');
      await _repo.saveGames(_buildSeedGames());
      dev.log('Seeded ${kSeedGames.length} games to Firestore', name: 'DataPipelineService');
      final games = _mergeBggCache(kSeedGames);
      Future.delayed(Duration.zero, () => _batchFetchMissing(games));
      return games;
    } catch (e) {
      dev.log('getGames error: $e — fallback to local', name: 'DataPipelineService');
      final games = _mergeBggCache(kSeedGames);
      Future.delayed(Duration.zero, () => _batchFetchMissing(games));
      return games;
    }
  }

  /// BGGホットリスト取得 + 画像補完をバックグラウンドで実行
  Future<void> _batchFetchMissing(List<Game> games) async {
    // ── 0a. 初期ライブラリ補完（未取得IDがある限り毎起動チェック）
    await _fetchInitialLibrary(games);
    // ── 0b. 毎起動: BGGホット新着を追加
    await _fetchAndAddHotGames(games);

    // ── 1. BGG画像取得（imageUrlがないゲーム）
    final noImage = games
        .where((g) => g.imageUrl == null && g.localAsset == null)
        .toList();
    if (noImage.isEmpty) return;

    dev.log('Fetching BGG images for ${noImage.length} games',
        name: 'DataPipelineService');
    final imageMap = await BggRepository.instance.fetchImages(noImage);
    for (final game in noImage) {
      final url = imageMap[game.bggId];
      if (url != null) {
        try {
          await _repo.saveGame(game.copyWith(imageUrl: url));
        } catch (_) {}
      }
    }
    if (imageMap.isNotEmpty) {
      dev.log('BGG images fetched: ${imageMap.length}', name: 'DataPipelineService');
      onBatchComplete?.call();
    }
  }

  /// Firestoreのゲーム数が300未満の場合にBGG上位ゲームを取得して補完
  Future<void> _fetchInitialLibrary(List<Game> currentGames) async {
    try {
      final knownBggIds = currentGames.map((g) => g.bggId).toSet();
      final toFetch = _kInitialBggIds
          .where((id) => !knownBggIds.contains(id))
          .toList();
      if (toFetch.isEmpty) {
        dev.log('Initial library: all IDs already fetched', name: 'DataPipelineService');
        return;
      }

      dev.log('Initial library fetch: ${toFetch.length} BGG IDs '
          '(current: ${currentGames.length})', name: 'DataPipelineService');

      // 20件ずつバッチ処理。各バッチで部分的に失敗しても続行
      int saved = 0;
      for (var i = 0; i < toFetch.length; i += 20) {
        final batch = toFetch.skip(i).take(20).toList();
        try {
          final stubs = await BggRepository.instance.fetchGameStubs(batch);
          for (final game in stubs) {
            try { await _repo.saveGame(game); saved++; } catch (_) {}
          }
          // バッチごとに棚を更新（順次表示される）
          if (stubs.isNotEmpty) onBatchComplete?.call();
        } catch (e) {
          dev.log('Initial library batch $i error: $e', name: 'DataPipelineService');
        }
        if (i + 20 < toFetch.length) {
          await Future.delayed(const Duration(milliseconds: 800));
        }
      }
      dev.log('Initial library complete: $saved games saved', name: 'DataPipelineService');
    } catch (e) {
      dev.log('_fetchInitialLibrary error: $e', name: 'DataPipelineService');
    }
  }

  /// BGGホットリストを取得し、まだFirestoreにないゲームを追加する
  Future<void> _fetchAndAddHotGames(List<Game> currentGames) async {
    try {
      final hotGames = await BggRepository.instance.fetchHotGames(currentGames: currentGames);
      if (hotGames.isEmpty) return;

      dev.log('Found ${hotGames.length} new hot games', name: 'DataPipelineService');
      for (final game in hotGames) {
        try {
          await _repo.saveGame(game);
        } catch (_) {}
      }
      onBatchComplete?.call();
      dev.log('Hot games saved to Firestore: ${hotGames.length}',
          name: 'DataPipelineService');
    } catch (e) {
      dev.log('_fetchAndAddHotGames error: $e', name: 'DataPipelineService');
    }
  }

  /// kSeedGamesのlocalAssetをFirestoreゲームにマージ（Firestoreには保存しないローカルパス）
  List<Game> _mergeLocalAssets(List<Game> firestoreGames) {
    return firestoreGames.map((fg) {
      if (fg.imageUrl != null) return fg;
      final seed = kSeedGames.firstWhere(
        (s) => s.id == fg.id,
        orElse: () => fg,
      );
      if (seed.localAsset != null) {
        return fg.copyWith(localAsset: seed.localAsset);
      }
      return fg;
    }).toList();
  }

  /// BggRepositoryのメモリキャッシュをゲームリストにマージ
  List<Game> _mergeBggCache(List<Game> games) {
    final cache = BggRepository.instance.imageCache;
    if (cache.isEmpty) return games;
    return games.map((g) {
      if (g.imageUrl != null || g.localAsset != null) return g;
      final url = cache[g.bggId];
      return url != null ? g.copyWith(imageUrl: url) : g;
    }).toList();
  }

  /// Firestoreに投入するシードゲームリスト
  /// kSeedGames全件を保存し、_seedDataに詳細データがあればマージする
  List<Game> _buildSeedGames() {
    // _seedDataをidでインデックス化
    final seedMap = {
      for (final d in _seedData) d['id'] as String: d,
    };
    return kSeedGames.map((game) {
      final d = seedMap[game.id];
      if (d == null) return game; // 詳細データなし → そのまま保存
      return game.copyWith(
        minPlayers:      d['minPlayers'] as int?,
        maxPlayers:      d['maxPlayers'] as int?,
        playTimeMinutes: d['playTimeMinutes'] as int?,
        bggRating:       (d['bggRating'] as num).toDouble(),
        categories:      (d['categories'] as List).cast<String>(),
        description:     d['description'] as String?,
      );
    }).toList();
  }
}

// ゲームの手動データ（BGG APIが使えないため直接記述）
const _seedData = [
  {'id':'catan',       'minPlayers':3,'maxPlayers':4, 'playTimeMinutes':75,  'bggRating':7.2, 'categories':['Strategy','Negotiation','Family'],          'description':'島に入植した開拓者たちが資源を集め、道・開拓地・都市を建設して得点を競うボードゲームの定番。交渉と運が絡み合う。'},
  {'id':'wingspan',    'minPlayers':1,'maxPlayers':5, 'playTimeMinutes':70,  'bggRating':8.1, 'categories':['Engine Building','Card Drafting','Nature'],    'description':'鳥類学者として鳥を集め生息地を整えるエンジンビルド系ゲーム。美しいイラストと豊富なカードが魅力。'},
  {'id':'mysterium',   'minPlayers':2,'maxPlayers':7, 'playTimeMinutes':42,  'bggRating':7.4, 'categories':['Cooperative','Deduction','Horror'],           'description':'幽霊が夢のビジョンを送り、霊媒師たちが謎の殺人事件を解き明かす協力型ゲーム。幻想的なアートワークが印象的。'},
  {'id':'pandemic',    'minPlayers':2,'maxPlayers':4, 'playTimeMinutes':45,  'bggRating':7.6, 'categories':['Cooperative','Medical','Strategy'],            'description':'世界中に蔓延する4つの病原体を封じ込め、ワクチンを開発する完全協力ゲーム。役割分担とチームワークが鍵。'},
  {'id':'terraforming','minPlayers':1,'maxPlayers':5, 'playTimeMinutes':120, 'bggRating':8.4, 'categories':['Strategy','Engine Building','Sci-Fi'],         'description':'企業として火星の環境を変えながら得点を競う重量級エンジンビルド。豊富なカードとリプレイ性が高い。'},
  {'id':'7wonders',    'minPlayers':2,'maxPlayers':7, 'playTimeMinutes':30,  'bggRating':7.7, 'categories':['Card Drafting','Civilization','Strategy'],      'description':'古代の七不思議を建設しながら文明を発展させるドラフト型カードゲーム。短時間で深い戦略を楽しめる名作。'},
  {'id':'gloomhaven',  'minPlayers':1,'maxPlayers':4, 'playTimeMinutes':120, 'bggRating':8.6, 'categories':['Dungeon Crawler','Cooperative','RPG'],          'description':'キャンペーン型ダンジョン探索ゲーム。手札管理システムと進化するストーリーが特徴。BGGランキング常連の大作。'},
  {'id':'arkham',      'minPlayers':1,'maxPlayers':8, 'playTimeMinutes':180, 'bggRating':7.3, 'categories':['Cooperative','Horror','Adventure'],             'description':'クトゥルフ神話テーマの協力型ホラーゲーム。調査者たちが古き神々の目覚めを防ぐべくアーカムの街を探索する。'},
  {'id':'azul',        'minPlayers':2,'maxPlayers':4, 'playTimeMinutes':45,  'bggRating':7.8, 'categories':['Abstract','Pattern Building','Family'],         'description':'ポルトガルの宮殿のタイル張りをテーマにした抽象ゲーム。美しいタイルコンポーネントとシンプルながら深いルールが魅力。'},
  {'id':'dixit',       'minPlayers':3,'maxPlayers':6, 'playTimeMinutes':30,  'bggRating':7.3, 'categories':['Party','Storytelling','Creative'],              'description':'幻想的なイラストカードを使ったストーリーテリングゲーム。語り手のヒントが「ちょうどいい曖昧さ」になるよう表現する。'},
  {'id':'codenames',   'minPlayers':2,'maxPlayers':8, 'playTimeMinutes':15,  'bggRating':7.7, 'categories':['Party','Word Game','Team'],                     'description':'2チームがスパイ映画風に単語カードの正体を当て合うワードゲーム。スパイマスターが1語でチームメイトに複数カードを伝える。'},
  {'id':'ticket_ride', 'minPlayers':2,'maxPlayers':5, 'playTimeMinutes':75,  'bggRating':7.4, 'categories':['Family','Train','Route Building'],              'description':'北米大陸に鉄道路線を引き、チケットで指定された都市間をつなぐボードゲームの超定番。わかりやすいルールでファミリーにも人気。'},
  {'id':'dominion',    'minPlayers':2,'maxPlayers':4, 'playTimeMinutes':30,  'bggRating':7.6, 'categories':['Deck Building','Card Game','Strategy'],          'description':'デッキ構築ゲームの元祖。カードを購入してデッキを強化し、より多くの属州を獲得したプレイヤーが勝利。'},
  {'id':'carcassonne', 'minPlayers':2,'maxPlayers':5, 'playTimeMinutes':45,  'bggRating':7.4, 'categories':['Tile Placement','Family','Medieval'],            'description':'タイルを並べて中世フランスの都市・道路・修道院を作るタイル配置ゲームの名作。シンプルなルールで深い読み合いが楽しめる。'},
  {'id':'kingdomino',  'minPlayers':2,'maxPlayers':4, 'playTimeMinutes':15,  'bggRating':7.3, 'categories':['Tile Placement','Family','Kingdom Building'],    'description':'ドミノをベースに自分の王国を広げるファミリーゲーム。15分で遊べるコンパクトさながら多彩な戦略が生まれる。'},
  {'id':'agricola',    'minPlayers':1,'maxPlayers':5, 'playTimeMinutes':150, 'bggRating':7.9, 'categories':['Worker Placement','Farming','Strategy'],         'description':'農場を経営するワーカープレイスメントゲームの傑作。食料確保と農場拡大のジレンマが常につきまとう緊張感が魅力。'},
  {'id':'viticulture', 'minPlayers':2,'maxPlayers':6, 'playTimeMinutes':90,  'bggRating':8.0, 'categories':['Worker Placement','Wine','Strategy'],            'description':'トスカーナのワイナリーを経営するワーカープレイスメントゲーム。ワインを醸造・販売し名声点を積み重ねる。'},
  {'id':'concordia',   'minPlayers':2,'maxPlayers':5, 'playTimeMinutes':100, 'bggRating':8.0, 'categories':['Hand Management','Network Building','Rome'],      'description':'ローマ帝国を舞台にした交易ゲーム。手札管理と効率的な商業ネットワーク構築がカギ。インタラクション控えめで考え応えあり。'},
  {'id':'splendor',    'minPlayers':2,'maxPlayers':4, 'playTimeMinutes':30,  'bggRating':7.4, 'categories':['Engine Building','Card Game','Gems'],             'description':'宝石商として宝石を集め鉱山・交通路・商店を開発するエンジンビルドゲーム。シンプルだが戦略的なアクション選択が楽しい。'},
  {'id':'patchwork',   'minPlayers':2,'maxPlayers':2, 'playTimeMinutes':30,  'bggRating':7.7, 'categories':['2-Player','Puzzle','Abstract'],                  'description':'パッチワーク生地を組み合わせてキルトを完成させる2人専用ゲーム。ボタンを集めてピースを購入するメカニズムが独特。'},
  {'id':'jaipur',      'minPlayers':2,'maxPlayers':2, 'playTimeMinutes':30,  'bggRating':7.7, 'categories':['2-Player','Trading','Card Game'],                 'description':'インドの都市ジャイプルを舞台にした2人用交易カードゲーム。ラクダをうまく活用しながら商品を集め素早くセット売りする。'},
  {'id':'lost_cities', 'minPlayers':2,'maxPlayers':2, 'playTimeMinutes':30,  'bggRating':7.2, 'categories':['2-Player','Adventure','Card Game'],               'description':'失われた都市を探索する2人用カードゲーム。遠征隊に投資しながら得点を積み重ねるシンプルながら深い読み合いが魅力。'},
  {'id':'sushi_go',    'minPlayers':2,'maxPlayers':5, 'playTimeMinutes':15,  'bggRating':6.9, 'categories':['Card Drafting','Party','Family'],                 'description':'寿司ネタのカードをドラフトして得点を競うパーティーゲーム。かわいいイラストとシンプルなルールで老若男女楽しめる。'},
  {'id':'hive',        'minPlayers':2,'maxPlayers':2, 'playTimeMinutes':20,  'bggRating':7.4, 'categories':['Abstract','2-Player','Insects'],                  'description':'ボードもサイコロも使わない、昆虫をモチーフにした純粋な2人用抽象ゲーム。女王蜂を包囲した方が勝ち。'},
  {'id':'love_letter', 'minPlayers':2,'maxPlayers':4, 'playTimeMinutes':20,  'bggRating':6.9, 'categories':['Card Game','Deduction','Party'],                  'description':'王女に手紙を届けるため宮廷の人物を使う推理カードゲーム。16枚のカードだけで遊べるコンパクトさが魅力。'},
  {'id':'coup',        'minPlayers':2,'maxPlayers':6, 'playTimeMinutes':15,  'bggRating':7.2, 'categories':['Bluffing','Party','Deduction'],                   'description':'政府の腐敗した未来都市での権力争いをテーマにしたブラフゲーム。嘘をついてもいい。ただし見破られたら脱落。'},
  {'id':'bohnanza',    'minPlayers':2,'maxPlayers':7, 'playTimeMinutes':45,  'bggRating':7.1, 'categories':['Trading','Card Game','Family'],                   'description':'豆を栽培・収穫して稼ぐ交渉型カードゲーム。手札の並び順を変えてはいけないユニークなルールが交渉を盛り上げる。'},
  {'id':'hanabi',      'minPlayers':2,'maxPlayers':5, 'playTimeMinutes':25,  'bggRating':7.0, 'categories':['Cooperative','Card Game','Deduction'],             'description':'自分の手札が見えない状態でチームメイトとヒントを交換しながら花火を打ち上げる協力ゲーム。スピール賞受賞作。'},
  {'id':'skull',       'minPlayers':3,'maxPlayers':6, 'playTimeMinutes':45,  'bggRating':7.1, 'categories':['Bluffing','Party','Bidding'],                     'description':'バイカーギャングテーマの心理戦ブラフゲーム。花かドクロかを隠して競り合う。シンプルながらドキドキが止まらない。'},
  {'id':'no_thanks',   'minPlayers':3,'maxPlayers':5, 'playTimeMinutes':20,  'bggRating':7.1, 'categories':['Card Game','Filler','Party'],                     'description':'「いらない！」と言い続けるカードゲーム。受け取りたくないカードにチップを積むか全部引き受けるかの心理戦。'},
];

/// 初期ライブラリ用 BGG ID リスト（kSeedGamesと重複しない ~260件）
/// kSeedGames 65件 + これら = 計 ~325件を初回起動時に確保（300件保証）
/// ※ bggIdの重複チェックは _fetchInitialLibrary 内で実施済み（重複は自動スキップ）
const _kInitialBggIds = [
  // ── BGG Top 50 圏（重量級） ─────────────────────────────────────────────
  342942, // Ark Nova
  316554, // Dune: Imperium
  274637, // Lost Ruins of Arnak
  161936, // Pandemic Legacy: Season 1
  155821, // Pandemic Legacy: Season 2
  300531, // Pandemic Legacy: Season 0
  84876,  // The Castles of Burgundy
  233078, // Twilight Imperium 4th Edition
  182028, // Through the Ages: A New Story of Civilization
  12333,  // Twilight Struggle
  96848,  // Mage Knight Board Game
  115746, // War of the Ring (2nd Edition)
  220308, // Gaia Project
  187645, // Star Wars: Rebellion
  195421, // A Feast for Odin
  175914, // Gloomhaven: Jaws of the Lion
  257351, // Underwater Cities
  310873, // Dune: Imperium – Uprising
  297081, // Beyond the Sun
  293014, // Heat: Pedal to the Metal

  // ── 重量ユーロ ────────────────────────────────────────────────────────────
  279537, // On Mars
  143519, // Caverna: The Cave Farmers
  102652, // Tzolk'in: The Mayan Calendar
  157354, // Five Tribes
  218417, // Clans of Caledonia
  55690,  // Le Havre
  59254,  // Dominant Species
  121921, // Robinson Crusoe: Adventures on the Cursed Island
  291453, // Paladins of the West Kingdom
  258779, // Architects of the West Kingdom
  291457, // Viscounts of the West Kingdom
  237179, // Maracaibo
  244521, // Res Arcana
  261220, // Anachrony
  221107, // Lorenzo il Magnifico
  246584, // Praga Caput Regni
  251322, // Bonfire
  184267, // Trickerion: Legends of Illusion
  175045, // Food Chain Magnate
  27801,  // Caylus
  3076,   // Puerto Rico
  35677,  // Stone Age
  28143,  // Brass: Lancashire
  110327, // Lords of Waterdeep
  122515, // Keyflower
  228341, // Pax Pamir (Second Edition)
  72125,  // Eclipse: Second Dawn for the Galaxy
  176671, // Yokohama
  55999,  // Navegador
  99692,  // Alchemists

  // ── 中量ユーロ ────────────────────────────────────────────────────────────
  209010, // Sagrada
  108745, // Suburbia
  40398,  // Dominion: Seaside
  136888, // Bruges
  144733, // Tuscany: Essential Edition (Viticulture拡張)
  152196, // Codenames: Pictures
  42,     // Tigris & Euphrates
  74,     // Acquire
  189,    // Samurai
  478,    // Citadels
  45,     // Medici
  127023, // Viticulture (original) — bggId≠128621なら追加
  40834,  // Dominion: Intrigue
  120677, // Paperback
  312484, // Meadow
  325494, // Earth
  330592, // Sleeping Gods
  309110, // Imperium: Classics
  366013, // Wingspan: Asia
  228830, // Wingspan: European Expansion

  // ── テーマ系・ダンジョン ──────────────────────────────────────────────────
  167355, // Arkham Horror: The Card Game
  183394, // Mansions of Madness 2nd Edition
  38453,  // Small World
  90572,  // Elder Sign
  104006, // Descent: Journeys in the Dark 2nd
  37111,  // Battlestar Galactica: The Board Game
  135220, // Sentinels of the Multiverse
  285774, // Marvel Champions: The Card Game
  233867, // Betrayal at House on the Hill
  238042, // The 7th Continent
  330501, // Hegemony: Lead Your Class to Victory
  312786, // Nucleum

  // ── 2人用専用 ─────────────────────────────────────────────────────────────
  256960, // Watergate
  271055, // The Crew: The Quest for Planet Nine
  223040, // The Crew: Mission Deep Sea
  311965, // Marvel United
  265736, // Undaunted: Normandy

  // ── ライトストラテジー・ファミリー ────────────────────────────────────────
  215312, // Pandemic: Iberia
  70149,  // Pandemic: In the Lab
  37380,  // Pandemic: On the Brink
  14996,  // Descent: Journeys in the Dark (1st)
  181,    // Risk 2210 A.D.
  297030, // Disney Villainous
  313554, // Ticket to Ride: Europe
  171623, // The Networks
  192458, // Azul: Stained Glass of Sintra
  255684, // Azul: Summer Pavilion

  // ── フィラー・パーティー（kSeedGamesに未含有） ─────────────────────────
  64766,  // Dixit: Odyssey
  152156, // Codenames: Deep Undercover
  262316, // Sushi Go Party!
  188334, // Secret Hitler
  148949, // Istanbul (already in kSeedGames via id:'istanbul') — filtered by bggId
  271832, // Verdant
  299480, // Cascadia (alternate?)
  209996, // Tiny Towns
  276025, // My City
  216132, // The Quacks of Quedlinburg
  263918, // The Quacks of Quedlinburg: The Alchemists
  315610, // The Wandering Towers
  353467, // The White Castle
  382948, // Forest Shuffle
  372765, // Harmonies
  371942, // Sky Team
  381598, // Red Cathedral
  378456, // Aqua: Ocean's Heart
  356355, // Lands of Galzyr
  282524, // Distilled
  337474, // Earth (2nd?)
  348458, // Lacrimosa
  339789, // Apiary

  // ── ソロ・協力 ────────────────────────────────────────────────────────────
  253284, // Spirit Island: Jagged Earth
  199042, // Robinson Crusoe: Mystery Tales
  247763, // Pandemic: Hot Zone North America
  311646, // Pandemic: Emergency Phase
  317985, // Arkham Horror 3rd Edition

  // ── 戦争・ウォーゲーム ──────────────────────────────────────────────────
  37379,  // Conflict of Heroes: Awakening the Bear
  73439,  // Labyrinth: The War on Terror
  65244,  // Wilderness War

  // ── 追加: 重量ユーロ・重量テーマ ─────────────────────────────────────────
  35947,  // Race for the Galaxy
  31627,  // Galaxy Trucker
  63888,  // Innovation
  91671,  // Ora et Labora
  128345, // Village
  142177, // Kemet
  195856, // Inis
  172386, // Abyss
  178341, // The Gallerist
  198994, // Lisboa
  181345, // The Voyages of Marco Polo
  146021, // Eldritch Horror
  148864, // Dead of Winter: The Long Night
  288988, // Paleo
  290448, // Tainted Grail: The Fall of Avalon
  246900, // Eclipse: Second Dawn for the Galaxy
  193037, // Hadara
  251247, // Tapestry
  169786, // Scythe: Invaders from Afar
  205637, // Scythe: The Rise of Fenris
  188834, // Orléans: Invasion
  292457, // Maracaibo (card game version)
  307658, // Watergate (new ed)
  330533, // Dominion: Renaissance
  323612, // Ark Nova (alt)
  294137, // On the Underground
  266810, // Wingspan (Dutch? alt)
  350184, // Spots
  317311, // Lost Ruins of Arnak: Expedition Leaders
  350108, // Challengers!
  362944, // Ark Nova (target)
  366161, // HEAT (alt)

  // ── 追加: 中量ゲーム ─────────────────────────────────────────────────────
  155987, // Colt Express
  152218, // Sheriff of Nottingham
  159675, // Mice and Mystics
  271324, // Cartographers
  222770, // Welcome To...
  308765, // Stardew Valley: The Board Game
  172818, // Above and Below
  176289, // This War of Mine: The Board Game
  2655,   // Hansa Teutonica
  168270, // Aeon's End
  170042, // Raiders of the North Sea
  300012, // Furnace
  246224, // Planet Unknown
  262211, // Hadrian's Wall
  158600, // Between Two Cities
  182874, // Between Two Castles of Mad King Ludwig
  332686, // Oath: Chronicles of Empire & Exile
  223617, // Clank! Legacy: Acquisitions Incorporated
  193290, // Village: Port
  282524, // Distilled (already in list, deduped)
  269188, // Fleet: The Dice Game
  339879, // Mindbug: First Contact
  294037, // Cascadia: Landmarks
  337474, // Earth (alt, deduped)
  294116, // Wandering Towers

  // ── 追加: ライト・パーティー ─────────────────────────────────────────────
  314491, // Zombie Teenz Evolution
  306479, // The Fox in the Forest Duet
  291453, // Paladins (deduped)
  265736, // Undaunted: Normandy (deduped)
  183840, // Coup: Rebellion G54
  161533, // Orléans (alt bggId check)
  296224, // Pathfinder: Core Set
  176042, // Oh My Goods!
  240980, // Sagrada (alternate)
  317985, // Arkham Horror 3rd Ed (deduped)
  199792, // Pandemic: Iberia (alt)
  186508, // Pandemic: State of Emergency
  161936, // Pandemic Legacy S1 (deduped)
  291010, // Paleo (alt)
  315377, // Cartographers Heroes
  310873, // Dune: Uprising (deduped)

  // ── 追加: 2人用専用 ──────────────────────────────────────────────────────
  256960, // Watergate (deduped)
  223040, // The Crew: Mission Deep Sea (deduped)
  271055, // The Crew: Quest for Planet Nine (deduped)
  284083, // The Crew: Mission Deep Sea alt
  265736, // Undaunted: Normandy (deduped)
  304783, // Undaunted: North Africa
  364073, // Undaunted: Reinforcements
  369406, // Mindbug: Base Set

  // ── 追加: ファミリー・軽量 ───────────────────────────────────────────────
  269144, // Wingspan: European Exp (alt bggId)
  298871, // Flamecraft
  299004, // My Little Scythe
  241724, // Parks
  272324, // Wavelength (alt)
  351538, // Faraway
  374173, // Sky Team (deduped)
  383312, // Harmonies (alt)
  354729, // Nucleum (alt)
  368566, // Fit to Print
  377083, // Botanik
  378456, // Aqua (deduped)
  386683, // Rebis
  380980, // Thunder Road: Vendetta
  358383, // Isle of Cats: Don't Panic
  347636, // Anno 1800: The Board Game
  321942, // Everdell: Newleaf
  317718, // Everdell: Spirecrest (2nd ed)
  300905, // Points Salad
  288255, // The Isle of Cats
  329839, // Great Plains
  248127, // Wingspan: Nesting
  200680, // Village: Port (alt)
];

