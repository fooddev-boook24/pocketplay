import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/game.dart';
import '../models/game_detail.dart';
import 'game_data_repository.dart';
import '../../core/constants.dart';

class BggRepository {
  BggRepository._();
  static final instance = BggRepository._();

  final Map<int, String> _cache = {};
  final Map<int, GameDetail> _detailCache = {};

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
    final uri = Uri.parse('https://boardgamegeek.com/xmlapi2/thing?id=$ids&type=boardgame');
    dev.log('Fetching: $uri', name: 'BggRepository');
    try {
      var response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
      dev.log('Status: ${response.statusCode}', name: 'BggRepository');
      if (response.statusCode == 202) {
        await Future.delayed(const Duration(seconds: 4));
        response = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
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
        String? url;
        for (final tag in ['image', 'thumbnail']) {
          final el = item.findElements(tag).firstOrNull;
          final text = el?.innerText.trim() ?? '';
          if (text.isNotEmpty) { url = text; break; }
        }
        if (url == null) continue;
        if (url.startsWith('//')) url = 'https:$url';
        if (!url.startsWith('http')) continue;
        _cache[bggId] = url;
        dev.log('Cached $bggId -> $url', name: 'BggRepository');
      }
    } catch (e) {
      dev.log('XML parse error: $e', name: 'BggRepository');
    }
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

      if (response.statusCode == 202) {
        await Future.delayed(const Duration(seconds: 4));
        response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 20));
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
