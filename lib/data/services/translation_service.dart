import 'dart:convert';
import 'dart:developer' as dev;
import 'package:http/http.dart' as http;

/// Google Translate 非公式エンドポイントを使った翻訳サービス
/// APIキー不要。結果はFirestoreにキャッシュされるため1ゲームにつき1回だけ実行される。
class TranslationService {
  TranslationService._();

  /// テキストが日本語（ひらがな・カタカナ・漢字を含む）かどうか判定
  static bool isJapanese(String text) =>
      text.contains(RegExp(r'[\u3040-\u30FF\u4E00-\u9FFF]'));

  /// テキストを日本語に翻訳する。
  /// すでに日本語なら原文をそのまま返す。失敗時は null を返す。
  static Future<String?> toJapanese(String text) async {
    if (text.isEmpty) return null;
    if (isJapanese(text)) return text;

    // 5000文字超は先頭5000文字のみ翻訳（APIの制限）
    final input = text.length > 5000 ? text.substring(0, 5000) : text;

    try {
      final uri = Uri.parse(
        'https://translate.googleapis.com/translate_a/single'
        '?client=gtx&sl=auto&tl=ja&dt=t&q=${Uri.encodeComponent(input)}',
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      if (res.statusCode != 200) {
        dev.log('Translation HTTP error: ${res.statusCode}',
            name: 'TranslationService');
        return null;
      }

      // レスポンス形式: [ [ ["訳文", "原文", ...], ... ], ..., "en" ]
      final data = jsonDecode(res.body);
      final sentences = data[0] as List<dynamic>;
      final buffer = StringBuffer();
      for (final s in sentences) {
        if (s is List && s.isNotEmpty && s[0] is String) {
          buffer.write(s[0] as String);
        }
      }

      final translated = buffer.toString().trim();
      if (translated.isEmpty) return null;

      dev.log('Translated ${input.length} chars → ${translated.length} chars',
          name: 'TranslationService');
      return translated;
    } catch (e) {
      dev.log('Translation error: $e', name: 'TranslationService');
      return null;
    }
  }
}
