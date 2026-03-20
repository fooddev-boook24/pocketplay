import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../models/game.dart';
import '../../core/constants.dart';

class YahooResult {
  const YahooResult({this.url, this.imageUrl});
  final String? url;
  final String? imageUrl;
}

/// Yahoo!ショッピング商品検索API
class YahooRepository {
  YahooRepository._();
  static final instance = YahooRepository._();

  static const _endpoint =
      'https://shopping.yahooapis.jp/ShoppingWebService/V3/itemSearch';

  Future<YahooResult?> fetchResult(Game game) async {
    if (!_hasValidKey()) {
      dev.log('Yahoo API key not configured', name: 'YahooRepository');
      return null;
    }
    return _search('${game.title} ボードゲーム');
  }

  Future<YahooResult?> _search(String query) async {
    try {
      final uri = Uri.parse(_endpoint).replace(queryParameters: {
        'appid': AppConstants.yahooAppId,
        'query': query,
        'hits': '5',
        'results': 'hits',
      });
      dev.log('Yahoo request: $query', name: 'YahooRepository');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      dev.log('Yahoo response: ${res.statusCode}', name: 'YahooRepository');
      if (res.statusCode != 200) return null;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final hits = json['hits'] as List?;
      if (hits == null || hits.isEmpty) return null;

      final first = hits.first as Map<String, dynamic>;
      final url = first['url'] as String?;
      final image =
          (first['image'] as Map<String, dynamic>?)?['medium'] as String?;

      dev.log('Yahoo found: url=${url != null} image=${image != null}',
          name: 'YahooRepository');
      return YahooResult(url: url, imageUrl: image);
    } catch (e) {
      dev.log('Yahoo search error: $e', name: 'YahooRepository');
      return null;
    }
  }

  bool _hasValidKey() =>
      !AppConstants.yahooAppId.startsWith('YOUR_') &&
      AppConstants.yahooAppId.isNotEmpty;
}
