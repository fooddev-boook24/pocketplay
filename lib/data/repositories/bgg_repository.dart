import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';
import '../models/game.dart';

class BggRepository {
  BggRepository._();
  static final instance = BggRepository._();

  final Map<int, String> _cache = {};

  // BGG requires a proper User-Agent otherwise returns 401
  static const Map<String, String> _headers = {
    'User-Agent': 'PocketPlay/1.0 (board game discovery app)',
    'Accept': 'application/xml, text/xml',
  };

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
}
