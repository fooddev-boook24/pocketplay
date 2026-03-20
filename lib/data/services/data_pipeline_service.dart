import 'dart:developer' as dev;
import '../models/game.dart';
import '../repositories/game_data_repository.dart';
import '../repositories/rakuten_repository.dart';
import '../repositories/yahoo_repository.dart';

/// 起動時パイプライン:
/// 1. Firestoreにデータがあれば返す
/// 2. なければローカルシードデータをFirestoreに投入して返す
class DataPipelineService {
  DataPipelineService._();
  static final instance = DataPipelineService._();

  final _repo = GameDataRepository.instance;
  final _rakuten = RakutenRepository.instance;
  final _yahoo = YahooRepository.instance;

  // バッチ完了後に呼ばれるコールバック（gamesProviderをinvalidate）
  void Function()? onBatchComplete;

  Future<List<Game>> getGames() async {
    try {
      final firestoreGames = await _repo.fetchGames();

      if (firestoreGames.isNotEmpty) {
        dev.log('Using ${firestoreGames.length} games from Firestore', name: 'DataPipelineService');
        // kSeedGamesのlocalAssetをマージ（Firestoreには保存しないローカルパス）
        final games = _mergeLocalAssets(firestoreGames);
        // サムネイルがないゲームを楽天バッチ取得（バックグラウンド）
        Future.delayed(Duration.zero, () => _batchFetchMissing(games));
        return games;
      }

      // Firestoreが空 → シードデータを投入
      dev.log('Firestore empty, seeding with local data...', name: 'DataPipelineService');
      await _repo.saveGames(_buildSeedGames());
      dev.log('Seeded ${kSeedGames.length} games to Firestore', name: 'DataPipelineService');
      return kSeedGames;
    } catch (e) {
      dev.log('getGames error: $e — fallback to local', name: 'DataPipelineService');
      return kSeedGames;
    }
  }

  /// thumbnailUrl/rakutenAffUrlが未取得のゲームを楽天でバッチ取得
  Future<void> _batchFetchMissing(List<Game> games) async {
    final missing = games
        .where((g) => g.rakutenAffUrl == null || g.rakutenAffUrl!.isEmpty)
        .toList();
    if (missing.isEmpty) return;

    dev.log('Batch fetching Rakuten for ${missing.length} games',
        name: 'DataPipelineService');
    int count = 0;
    for (final game in missing) {
      await getOrFetchRakutenUrl(game);
      count++;
      // レート制限対策: 1秒間隔
      if (count < missing.length) {
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    dev.log('Batch complete ($count games)', name: 'DataPipelineService');
    // 棚を再描画するためにコールバックを呼ぶ
    onBatchComplete?.call();
  }

  /// 楽天アフィリエイトURL + 画像を取得してFirestoreに保存
  Future<String?> getOrFetchRakutenUrl(Game game) async {
    try {
      final result = await _rakuten.fetchResult(game);
      if (result == null) return null;

      // 楽天画像は正方形の商品写真 → ぼかし背景用にthumbnailUrlとして保存
      // imageUrl（ボックス正面に使用）には設定しない（歪み防止）
      final updated = game.copyWith(
        rakutenAffUrl: result.affiliateUrl,
        thumbnailUrl: game.thumbnailUrl == null ? result.imageUrl : null,
      );
      await _repo.saveGame(updated);
      dev.log('Saved Rakuten data for ${game.id} '
          '(image: ${result.imageUrl != null})',
          name: 'DataPipelineService');

      return result.affiliateUrl;
    } catch (e) {
      dev.log('getOrFetchRakutenUrl error: $e', name: 'DataPipelineService');
      return null;
    }
  }

  /// Yahoo!ショッピングURL取得（オンデマンド）
  Future<String?> getOrFetchYahooUrl(Game game) async {
    try {
      final result = await _yahoo.fetchResult(game);
      if (result?.url == null) return null;
      final updated = game.copyWith(
        thumbnailUrl: game.thumbnailUrl == null ? result!.imageUrl : null,
      );
      await _repo.saveGame(updated);
      dev.log('Saved Yahoo data for ${game.id}', name: 'DataPipelineService');
      return result!.url;
    } catch (e) {
      dev.log('getOrFetchYahooUrl error: $e', name: 'DataPipelineService');
      return null;
    }
  }

  /// kSeedGamesのlocalAssetとマージ（Firestoreデータを優先）
  List<Game> _mergeLocalAssets(List<Game> firestoreGames) {
    return firestoreGames.map((fg) {
      final seed = kSeedGames.firstWhere(
        (s) => s.id == fg.id,
        orElse: () => fg,
      );
      // Firestoreにimageがあればそちらを使い、なければlocalAssetへフォールバック
      if (fg.imageUrl != null) return fg;
      if (seed.localAsset != null) {
        return fg.copyWith(imageUrl: seed.imageUrl);
      }
      return fg;
    }).toList();
  }

  /// Firestoreに投入するシードゲームリスト（スクリプトのデータをGameオブジェクトへ）
  List<Game> _buildSeedGames() => _seedData.map((d) {
    final base = kSeedGames.firstWhere(
      (g) => g.id == d['id'],
      orElse: () => kSeedGames.first,
    );
    return base.copyWith(
      minPlayers:     d['minPlayers'] as int?,
      maxPlayers:     d['maxPlayers'] as int?,
      playTimeMinutes: d['playTimeMinutes'] as int?,
      bggRating:      (d['bggRating'] as num).toDouble(),
      categories:     (d['categories'] as List).cast<String>(),
      description:    d['description'] as String?,
    );
  }).toList();
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
