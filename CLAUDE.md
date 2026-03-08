# PocketPlay — CLAUDE.md
## Claude Code 自律開発仕様書

---

## 0. このファイルの目的

Claude Code がこのリポジトリで自律的に開発を進めるための完全な仕様・ルール・判断基準を記述する。
不明点が生じた場合はこのファイルを最優先の根拠とすること。

---

## 1. プロダクト概要

**PocketPlay** — ボードゲーム専門店の棚をスマホで再現するディスカバリーアプリ。

### コアバリュー（絶対に忘れないこと）
1. **没入感が最優先** — EC一覧UIは絶対禁止。実店舗の棚を歩く感覚の再現
2. **ジャケ買いを促す** — パッケージ画像の実在感がすべて
3. **アフィリエイト収益** — 楽天商品ページへの誘導がマネタイズの核

### ターゲットユーザー
ボードゲームに興味があるが何を買えばいいか分からない人。
「検索」ではなく「棚を眺めて偶然の出会いを楽しむ」体験を求める人。

---

## 2. 技術スタック

```
Flutter (iOS/Android)
Dart SDK: ^3.6.0
State: flutter_riverpod ^2.6.1 + hooks_riverpod ^2.6.1 + flutter_hooks ^0.20.5
Images: cached_network_image ^3.3.1
Fonts: google_fonts ^6.2.1
HTTP: http ^1.2.0
XML: xml ^6.5.0
Backend: Firebase (Firestore + Functions + Storage)
```

### 追加が必要なパッケージ（実装時に pubspec.yaml へ追加すること）
```yaml
# アニメーション
flutter_animate: ^4.5.0

# Firebase
firebase_core: ^3.x.x
cloud_firestore: ^5.x.x
firebase_storage: ^12.x.x
firebase_auth: ^5.x.x  # 将来用

# ディープリンク
url_launcher: ^6.3.x

# ローカルキャッシュ
shared_preferences: ^2.3.x

# 画像処理
flutter_cache_manager: ^3.4.x
```

---

## 3. プロジェクト構成

### 現在の構成（変更禁止ファイル）
```
lib/
  main.dart
  data/
    models/game.dart              # Gameモデル、kSeedGames (30タイトル)
    repositories/
      bgg_repository.dart         # BGG XMLAPIクライアント
      game_provider.dart          # Riverpod provider + ShelfRow定義
  features/home/
    home_screen.dart              # メイン画面 (InteractiveViewer + 電球照明)
  shelf/
    box_widgets.dart              # FaceBoxWidget, SpineBoxWidget, StackBoxWidget
    shelf_engine.dart             # PlacedBox, PlacedPop, ShelfLayoutEngine
    shelf_wall.dart               # ShelfWall, POPカード, 棚板, 柱
```

### 追加する構成
```
lib/
  data/
    models/
      game.dart                   # 拡張（下記参照）
      game_detail.dart            # NEW: 詳細データモデル
      affiliate_link.dart         # NEW: アフィリエイトリンクモデル
    repositories/
      bgg_repository.dart         # 拡張（画像+詳細データ取得）
      rakuten_repository.dart     # NEW: 楽天商品検索
      game_data_repository.dart   # NEW: Firestore CRUD
      game_provider.dart          # 拡張
    services/
      data_pipeline_service.dart  # NEW: BGG→楽天→Firestore自動パイプライン
      affiliate_service.dart      # NEW: アフィリエイトURL生成
  features/
    home/
      home_screen.dart            # 既存（タップアニメーション追加）
    game_detail/
      game_detail_screen.dart     # NEW: 詳細画面
      game_detail_provider.dart   # NEW
    search/
      search_screen.dart          # NEW（後回しOK）
  shelf/
    box_widgets.dart              # 拡張（タップアニメーション）
    shelf_engine.dart             # 既存
    shelf_wall.dart               # 既存
  core/
    firebase_options.dart         # NEW: Firebase設定（手動作成後に配置）
    constants.dart                # NEW: API keys等の定数
```

---

## 4. データモデル仕様

### 4.1 Game モデル拡張（game.dart）

現在の`Game`クラスに以下フィールドを追加する：

```dart
class Game {
  // 既存フィールドはそのまま維持
  final String id;
  final int bggId;
  final String title;
  final Color spineColor;
  final Color spineTextColor;
  final BoxSize size;
  final double faceAspect;
  final String? imageUrl;        // BGG正面画像URL
  final String? localAsset;

  // 追加フィールド
  final String? spineImageUrl;   // 背表紙画像URL（BGGまたは生成）
  final String? thumbnailUrl;    // サムネイル（小サイズ）
  final int? minPlayers;
  final int? maxPlayers;
  final int? playTimeMinutes;
  final double? bggRating;       // BGGスコア
  final List<String> categories; // ['戦略', '2人用', etc.]
  final String? description;     // ゲーム説明（日本語優先）
  final String? publisherJp;     // 日本語版発売元
  final bool isAvailableInJapan; // 日本語版あり
  
  // アフィリエイト
  final String? rakutenItemCode; // 楽天商品コード（取得できた場合）
  final String? rakutenAffUrl;   // 楽天アフィリエイトURL（生成済み）
  
  // データソース管理
  final DateTime? lastFetched;   // Firestore最終取得日時
  final bool isFirestoreData;    // Firestoreから来たデータかどうか
}
```

### 4.2 GameDetail モデル（game_detail.dart）

詳細画面専用の拡張データ：

```dart
class GameDetail {
  final Game game;
  final List<String> imageUrls;   // 正面/側面/背面など複数画像
  final String? longDescription;
  final List<String> mechanics;   // ['ドラフト', 'ワーカープレイスメント', etc.]
  final List<String> designers;
  final int? yearPublished;
  final double? complexity;       // BGG weight (1-5)
  final List<AffiliateLink> affiliateLinks;
}

class AffiliateLink {
  final String platform;   // 'rakuten'
  final String url;        // アフィリエイトURL
  final String? price;     // 表示価格（取得できた場合）
  final String? shopName;  // 店舗名
}
```

---

## 5. データ取得パイプライン仕様

### 5.1 全体フロー

```
起動時:
  1. Firestore からゲームデータ取得（キャッシュ）
  2. キャッシュがなければ BGG API → Firestore 保存
  3. 楽天APIは詳細画面タップ時にオンデマンド取得

バックグラウンド（Firebase Functions）:
  毎日1回: BGGから新着・更新データを取得しFirestoreを更新
  週1回: 楽天APIで価格・在庫を更新
```

### 5.2 BGG API（既存 + 拡張）

**既存**: `bgg_repository.dart` で画像取得済み

**追加取得項目**:
```
GET https://boardgamegeek.com/xmlapi2/thing?id={bggId}&type=boardgame&stats=1

取得項目:
- <image> / <thumbnail>           → imageUrl, thumbnailUrl
- <name type="primary">           → title (英語)
- <description>                   → description
- <minplayers> / <maxplayers>     → minPlayers / maxPlayers
- <minplaytime> / <maxplaytime>   → playTimeMinutes
- <statistics><ratings><average>  → bggRating
- <link type="boardgamecategory"> → categories
- <link type="boardgamemechanic"> → mechanics
- <link type="boardgamedesigner"> → designers
- <link type="boardgamepublisher">→ publisherJp (日本語発売元を優先)
```

**実装ルール**:
- 既存の`BggRepository`を拡張して`fetchDetail(int bggId)`メソッドを追加
- 202レスポンスは4秒待ってリトライ（既存ロジック維持）
- User-Agent必須: `PocketPlay/1.0 (board game discovery app)`
- バッチサイズ: 20件まで、間隔800ms（既存ロジック維持）
- エラー時はローカルデータにフォールバック

### 5.3 楽天商品検索API

**目的**: ボードゲームの楽天商品ページURLとアフィリエイトリンクを取得

**エンドポイント**:
```
GET https://app.rakuten.co.jp/services/api/IchibaItem/Search/20170706
パラメータ:
  applicationId: {RAKUTEN_APP_ID}        # lib/core/constants.dartに記載
  affiliateId: {RAKUTEN_AFFILIATE_ID}    # lib/core/constants.dartに記載
  keyword: "{ゲームタイトル} ボードゲーム"
  hits: 5                                 # 上位5件取得
  sort: -reviewCount                      # レビュー数順（人気順）
  genreId: 101921                        # 楽天ジャンル: おもちゃ＞ゲーム
  formatVersion: 2
```

**レスポンス処理**:
```dart
// 取得したいフィールド
items[0].itemUrl        → 商品ページURL
items[0].affiliateUrl   → アフィリエイトURL（affiliateIdを渡した場合自動生成）
items[0].itemPrice      → 価格
items[0].shopName       → 店舗名
items[0].itemName       → 商品名（マッチング確認用）
```

**マッチング判定**:
- `itemName`にゲームタイトル（日本語）が含まれるかチェック
- 含まれない場合は英語タイトルでも検索
- それでもマッチしない場合は`affiliateUrl: null`として扱い、リンクボタンを非表示

**実装クラス**: `lib/data/repositories/rakuten_repository.dart`
```dart
class RakutenRepository {
  Future<AffiliateLink?> searchGame(Game game) async { ... }
  Future<List<AffiliateLink>> searchGameMultiple(Game game) async { ... }
}
```

### 5.4 その他のボードゲーム商品データAPI

楽天以外にも以下を検討・実装すること：

**Yahoo!ショッピング API**
```
GET https://shopping.yahooapis.jp/ShoppingWebService/V3/itemSearch
  appid: {YAHOO_APP_ID}
  query: "{タイトル} ボードゲーム"
  hits: 5
→ url フィールドを商品リンクとして使用
```

**カカクコム（非公式）**: スクレイピングは規約違反のため使用しない

**優先順位**: 楽天 → Yahoo!ショッピング → BGGの購入リンク

### 5.5 Firestore データ構造

```
firestore/
  games/
    {gameId}/
      # Game基本データ（全フィールド）
      bggId: number
      title: string
      titleEn: string
      imageUrl: string
      thumbnailUrl: string
      spineColorHex: string        # Colorはint(0xFFxxxxxx)で保存
      spineTextColorHex: string
      boxSize: string              # 'tiny'|'small'|'medium'|'large'
      faceAspect: number
      minPlayers: number
      maxPlayers: number
      playTimeMinutes: number
      bggRating: number
      categories: string[]
      mechanics: string[]
      description: string
      publisherJp: string
      isAvailableInJapan: boolean
      
      # アフィリエイト
      rakutenItemCode: string
      rakutenAffUrl: string
      yahooAffUrl: string
      
      # メタ
      lastFetched: timestamp
      lastAffiliateCheck: timestamp
      
  shelves/
    {shelfId}/
      label: string
      labelJp: string
      gameIds: string[]
      seed: number
      order: number
```

### 5.6 自動パイプライン（data_pipeline_service.dart）

アプリ起動時にバックグラウンドで実行：

```dart
class DataPipelineService {
  /// ゲームデータをFirestoreから取得。なければBGGから取得してFirestoreに保存
  Future<List<Game>> getOrFetchGames(List<Game> seedGames) async {
    // 1. Firestoreから取得試行
    // 2. キャッシュ有効期限チェック（7日）
    // 3. 期限切れ or 未取得 → BGG APIで再取得
    // 4. Firestoreに保存
    // 5. 楽天URLはdetail画面開時にオンデマンド取得
  }
  
  /// 単一ゲームの楽天アフィリエイトURLを取得・保存
  Future<String?> getOrFetchAffiliateUrl(Game game) async { ... }
}
```

---

## 6. UI実装仕様

### 6.1 現在実装済み（変更禁止の核心部分）

以下は**デザイン感として承認済み**。壊さないこと：

- `_StoreAmbience`: blur σ=55の背景 + 暗いグラデーションオーバーレイ
- `_CeilingLights` / `_PendantPainter`: 電球＋光錐（評価済み）
- 棚の色味: `_cBoardTop = 0xFFD09248`, `_cBoardMid = 0xFFB87830`など
- 後壁グラデーション: 5段暖色グラデーション（ライトが当たっている感）
- `InteractiveViewer`: minScale=0.38, maxScale=2.8, boundaryMargin=0

### 6.2 タップアニメーション（box_widgets.dart に追加）

**必須実装**。「手に取る」感覚を再現：

```
Phase 1 — 押し込み (80ms):
  scale: 1.0 → 0.96
  shadow: 通常 → 弱く

Phase 2 — 飛び出し (140ms):
  scale: 0.96 → 1.08
  shadow: 弱い → 強く (blurRadius 24, opacity 0.45, offset y=12)
  translateY: 0 → -8px (少し浮き上がる)

Phase 3 — Hero遷移 (220ms):
  そのままGameDetailScreenへHero遷移
  heroTag: 'game_box_${game.id}'
```

実装方法:
- `GestureDetector` + `AnimatedScale` + `AnimatedContainer`
- または `flutter_animate` パッケージを使用
- `StatefulWidget`に変更してアニメーション状態を管理

**禁止**:
- バネが強いアニメーション
- 大げさな3D回転
- 500ms以上の長いアニメーション

### 6.3 GameDetailScreen（game_detail_screen.dart）

**Hero遷移の受け口**:
```dart
// heroTag: 'game_box_${game.id}' で受け取る
Hero(
  tag: 'game_box_${game.id}',
  child: GameBoxLargeWidget(game: game),
)
```

**レイアウト（上から順）**:

```
1. ヘッダー画像エリア (height: 340px)
   - パッケージ正面画像（大）
   - 左右スワイプで正面/側面/背面切り替え（画像が複数ある場合）
   - 左上: 戻るボタン（glass morphism）
   - 右上: 保存ボタン

2. ゲーム基本情報
   - タイトル（大、白）
   - プレイ人数 / プレイ時間 / BGGレーティング（アイコン付き横並び）
   - カテゴリタグ（横スクロール）

3. 説明文
   - 折りたたみ（3行まで表示、「もっと見る」タップで展開）

4. 購入ボタン（最重要）
   - 楽天ボタン: 赤背景、「楽天で見る」
   - Yahoo!ボタン: あれば表示
   - ボタンをタップ → url_launcher で外部ブラウザ起動
   - アフィリエイトURLが取得できていない場合は「検索中...」表示

5. 詳細データ
   - デザイナー、メカニクス等（折りたたみ）
```

**背景**: `_StoreAmbience`と同じblur背景（統一感）

### 6.4 POPカードの配置ロジック（現在実装済み、仕様として明記）

```dart
// shelf_engine.dart の generatePops()
// 0枚: 15%, 1枚: 55%, 2枚: 30%
// X位置: 壁幅の8〜92%のランダム位置
// 2枚の場合120px以上離す
// タイプ: stand(縦長), plate(横長), lean(傾き大)
```

---

## 7. Firebase セットアップ手順（ユーザーへの案内）

Claude Codeは以下のステップをユーザーに案内しつつ、コード側の準備を並行して進めること：

### Step 1: Firebase Console での作業（ユーザーが手動で行う）
```
1. https://console.firebase.google.com にアクセス
2. 「プロジェクトを追加」→ プロジェクト名: pocketplay
3. Google Analytics: 有効化（推奨）
4. 「iOSアプリを追加」
   - バンドルID: com.yourname.pocketplay
   - GoogleService-Info.plist をダウンロード → ios/Runner/ に配置
5. 「Androidアプリを追加」（必要な場合）
   - パッケージ名: com.yourname.pocketplay
   - google-services.json をダウンロード → android/app/ に配置
6. Firestore Database → 「データベースの作成」→ 本番モードで開始
7. Firestore ルール設定（下記参照）
```

### Step 2: Firestoreセキュリティルール
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // ゲームデータは読み取り自由
    match /games/{gameId} {
      allow read: if true;
      allow write: if false; // Functions経由のみ書き込み可
    }
    match /shelves/{shelfId} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

### Step 3: FlutterFireの設定
```bash
# Claude Codeが実行するコマンド
dart pub global activate flutterfire_cli
flutterfire configure --project=pocketplay-xxxxx
# → lib/core/firebase_options.dart が自動生成される
```

### Step 4: main.dartの更新
```dart
// Firebase初期化をClaude Codeが実装
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: PocketPlayApp()));
}
```

---

## 8. API キー管理

**絶対にAPIキーをコードにハードコードしない**。

### 開発時: lib/core/constants.dart（.gitignoreに追加）
```dart
// lib/core/constants.dart
// このファイルは .gitignore に追加すること
class AppConstants {
  // 楽天API
  static const String rakutenAppId = 'YOUR_RAKUTEN_APP_ID';
  static const String rakutenAffiliateId = 'YOUR_RAKUTEN_AFFILIATE_ID';
  
  // Yahoo! ショッピングAPI
  static const String yahooAppId = 'YOUR_YAHOO_APP_ID';
  
  // BGG (認証不要だが念のため)
  static const String bggUserAgent = 'PocketPlay/1.0 (board game discovery app)';
}
```

### 本番時: Firebase Remote Config または Functions の環境変数
```
Firebase Console → Remote Config に以下を設定:
  rakuten_app_id: xxxxx
  rakuten_affiliate_id: xxxxx
  yahoo_app_id: xxxxx
```

### .gitignore に追加すること
```
lib/core/constants.dart
lib/core/firebase_options.dart
ios/Runner/GoogleService-Info.plist
android/app/google-services.json
```

---

## 9. 実装フェーズとタスク

### Phase 1: タップアニメーション + Hero遷移（最優先）
優先度: ★★★★★

```
タスク:
[ ] box_widgets.dart: FaceBoxWidget, SpineBoxWidgetにタップアニメーション追加
    - 押し込み → 飛び出し → Hero遷移の3フェーズ
    - heroTag: 'game_box_${game.id}'
[ ] GameDetailScreen の骨格作成（仮データで動く状態に）
[ ] Hero遷移の受け口実装
[ ] 戻るアニメーション（逆Hero）
```

### Phase 2: データモデル拡張 + BGG詳細取得
優先度: ★★★★☆

```
タスク:
[ ] game.dart: Gameモデルに拡張フィールド追加
[ ] game_detail.dart: GameDetailモデル作成
[ ] bgg_repository.dart: fetchDetail()メソッド追加
    - プレイ人数, 時間, レーティング, カテゴリ, 説明文を取得
[ ] game_provider.dart: gameDetailProvider追加
[ ] GameDetailScreenにBGGデータを表示
```

### Phase 3: Firebase Firestore 統合
優先度: ★★★★☆

```
事前条件: ユーザーがFirebase Consoleでプロジェクト作成済み
タスク:
[ ] pubspec.yaml: firebase_core, cloud_firestore追加
[ ] lib/core/firebase_options.dart: flutterfire configureで生成
[ ] main.dart: Firebase.initializeApp()追加
[ ] game_data_repository.dart: Firestore CRUD実装
[ ] data_pipeline_service.dart: BGG→Firestoreパイプライン実装
[ ] game_provider.dart: Firestoreプロバイダに切り替え
```

### Phase 4: 楽天アフィリエイト統合
優先度: ★★★★☆

```
事前条件: AppConstants.dartにAPIキー設定済み
タスク:
[ ] rakuten_repository.dart: 楽天商品検索API実装
[ ] affiliate_service.dart: URL生成ロジック
[ ] GameDetailScreen: 購入ボタン実装
    - url_launcher でブラウザ起動
    - ローディング状態管理
    - マッチしない場合の非表示ロジック
[ ] Firestoreへの楽天URL保存
```

### Phase 5: Yahoo! ショッピング統合
優先度: ★★★☆☆

```
タスク:
[ ] yahoo_repository.dart: Yahoo!商品検索API実装
[ ] GameDetailScreen: Yahoo!ボタン追加
[ ] 複数購入先の表示ロジック
```

### Phase 6: パフォーマンス最適化
優先度: ★★★☆☆

```
タスク:
[ ] ShelfRow全体をRepaintBoundaryで包む
[ ] 次の1段分のみprecacheImage
[ ] Placement計算をcompute()でisolateに移行
[ ] 画像キャッシュ戦略の改善
```

### Phase 7: パララックス（オプション）
優先度: ★★☆☆☆

```
タスク:
[ ] ScrollController → scrollOffsetProvider
[ ] 背景速度0.2, 棚板0.6, 箱1.0の多層スクロール
```

---

## 10. 実装ルール・制約

### 絶対禁止
- GridView / ListView での棚表現
- 角丸カードUIへの変更
- 太い枠線の追加
- 現在の棚の色味・電球照明の変更
- APIキーのハードコード
- 毎buildでShelfLayoutEngine.generateRow()を呼ぶ（事前計算必須）

### コーディング規則
- `StatelessWidget`優先。アニメーションのみ`StatefulWidget`可
- Riverpodのproviderは`lib/data/repositories/`以下に集約
- UIロジックをwidgetに書かない（provider経由）
- エラー時は必ずローカルデータ(kSeedGames)にフォールバック
- 日本語対応: タイトル・説明文は日本語を優先表示

### エラーハンドリング
```dart
// 全てのAPI呼び出しは try-catch + フォールバック
try {
  final data = await someApi.fetch();
  return data;
} catch (e) {
  dev.log('Error: $e', name: 'RepositoryName');
  return fallbackData; // kSeedGamesや空リストなど
}
```

### 画像取得の優先順位
```
1. Firestore保存済みURL
2. BGG imageUrl (networkから)
3. localAsset (assets/boxes/)
4. _SpinePlaceholder (spineColorグラデーション)
```

---

## 11. 現在のファイル詳細メモ

### shelf_engine.dart の重要定数
```dart
const double kRowHeight = 230.0;  // 棚の高さ
const double kBoardH    = 18.0;   // 棚板の厚み
const double kPillarW   = 26.0;   // 柱の幅
```

### home_screen.dart の重要パラメータ
```dart
final wallW   = screenW * 10.0;  // 棚幅 = 画面幅の10倍
final marginW = screenW * 1.5;   // 左右マージン（変更禁止）
// InteractiveViewer: minScale=0.38, maxScale=2.8, boundaryMargin=0
```

### kShelfRows (game_provider.dart)
```
'FEATURED'    seed:101  // 12ゲーム
'STRATEGY'    seed:202  // 12ゲーム
'2 PLAYERS'   seed:303  // 12ゲーム
'PARTY GAMES' seed:404  // 12ゲーム
'SMALL BOX'   seed:505  // 12ゲーム
'NEW & HOT'   seed:606  // 12ゲーム
```

---

## 12. よくある判断基準

**Q: 新しいUIを追加する際、既存の棚UIを変更していいか？**
→ 棚UIへの影響がゼロの場合のみ追加可。既存コンポーネントは変更禁止。

**Q: BGGのAPIが落ちていたらどうするか？**
→ `kSeedGames`のlocalAssetで表示。エラーは隠さず`dev.log`に記録。

**Q: 楽天で商品が見つからなかったら？**
→ 購入ボタンを非表示（エラー表示しない）。ユーザー体験を損なわないこと。

**Q: 画像が縦横比がおかしい場合は？**
→ `BoxFit.cover`で中央クロップ。アスペクト比は`game.faceAspect`を参照。

**Q: Firebaseがまだ設定されていない段階でFirestoreを使おうとしたら？**
→ `try-catch`でFirebaseExceptionを捕捉し、BGG/ローカルデータにフォールバック。

**Q: アニメーションが重い場合は？**
→ `RepaintBoundary`を追加。それでも重い場合はアニメーションを簡略化。60fpsを維持すること。

---

## 13. ユーザーへの案内が必要なタスク

以下はClaude Codeが自動化できず、ユーザーの手作業が必要：

1. **Firebase プロジェクト作成** → Phase 3開始前に必要
   - 案内: `firebase_setup_guide.md`を生成してユーザーに渡す

2. **GoogleService-Info.plist 配置** → `ios/Runner/`に手動配置

3. **楽天API/Yahoo! APIキー取得・設定** → Phase 4開始前に必要
   - 楽天デベロッパーアカウント: https://webservice.rakuten.co.jp/
   - Yahoo!デベロッパーアカウント: https://developer.yahoo.co.jp/
   - 取得後、`lib/core/constants.dart`に設定

4. **App Store / Google Play 登録** → リリース時

---

## 14. 成功の定義

以下を全て満たした時点でMVP完成とみなす：

- [ ] 棚をスクロールして「実店舗を歩いている感覚」がある
- [ ] ゲームをタップすると箱が手前に飛び出してくる
- [ ] 詳細画面でパッケージ画像が美しく表示される
- [ ] 「楽天で見る」ボタンから実際の商品ページに飛べる
- [ ] アフィリエイトタグが正しくURLに含まれている
- [ ] 全ゲームにBGGから取得した実画像が表示されている
- [ ] Firestoreにデータが自動保存される
- [ ] オフライン時もローカルデータで棚が表示される

---

## 15. パッケージ画像の取得戦略（重要）

### 15.1 棚に表示される画像タイプと用途

ボードゲームの箱には複数の面があり、それぞれ異なるシーンで使用する：

| 画像タイプ | 用途 | 優先度 |
|-----------|------|--------|
| **正面(front)** | `face`表示、詳細画面メイン、`stack`の上面 | ★★★★★ |
| **側面・縦(spine vertical)** | `spine`表示（背表紙） | ★★★★★ |
| **側面・横(spine horizontal)** | `stack`の側面、将来の棚奥行き表現 | ★★★☆☆ |
| **背面(back)** | 詳細画面のスワイプ2枚目 | ★★☆☆☆ |

### 15.2 現在の実装

`spine`表示時: 正面画像を細くクロップして擬似的に背表紙を表現（`box_widgets.dart`の`SpineBoxWidget`）
`face`表示時: 正面画像をそのまま表示
`stack`表示時: 正面画像を横向きに表示

→ **全て正面画像1枚で賄っている**。本来あるべき側面画像は未取得。

### 15.3 画像取得の優先順位と戦略

```
Step 1: BGG XMLAPIから正面画像取得（既存実装）
  → <image> タグ: 高解像度正面画像
  → <thumbnail> タグ: 低解像度版（フォールバック）

Step 2: BGG Imagesページからの追加画像（拡張実装）
  BGGには複数画像が投稿されている場合がある
  GET https://boardgamegeek.com/xmlapi2/thing?id={bggId}&type=boardgame
  → <image> は1枚のみ返る（APIの制限）
  
  BGG非公式画像一覧（将来対応）:
  https://boardgamegeek.com/boardgame/{bggId}/images
  ※スクレイピングはToS違反リスクあり → 使用しない

Step 3: Open Library / IGDB 相当のボードゲーム画像DB（調査中）
  → 実装時にweb_searchで最新APIを確認すること

Step 4: 楽天APIから商品画像を取得
  items[0].mediumImageUrls → 正面画像（楽天撮影）
  items[0].smallImageUrls  → サムネイル
  ※楽天画像は正面のみのことが多い

Step 5: Google Custom Search API（最終手段）
  検索クエリ: "{タイトル} ボードゲーム box spine"
  ※有料・制限あり。MVPでは使用しない
```

### 15.4 Gameモデルへの画像フィールド追加

```dart
class Game {
  // 既存
  final String? imageUrl;        // BGG正面画像
  final String? localAsset;      // ローカルアセット（現在10タイトル）
  
  // 追加すること
  final String? thumbnailUrl;    // BGGサムネイル（低解像度、高速表示用）
  final String? spineImageUrl;   // 側面縦画像（取得できた場合のみ）
  final List<String> extraImages; // 追加画像（詳細画面スワイプ用）
  // extraImages[0] = 正面, [1] = 背面, [2] = 側面 etc.
}
```

### 15.5 spine表示の改善方針

現状: 正面画像を `BoxFit.cover` + 左右クロップで擬似背表紙
改善: 正面画像から自動的にedgeを抽出する処理

```dart
// SpineBoxWidget での表示ロジック（優先順位）
1. game.spineImageUrl が存在する → そのまま表示
2. game.imageUrl が存在する → 左端15%をクロップして表示（擬似spine）
3. game.localAsset が存在する → 同上
4. 全てnull → spineColorグラデーション + タイトル縦書き
```

### 15.6 横積み(stack)の画像表示

`stack`表示時は箱の上面（正面画像）が見える：
```dart
// StackBoxWidget
// 一番上の箱: 正面画像を横向き(rotate 90度 or fit.cover)
// 下の箱: 側面色またはスパインカラー
```

---

## 16. Amazon アフィリエイト対応

### 16.1 方針: 検索URLにアソシエイトタグを付与（確定）

**ユーザー確認済み**: API不使用、検索URL方式でOK。
APIキー不要のため**Phase 1から即日実装可能**。

採用方式:

```
https://www.amazon.co.jp/s?k={検索キーワード}&tag={ASSOCIATE_TAG}&linkCode=ur2
```

### 16.2 AmazonアフィリエイトURL生成ロジック

```dart
class AffiliateService {
  static const String amazonAssociateTag = 'YOUR_ASSOCIATE_TAG'; // constants.dartに移動
  
  /// Amazon検索URLを生成（API不要）
  static String buildAmazonSearchUrl(Game game) {
    final keyword = Uri.encodeComponent('${game.title} ボードゲーム');
    return 'https://www.amazon.co.jp/s?k=$keyword&tag=$amazonAssociateTag&linkCode=ur2';
  }
  
  /// タイトルが日本語でない場合は英語タイトルも検索
  static String buildAmazonSearchUrlEn(String titleEn) {
    final keyword = Uri.encodeComponent('$titleEn board game');
    return 'https://www.amazon.co.jp/s?k=$keyword&tag=$amazonAssociateTag&linkCode=ur2';
  }
}
```

### 16.3 将来: ASIN取得による商品直リンク（Phase 5以降）

楽天APIで取得した商品名からASINを推定、またはPA-API審査通過後に実装。
MVP段階では検索URLで十分。

### 16.4 constants.dartへの追加

```dart
class AppConstants {
  // 既存
  static const String rakutenAppId = 'YOUR_RAKUTEN_APP_ID';
  static const String rakutenAffiliateId = 'YOUR_RAKUTEN_AFFILIATE_ID';
  static const String yahooAppId = 'YOUR_YAHOO_APP_ID';
  
  // 追加
  static const String amazonAssociateTag = 'YOUR_AMAZON_ASSOCIATE_TAG';
  // 例: 'pocketplay-22' (アソシエイトID)
}
```

### 16.5 GameDetailScreenの購入ボタン構成（更新）

```
購入ボタンエリア（横並び or 縦並び）:
  [楽天で見る]   ← 赤ボタン、楽天API取得URL or フォールバック検索URL
  [Amazonで見る] ← オレンジボタン、常に検索URL（APIなしで即実装可能）
  [Yahoo!で見る] ← 紫ボタン（Phase 5以降）

表示優先度:
  楽天: 商品直リンクあれば直リンク、なければ検索URL
  Amazon: 常に検索URL（確実に表示できる）
  
→ AmazonボタンはAPIキー不要で即日実装可能。Phase 1に組み込む。
```

---

## 17. Firebase セットアップの自動化範囲

### Claude Codeが自動実行できること（PCでCLIが動く場合）

```bash
# Firebase CLIのインストール確認
npm list -g firebase-tools || npm install -g firebase-tools

# ログイン（ブラウザが開く）
firebase login

# Flutterプロジェクトの設定
dart pub global activate flutterfire_cli
flutterfire configure --project={PROJECT_ID}
# → lib/core/firebase_options.dart を自動生成

# Firestoreルールのデプロイ
firebase deploy --only firestore:rules

# 初期データの投入
# → dart run scripts/seed_firestore.dart
```

### Claude Codeが自動化できないこと（手動必須）

```
1. Firebase Consoleでのプロジェクト作成
   → https://console.firebase.google.com
   → 所要時間: 約5分

2. iOSアプリ登録 + GoogleService-Info.plist ダウンロード
   → Console > プロジェクト設定 > アプリを追加 > iOS
   → ダウンロードした.plistを ios/Runner/ に配置

3. Firestoreの有効化
   → Console > Firestore Database > データベースの作成

4. ブラウザでのfirebase login認証
   → CLIが自動でブラウザを開くのでGoogleアカウントでログイン
```

### Claude Codeの対応方針（確定）

**ユーザー確認済み**: Claude Codeが動くPC上でCLI実行可能。

Firebase関連の作業が発生したら：
1. `firebase --version` でCLI確認
2. 未インストールなら `npm install -g firebase-tools` を自動実行
3. `firebase login` → ブラウザ認証（ユーザーが行う唯一の手作業）
4. `flutterfire configure` で `firebase_options.dart` を自動生成
5. Firestoreルール・初期データは自動デプロイ
6. `firebase_options.dart` が存在しない間はtry-catchでローカルデータ継続動作

