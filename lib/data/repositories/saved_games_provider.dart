import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/game.dart';
import 'game_provider.dart';

const _kSavedKey = 'saved_game_ids';

// ── 保存済みゲームIDセット ──────────────────────────────────────────────────
final savedIdsProvider =
    StateNotifierProvider<SavedIdsNotifier, Set<String>>(
  (ref) => SavedIdsNotifier(),
);

class SavedIdsNotifier extends StateNotifier<Set<String>> {
  SavedIdsNotifier() : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_kSavedKey) ?? [];
    state = list.toSet();
  }

  Future<void> toggle(String gameId) async {
    final next = {...state};
    if (next.contains(gameId)) {
      next.remove(gameId);
    } else {
      next.add(gameId);
    }
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kSavedKey, next.toList());
  }

  bool isSaved(String gameId) => state.contains(gameId);
}

// ── 保存済みゲームリスト（gamesProviderから引き当て）──────────────────────
final savedGamesProvider = Provider<List<Game>>((ref) {
  final ids = ref.watch(savedIdsProvider);
  final gamesAsync = ref.watch(gamesProvider);
  final allGames = gamesAsync.maybeWhen(data: (g) => g, orElse: () => kSeedGames);
  // IDの順序を保持しつつ一致するゲームを返す
  return ids
      .map((id) => allGames.firstWhere(
            (g) => g.id == id,
            orElse: () => allGames.first,
          ))
      .where((g) => ids.contains(g.id))
      .toList();
});

// ── 並び替え ────────────────────────────────────────────────────────────────
enum SavedSortOrder { added, rating }

final savedSortOrderProvider =
    StateProvider<SavedSortOrder>((ref) => SavedSortOrder.added);

final savedGamesSortedProvider = Provider<List<Game>>((ref) {
  final games = ref.watch(savedGamesProvider);
  final order = ref.watch(savedSortOrderProvider);
  if (order == SavedSortOrder.added) return games;
  return [...games]
    ..sort((a, b) => (b.bggRating ?? 0).compareTo(a.bggRating ?? 0));
});
