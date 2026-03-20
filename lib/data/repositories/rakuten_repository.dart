import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;
import '../models/game.dart';
import '../../core/constants.dart';

class RakutenResult {
  const RakutenResult({this.affiliateUrl, this.imageUrl});
  final String? affiliateUrl;
  final String? imageUrl; // 楽天商品画像URL
}

/// 楽天商品検索API — アフィリエイトURL + 商品画像を同時取得
class RakutenRepository {
  RakutenRepository._();
  static final instance = RakutenRepository._();

  static const _endpoint =
      'https://app.rakuten.co.jp/services/api/IchibaItem/Search/20170706';

  Future<RakutenResult?> fetchResult(Game game) async {
    if (!_hasValidKeys()) {
      dev.log('Rakuten API keys not configured', name: 'RakutenRepository');
      return null;
    }
    return _search('${game.title} ボードゲーム');
  }

  Future<RakutenResult?> _search(String keyword) async {
    try {
      final params = <String, String>{
        'applicationId': AppConstants.rakutenAppId,
        'keyword': keyword,
        'hits': '5',
        'formatVersion': '2',
      };
      if (!AppConstants.rakutenAffiliateId.startsWith('YOUR_') &&
          AppConstants.rakutenAffiliateId.isNotEmpty) {
        params['affiliateId'] = AppConstants.rakutenAffiliateId;
      }

      final uri = Uri.parse(_endpoint).replace(queryParameters: params);
      dev.log('Rakuten request: $keyword', name: 'RakutenRepository');

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      dev.log('Rakuten response: ${res.statusCode}', name: 'RakutenRepository');

      if (res.statusCode != 200) {
        dev.log(
            'Rakuten body: ${res.body.substring(0, res.body.length.clamp(0, 300))}',
            name: 'RakutenRepository');
        return null;
      }

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final items = json['Items'] as List?;
      if (items == null || items.isEmpty) return null;

      final first = items.first as Map<String, dynamic>;

      // アフィリエイトURL（なければitemUrl）
      final affUrl = (first['affiliateUrl'] as String?)?.isNotEmpty == true
          ? first['affiliateUrl'] as String
          : first['itemUrl'] as String?;

      // 商品画像（formatVersion:2 では List<String> で返る）
      String? imageUrl;
      final medium = first['mediumImageUrls'] as List?;
      if (medium != null && medium.isNotEmpty) {
        final v = medium.first;
        imageUrl = v is String ? v : (v as Map<String, dynamic>)['imageUrl'] as String?;
      }
      if (imageUrl == null) {
        final small = first['smallImageUrls'] as List?;
        if (small != null && small.isNotEmpty) {
          final v = small.first;
          imageUrl = v is String ? v : (v as Map<String, dynamic>)['imageUrl'] as String?;
        }
      }

      dev.log('Rakuten found: affUrl=${affUrl != null} imageUrl=${imageUrl != null}',
          name: 'RakutenRepository');

      return RakutenResult(affiliateUrl: affUrl, imageUrl: imageUrl);
    } catch (e) {
      dev.log('Rakuten search error: $e', name: 'RakutenRepository');
      return null;
    }
  }

  bool _hasValidKeys() =>
      !AppConstants.rakutenAppId.startsWith('YOUR_') &&
      AppConstants.rakutenAppId.isNotEmpty;
}
