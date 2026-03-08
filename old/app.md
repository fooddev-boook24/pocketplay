# PocketPlay

## ボードゲーム Discovery アプリ

### Codex開発スターターキット完全仕様書（日本語版）

Version: 3.0 Target: Codex自動開発 Platform: iOS / Android Framework:
Flutter Architecture: Riverpod + Firebase

------------------------------------------------------------------------

# 1. プロダクト概要

PocketPlayは **「検索ではなく棚からゲームと出会う」**
ことを目的としたボードゲームDiscoveryアプリである。

ユーザーは実際のゲームショップのような
**リアルな棚UI**をスクロールしながらゲームを発見する。

従来のEC

検索 → 商品一覧 → 比較 → 購入

PocketPlay

棚を見る → 気になる箱 → 手に取る → 詳細 → 購入

つまり

**ショッピングではなく探索体験を提供する。**

------------------------------------------------------------------------

# 2. ターゲットユーザー

Primary

・ボードゲーム初心者\
・面白いゲームを探したい人\
・ジャケ買いをする人

Secondary

・ボードゲームファン\
・コレクター\
・ギフト探しユーザー

------------------------------------------------------------------------

# 3. プラットフォーム

Flutter

対応

iOS\
Android

------------------------------------------------------------------------

# 4. 技術スタック

Frontend

Flutter\
Riverpod\
flutter_hooks\
cached_network_image

Backend

Firebase

Firestore\
Cloud Functions\
Cloud Scheduler\
Firebase Analytics\
Remote Config

------------------------------------------------------------------------

# 5. システムアーキテクチャ

Data Source

↓

Collector

↓

Normalizer

↓

Firestore

↓

Flutter App

------------------------------------------------------------------------

# 6. データソース

BoardGameGeek API

取得情報

title\
year\
rating\
players\
playtime\
description\
image

Amazon Product Advertising API

取得

商品画像\
価格\
商品URL

楽天商品検索API

取得

商品画像\
価格\
商品URL

------------------------------------------------------------------------

# 7. 自動データ追加システム

Cloud Scheduler（1日1回）

↓

Cloud Function

↓

BoardGameGeek 人気ランキング取得

↓

Firestore存在確認

↓

未登録ゲーム追加

↓

Amazon / 楽天リンク付与

↓

Firestore保存

------------------------------------------------------------------------

# 8. Firestore データ構造

collection: games

fields

id\
title\
year\
image\
thumbnail\
description\
players_min\
players_max\
play_time\
rating\
complexity\
tags\
amazon_url\
rakuten_url\
created_at\
popularity_score

------------------------------------------------------------------------

# 9. shelf collection

id\
name\
type\
tag_filter\
created_at

例

recommended\
party\
strategy\
two_players\
family

------------------------------------------------------------------------

# 10. Flutter フォルダ構造

lib/

core/ constants theme utils

features/

home/ shelf/ game_detail/ recommendation/

models/ game_model.dart placement_model.dart

services/ firestore_service.dart recommendation_service.dart

providers/ game_provider.dart shelf_provider.dart

widgets/ game_box.dart shelf_row.dart shelf_background.dart

screens/ home_screen.dart shelf_screen.dart game_detail_screen.dart

------------------------------------------------------------------------

# 11. UI設計

リアルな棚を再現

要素

木製棚\
影\
パッケージ高画質\
ランダム配置\
パララックス

------------------------------------------------------------------------

# 12. 画面構成

HomeScreen

ShelfScreen

GameDetailScreen

------------------------------------------------------------------------

# 13. HomeScreen

棚一覧

今日のおすすめ

パーティーゲーム

2人用ゲーム

戦略ゲーム

------------------------------------------------------------------------

# 14. 棚UI設計

高さ

260px

構造

Stack

background\
shelf\
boxes\
shadow

------------------------------------------------------------------------

# 15. Box表示タイプ

3種類

upright\
face_out\
stacked

割合

upright 70%

face_out 20%

stacked 10%

------------------------------------------------------------------------

# 16. Placementモデル

class Placement

gameId

pose

x

y

width

height

rotation

zIndex

------------------------------------------------------------------------

# 17. ランダム配置

seed = shelfId + shelfIndex

Random(seed)

------------------------------------------------------------------------

# 18. Flutter棚レンダリング

CustomScrollView

SliverList

ShelfRow

------------------------------------------------------------------------

# 19. ShelfRow構造

Stack

ShelfBackground

ShelfBoard

GameBoxes

------------------------------------------------------------------------

# 20. 3Dボックス表現

Transform

Matrix4

setEntry(3,2,0.001)

rotateY

------------------------------------------------------------------------

# 21. パララックス

背景 0.2

棚 0.6

箱 1.0

------------------------------------------------------------------------

# 22. GameDetailScreen

表示

箱画像

タイトル

プレイ人数

プレイ時間

評価

説明

------------------------------------------------------------------------

# 23. 購入リンク

Amazon

楽天

アフィリエイトリンク使用

------------------------------------------------------------------------

# 24. スワイプ機能

左

興味なし

右

気になる

------------------------------------------------------------------------

# 25. レコメンドアルゴリズム

score =

rating_weight

-   

tag_similarity

-   

popularity

-   

recency

------------------------------------------------------------------------

# 26. user_preferences

collection

userId

liked_tags

disliked_tags

saved_games

------------------------------------------------------------------------

# 27. パフォーマンス最適化

RepaintBoundary

cached_network_image

precacheImage

lazy loading

------------------------------------------------------------------------

# 28. 画像仕様

最低

600px

推奨

1000px

------------------------------------------------------------------------

# 29. Analytics

open_app

scroll_shelf

tap_game

open_amazon

open_rakuten

like_game

------------------------------------------------------------------------

# 30. 収益化

Amazon Affiliate

Rakuten Affiliate

AdMob

------------------------------------------------------------------------

# 31. 初期ゲームデータ

最低

100

推奨

300

------------------------------------------------------------------------

# 32. 初期棚

今日のおすすめ

パーティーゲーム

2人用ゲーム

戦略ゲーム

------------------------------------------------------------------------

# 33. 初期JSONデータ例

{ "id": "catan", "title": "Catan", "year": 1995, "players_min": 3,
"players_max": 4, "play_time": 90, "rating": 7.3, "tags":
\["strategy","family"\] }

------------------------------------------------------------------------

# 34. Cloud Function 擬似コード

fetchTopGames()

for game in results

if not exists

saveToFirestore()

------------------------------------------------------------------------

# 35. MVPロードマップ

Phase1

棚UI

ゲーム一覧

詳細画面

Amazonリンク

Phase2

レコメンド

ユーザー履歴

Phase3

レビュー

SNS共有

------------------------------------------------------------------------

# 36. KPI

DAU

棚スクロール深度

ゲームクリック率

購入遷移率

------------------------------------------------------------------------

# 37. アプリ名

PocketPlay

意味

ポケットの中のゲーム棚

------------------------------------------------------------------------

# 38. Flutterプロジェクト

project name

playpocket

organization

app.boook24.playpocket

------------------------------------------------------------------------

# 39. 将来拡張

カードゲーム

TRPG

ミニチュアゲーム

------------------------------------------------------------------------

# END
