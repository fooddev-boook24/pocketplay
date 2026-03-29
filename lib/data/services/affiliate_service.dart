import '../../core/constants.dart';
import '../models/game.dart';

class AffiliateService {
  /// Amazon検索URLを生成（API不要 - アソシエイトタグのみ使用）
  static String buildAmazonSearchUrl(Game game) {
    final keyword = Uri.encodeComponent('${game.title} ボードゲーム');
    return 'https://www.amazon.co.jp/s?k=$keyword'
        '&tag=${AppConstants.amazonAssociateTag}'
        '&linkCode=ur2';
  }

  /// 英語タイトルで検索するURL（日本語タイトルでヒットしない場合）
  static String buildAmazonSearchUrlEn(String titleEn) {
    final keyword = Uri.encodeComponent('$titleEn board game');
    return 'https://www.amazon.co.jp/s?k=$keyword'
        '&tag=${AppConstants.amazonAssociateTag}'
        '&linkCode=ur2';
  }

  /// 楽天検索URLを生成（アフィリエイトURL未取得時のフォールバック）
  static String buildRakutenSearchUrl(Game game) {
    final keyword = Uri.encodeComponent('${game.title} ボードゲーム');
    return 'https://search.rakuten.co.jp/search/mall/$keyword/';
  }
}
