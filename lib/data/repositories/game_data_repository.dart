import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/game.dart';

/// Firestore CRUD — games コレクション
class GameDataRepository {
  GameDataRepository._();
  static final instance = GameDataRepository._();

  final _db = FirebaseFirestore.instance;

  // ─── 読み取り ────────────────────────────────────────────────────────────────

  /// Firestoreから全ゲームデータを取得
  Future<List<Game>> fetchGames() async {
    try {
      final snap = await _db.collection('games').get();
      final games = snap.docs.map(_docToGame).whereType<Game>().toList();
      dev.log('Fetched ${games.length} games from Firestore', name: 'GameDataRepository');
      return games;
    } catch (e) {
      dev.log('fetchGames error: $e', name: 'GameDataRepository');
      return [];
    }
  }

  /// 単一ゲームを取得
  Future<Game?> fetchGame(String gameId) async {
    try {
      final doc = await _db.collection('games').doc(gameId).get();
      return doc.exists ? _docToGame(doc) : null;
    } catch (e) {
      dev.log('fetchGame error: $e', name: 'GameDataRepository');
      return null;
    }
  }

  // ─── 書き込み ────────────────────────────────────────────────────────────────

  /// ゲームデータをFirestoreに保存（upsert）
  Future<void> saveGame(Game game) async {
    try {
      await _db.collection('games').doc(game.id).set(
        _gameToDoc(game),
        SetOptions(merge: true),
      );
      dev.log('Saved game: ${game.id}', name: 'GameDataRepository');
    } catch (e) {
      dev.log('saveGame error: $e', name: 'GameDataRepository');
    }
  }

  /// 複数ゲームをバッチ保存
  Future<void> saveGames(List<Game> games) async {
    try {
      final batch = _db.batch();
      for (final game in games) {
        batch.set(
          _db.collection('games').doc(game.id),
          _gameToDoc(game),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
      dev.log('Batch saved ${games.length} games', name: 'GameDataRepository');
    } catch (e) {
      dev.log('saveGames error: $e', name: 'GameDataRepository');
    }
  }

  // ─── 変換 ────────────────────────────────────────────────────────────────────

  Game? _docToGame(DocumentSnapshot doc) {
    try {
      final d = doc.data() as Map<String, dynamic>;
      final seed = kSeedGames.firstWhere(
        (g) => g.id == doc.id,
        orElse: () => kSeedGames.first,
      );
      final game = seed.copyWith(
        imageUrl:       d['imageUrl'] as String?,
        thumbnailUrl:   d['thumbnailUrl'] as String?,
        minPlayers:     d['minPlayers'] as int?,
        maxPlayers:     d['maxPlayers'] as int?,
        playTimeMinutes: d['playTimeMinutes'] as int?,
        bggRating:      (d['bggRating'] as num?)?.toDouble(),
        categories:     (d['categories'] as List?)?.cast<String>(),
        description:    d['description'] as String?,
        rakutenAffUrl:  d['rakutenAffUrl'] as String?,
      );
      dev.log('${doc.id}: players=${game.minPlayers}-${game.maxPlayers} time=${game.playTimeMinutes}',
          name: 'GameDataRepository');
      return game;
    } catch (e) {
      dev.log('_docToGame error for ${doc.id}: $e', name: 'GameDataRepository');
      return null;
    }
  }

  Map<String, dynamic> _gameToDoc(Game game) => {
    'id':             game.id,
    'bggId':          game.bggId,
    'title':          game.title,
    'imageUrl':       game.imageUrl,
    'thumbnailUrl':   game.thumbnailUrl,
    'minPlayers':     game.minPlayers,
    'maxPlayers':     game.maxPlayers,
    'playTimeMinutes': game.playTimeMinutes,
    'bggRating':      game.bggRating,
    'categories':     game.categories,
    'description':    game.description,
    'isAvailableInJapan': game.isAvailableInJapan,
    'rakutenAffUrl':  game.rakutenAffUrl,
    'lastUpdated':    FieldValue.serverTimestamp(),
  };
}
