import 'dart:developer' as dev;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/game.dart';
import '../models/game_detail.dart';
import 'game_data_repository.dart';
import '../../core/constants.dart';

class BggRepository {
  BggRepository._();
  static final instance = BggRepository._();

  final Map<int, String> _cache = {};              // bggId → imageUrl
  final Map<int, String> _nameCache = {};          // bggId → primary name
  final Map<int, List<String>> _categoryCache = {}; // bggId → categories
  final Map<int, double?> _ratingCache = {};        // bggId → bggRating
  final Map<int, String?> _descCache = {};          // bggId → description
  final Map<int, int?> _minPlayersCache = {};
  final Map<int, int?> _maxPlayersCache = {};
  final Map<int, int?> _playTimeCache = {};
  final Map<int, GameDetail> _detailCache = {};

  /// BGG画像キャッシュ（bggId → imageUrl）の読み取り専用ビュー
  Map<int, String> get imageCache => Map.unmodifiable(_cache);

  static Map<String, String> get _headers {
    final token = AppConstants.bggAppToken;
    return {
      'User-Agent': AppConstants.bggUserAgent,
      'Accept': 'application/xml,text/xml,*/*',
      if (!token.startsWith('YOUR_')) 'Authorization': 'Bearer $token',
    };
  }

  // ─── 既存: バッチ画像取得 ────────────────────────────────────────────────────
  Future<Map<int, String>> fetchImages(List<Game> games) async {
    final toFetch = games.where((g) => !_cache.containsKey(g.bggId)).toList();
    if (toFetch.isEmpty) return _hits(games);
    for (var i = 0; i < toFetch.length; i += 20) {
      final ids = toFetch.skip(i).take(20).map((g) => g.bggId).join(',');
      await _fetchBatch(ids);
      if (i + 20 < toFetch.length) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    dev.log('Cache size: ${_cache.length}', name: 'BggRepository');
    return _hits(games);
  }

  Map<int, String> _hits(List<Game> games) =>
      {for (final g in games) if (_cache.containsKey(g.bggId)) g.bggId: _cache[g.bggId]!};

  Future<void> _fetchBatch(String ids) async {
    final uri = Uri.parse('https://boardgamegeek.com/xmlapi2/thing?id=$ids&type=boardgame&stats=1');
    dev.log('Fetching: $uri', name: 'BggRepository');
    try {
      var response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      dev.log('Status: ${response.statusCode}', name: 'BggRepository');
      // 202: BGGがキューイング中 → 最大3回リトライ
      int retries = 0;
      while (response.statusCode == 202 && retries < 3) {
        await Future.delayed(const Duration(seconds: 4));
        response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
        retries++;
      }
      if (response.statusCode != 200) {
        dev.log('Failed: ${response.statusCode}', name: 'BggRepository');
        return;
      }
      _parseXml(response.body);
    } catch (e) {
      dev.log('Error: $e', name: 'BggRepository');
    }
  }

  void _parseXml(String body) {
    try {
      final doc = XmlDocument.parse(body);
      for (final item in doc.findAllElements('item')) {
        final bggId = int.tryParse(item.getAttribute('id') ?? '');
        if (bggId == null) continue;

        // タイトル（primary name）
        for (final name in item.findElements('name')) {
          if (name.getAttribute('type') == 'primary') {
            final v = name.getAttribute('value') ?? '';
            if (v.isNotEmpty) _nameCache[bggId] = v;
            break;
          }
        }

        // 画像
        String? url;
        for (final tag in ['image', 'thumbnail']) {
          final el = item.findElements(tag).firstOrNull;
          final text = el?.innerText.trim() ?? '';
          if (text.isNotEmpty) { url = text; break; }
        }
        if (url != null) {
          if (url.startsWith('//')) url = 'https:$url';
          if (url.startsWith('http')) _cache[bggId] = url;
        }

        // プレイ人数・時間
        _minPlayersCache[bggId] = int.tryParse(
            item.findElements('minplayers').firstOrNull?.getAttribute('value') ?? '');
        _maxPlayersCache[bggId] = int.tryParse(
            item.findElements('maxplayers').firstOrNull?.getAttribute('value') ?? '');
        final maxTime = int.tryParse(
            item.findElements('maxplaytime').firstOrNull?.getAttribute('value') ?? '');
        final minTime = int.tryParse(
            item.findElements('minplaytime').firstOrNull?.getAttribute('value') ?? '');
        _playTimeCache[bggId] = maxTime ?? minTime;

        // レーティング（stats=1 があれば取得される）
        final stats = item.findElements('statistics').firstOrNull;
        if (stats != null) {
          final ratings = stats.findElements('ratings').firstOrNull;
          if (ratings != null) {
            _ratingCache[bggId] = double.tryParse(
                ratings.findElements('average').firstOrNull?.getAttribute('value') ?? '');
          }
        }

        // カテゴリ
        final cats = <String>[];
        for (final link in item.findElements('link')) {
          if (link.getAttribute('type') == 'boardgamecategory') {
            final v = link.getAttribute('value') ?? '';
            if (v.isNotEmpty) cats.add(v);
          }
        }
        if (cats.isNotEmpty) _categoryCache[bggId] = cats;

        // 説明文
        final rawDesc = item.findElements('description').firstOrNull?.innerText.trim() ?? '';
        if (rawDesc.isNotEmpty) _descCache[bggId] = _cleanDescription(rawDesc);
      }
    } catch (e) {
      dev.log('XML parse error: $e', name: 'BggRepository');
    }
  }

  // ─── 初期ライブラリ取得（Top ~300ゲームのスタブ）─────────────────────────
  /// bggIdリストを受け取りGame stubs（タイトル+画像）を返す
  Future<List<Game>> fetchGameStubs(List<int> bggIds) async {
    final result = <Game>[];
    for (var i = 0; i < bggIds.length; i += 20) {
      final batch = bggIds.skip(i).take(20).toList();
      final ids = batch.join(',');
      await _fetchBatch(ids);
      for (final bggId in batch) {
        final imageUrl = _cache[bggId];
        final title = _nameCache[bggId];
        if (title == null) continue;
        result.add(Game(
          id: 'bgg_$bggId',
          bggId: bggId,
          title: title,
          spineColor: _deriveColor(bggId),
          spineTextColor: _deriveTextColor(bggId),
          size: BoxSize.medium,
          faceAspect: 0.88,
          imageUrl: imageUrl,
          minPlayers:      _minPlayersCache[bggId],
          maxPlayers:      _maxPlayersCache[bggId],
          playTimeMinutes: _playTimeCache[bggId],
          bggRating:       _ratingCache[bggId],
          categories:      _categoryCache[bggId] ?? const [],
          description:     _descCache[bggId],
        ));
      }
      if (i + 20 < bggIds.length) {
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }
    dev.log('fetchGameStubs: ${result.length} games', name: 'BggRepository');
    return result;
  }

  /// bggId から背表紙カラーをハッシュ的に決定（暖色〜寒色の実店舗らしいパレット）
  Color _deriveColor(int bggId) {
    const palette = [
      0xFF2D4A6A, 0xFF4A2D2D, 0xFF2D4A2D, 0xFF4A3D2D,
      0xFF2D3D4A, 0xFF4A2D40, 0xFF3D4A2D, 0xFF2D4A3D,
      0xFF4A4020, 0xFF20304A, 0xFF3A2040, 0xFF1A3A28,
      0xFF5A3A1A, 0xFF1A2A5A, 0xFF3A1A3A, 0xFF2A3A1A,
    ];
    return Color(palette[bggId % palette.length]);
  }

  Color _deriveTextColor(int bggId) {
    const textPalette = [
      0xFFFFFFFF, 0xFFFFDDA0, 0xFFAADDFF, 0xFFFFCCBB,
      0xFFCCFFCC, 0xFFFFAACC, 0xFFDDDDAA, 0xFFBBCCFF,
    ];
    return Color(textPalette[(bggId ~/ 7) % textPalette.length]);
  }

  // ─── バックグラウンド画像取得 ─────────────────────────────────────────────────

  /// バックグラウンドでBGG画像取得を試みる（失敗しても問題なし）
  Future<void> tryFetchAndSaveImages(
      List<Game> games, GameDataRepository repo) async {
    final noImage = games
        .where((g) => g.imageUrl == null && g.localAsset == null)
        .toList();
    if (noImage.isEmpty) return;

    dev.log('Trying BGG images for ${noImage.length} games',
        name: 'BggRepository');
    final imageMap = await fetchImages(noImage);

    for (final game in noImage) {
      final url = imageMap[game.bggId];
      if (url != null) {
        await repo.saveGame(game.copyWith(imageUrl: url));
        dev.log('Saved BGG image for ${game.id}', name: 'BggRepository');
      }
    }
  }

  // ─── HOT ゲーム取得 ──────────────────────────────────────────────────────────

  /// BGGのホットリスト（上位50件）を取得してGameリストを返す。
  /// 既知のgame ID・bggId に含まれないゲームのみ返す。
  Future<List<Game>> fetchHotGames({required List<Game> currentGames}) async {
    final uri = Uri.parse('https://boardgamegeek.com/xmlapi2/hot?type=boardgame');
    dev.log('Fetching hot games: $uri', name: 'BggRepository');
    try {
      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      dev.log('Hot status: ${response.statusCode}', name: 'BggRepository');
      if (response.statusCode != 200) return [];
      return _parseHot(response.body, currentGames);
    } catch (e) {
      dev.log('fetchHotGames error: $e', name: 'BggRepository');
      return [];
    }
  }

  List<Game> _parseHot(String body, List<Game> currentGames) {
    final knownIds    = currentGames.map((g) => g.id).toSet();
    final knownBggIds = currentGames.map((g) => g.bggId).toSet();
    try {
      final doc = XmlDocument.parse(body);
      final games = <Game>[];
      for (final item in doc.findAllElements('item')) {
        final bggId = int.tryParse(item.getAttribute('id') ?? '');
        if (bggId == null) continue;

        // IDでも bggId でも重複チェック（kSeedGamesとの衝突防止）
        final id = 'bgg_$bggId';
        if (knownIds.contains(id) || knownBggIds.contains(bggId)) continue;

        final name = item.findElements('name').firstOrNull?.getAttribute('value') ?? '';
        if (name.isEmpty) continue;

        final thumb = item.findElements('thumbnail').firstOrNull?.getAttribute('value') ?? '';
        String? imageUrl = thumb.isNotEmpty ? thumb : null;
        if (imageUrl != null && imageUrl.startsWith('//')) imageUrl = 'https:$imageUrl';

        // スパインカラーはデフォルト（詳細取得後にカテゴリで上書き）
        games.add(Game(
          id: id,
          bggId: bggId,
          title: name,
          spineColor: const Color(0xFF4A3820),
          spineTextColor: Colors.white,
          size: BoxSize.medium,
          faceAspect: 0.88,
          imageUrl: imageUrl,
        ));
      }
      dev.log('Hot games parsed: ${games.length}', name: 'BggRepository');
      return games;
    } catch (e) {
      dev.log('_parseHot error: $e', name: 'BggRepository');
      return [];
    }
  }

  // ─── NEW: 詳細データ取得 (stats=1) ──────────────────────────────────────────
  Future<GameDetail> fetchDetail(Game game) async {
    if (_detailCache.containsKey(game.bggId)) {
      return _detailCache[game.bggId]!;
    }

    final uri = Uri.parse(
      'https://boardgamegeek.com/xmlapi2/thing?id=${game.bggId}&type=boardgame&stats=1',
    );
    dev.log('Fetching detail: $uri', name: 'BggRepository');

    try {
      var response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));

      int retries = 0;
      while (response.statusCode == 202 && retries < 3) {
        await Future.delayed(const Duration(seconds: 4));
        response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 20));
        retries++;
      }

      if (response.statusCode != 200) {
        dev.log('Detail failed: ${response.statusCode}', name: 'BggRepository');
        return GameDetail(game: game);
      }

      final detail = _parseDetail(response.body, game);
      _detailCache[game.bggId] = detail;
      return detail;
    } catch (e) {
      dev.log('Detail error: $e', name: 'BggRepository');
      return GameDetail(game: game);
    }
  }

  GameDetail _parseDetail(String body, Game baseGame) {
    try {
      final doc = XmlDocument.parse(body);
      final item = doc.findAllElements('item').firstOrNull;
      if (item == null) return GameDetail(game: baseGame);

      // 画像URL
      String? imageUrl = _xmlText(item, 'image');
      String? thumbnailUrl = _xmlText(item, 'thumbnail');
      if (imageUrl != null && imageUrl.startsWith('//')) imageUrl = 'https:$imageUrl';
      if (thumbnailUrl != null && thumbnailUrl.startsWith('//')) thumbnailUrl = 'https:$thumbnailUrl';

      // 基本データ
      final minPlayers = _xmlIntAttr(item, 'minplayers');
      final maxPlayers = _xmlIntAttr(item, 'maxplayers');
      final minTime    = _xmlIntAttr(item, 'minplaytime');
      final maxTime    = _xmlIntAttr(item, 'maxplaytime');
      final playTime   = maxTime ?? minTime;
      final yearPub    = _xmlIntAttr(item, 'yearpublished');

      // 説明文
      final rawDesc = _xmlText(item, 'description') ?? '';
      final description = _cleanDescription(rawDesc);

      // 統計
      double? bggRating;
      double? complexity;
      final stats = item.findElements('statistics').firstOrNull;
      if (stats != null) {
        final ratings = stats.findElements('ratings').firstOrNull;
        if (ratings != null) {
          bggRating = double.tryParse(
            ratings.findElements('average').firstOrNull?.getAttribute('value') ?? '',
          );
          complexity = double.tryParse(
            ratings.findElements('averageweight').firstOrNull?.getAttribute('value') ?? '',
          );
        }
      }

      // リンク要素（カテゴリ・メカニクス・デザイナー）
      final categories = <String>[];
      final mechanics  = <String>[];
      final designers  = <String>[];

      for (final link in item.findElements('link')) {
        final type  = link.getAttribute('type') ?? '';
        final value = link.getAttribute('value') ?? '';
        if (value.isEmpty) continue;
        switch (type) {
          case 'boardgamecategory': categories.add(value);
          case 'boardgamemechanic': mechanics.add(value);
          case 'boardgamedesigner': designers.add(value);
        }
      }

      final enrichedGame = baseGame.copyWith(
        imageUrl:       imageUrl ?? baseGame.imageUrl,
        thumbnailUrl:   thumbnailUrl,
        minPlayers:     minPlayers,
        maxPlayers:     maxPlayers,
        playTimeMinutes: playTime,
        bggRating:      bggRating,
        categories:     categories,
        description:    description.isNotEmpty ? description : null,
      );

      return GameDetail(
        game:          enrichedGame,
        mechanics:     mechanics,
        designers:     designers,
        yearPublished: yearPub,
        complexity:    complexity,
      );
    } catch (e) {
      dev.log('Detail parse error: $e', name: 'BggRepository');
      return GameDetail(game: baseGame);
    }
  }

  // ─── ヘルパー ────────────────────────────────────────────────────────────────
  String? _xmlText(XmlElement el, String tag) {
    final text = el.findElements(tag).firstOrNull?.innerText.trim();
    return (text == null || text.isEmpty) ? null : text;
  }

  int? _xmlIntAttr(XmlElement el, String tag) {
    return int.tryParse(
      el.findElements(tag).firstOrNull?.getAttribute('value') ?? '',
    );
  }

  String _cleanDescription(String raw) {
    return raw
        .replaceAll('&#10;', '\n')
        .replaceAll('&#13;', '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&bull;', '•')
        .replaceAll(RegExp(r'&#\d+;'), '')
        .trim();
  }
}
