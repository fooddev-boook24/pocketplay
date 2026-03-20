import 'game.dart';

class GameDetail {
  const GameDetail({
    required this.game,
    this.mechanics = const [],
    this.designers = const [],
    this.yearPublished,
    this.complexity,
  });

  final Game game;
  final List<String> mechanics;
  final List<String> designers;
  final int? yearPublished;
  final double? complexity; // BGG weight 1-5

  String get complexityLabel {
    if (complexity == null) return '-';
    if (complexity! < 1.5) return 'かんたん';
    if (complexity! < 2.5) return '初心者向け';
    if (complexity! < 3.5) return '中級者向け';
    if (complexity! < 4.5) return '上級者向け';
    return 'エキスパート';
  }
}
