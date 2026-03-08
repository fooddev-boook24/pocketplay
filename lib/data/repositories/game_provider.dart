import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/game.dart';
import 'bgg_repository.dart';

/// Loads BGG images and returns enriched game list.
final gamesProvider = FutureProvider<List<Game>>((ref) async {
  final imageMap = await BggRepository.instance.fetchImages(kSeedGames);
  return kSeedGames.map((g) {
    final url = imageMap[g.bggId];
    return url != null ? g.copyWith(imageUrl: url) : g;
  }).toList();
});

class ShelfRow {
  const ShelfRow({required this.label, required this.gameIds, required this.seed});
  final String label;
  final List<String> gameIds;
  final int seed;
}

// 6 shelf rows — different game mixes, enough boxes to fill 1.8× screen width
const kShelfRows = [
  ShelfRow(label: 'FEATURED',     seed: 101, gameIds: ['mysterium','gloomhaven','wingspan','catan','arkham','terraforming','7wonders','pandemic','azul','codenames','dominion','ticket_ride']),
  ShelfRow(label: 'STRATEGY',     seed: 202, gameIds: ['terraforming','concordia','viticulture','agricola','wingspan','7wonders','gloomhaven','catan','kingdomino','carcassonne','dominion','azul']),
  ShelfRow(label: '2 PLAYERS',    seed: 303, gameIds: ['patchwork','jaipur','lost_cities','hive','azul','splendor','codenames','bohnanza','love_letter','skull','no_thanks','coup']),
  ShelfRow(label: 'PARTY GAMES',  seed: 404, gameIds: ['dixit','codenames','sushi_go','skull','coup','hanabi','no_thanks','love_letter','carcassonne','kingdomino','bohnanza','mysterium']),
  ShelfRow(label: 'SMALL BOX',    seed: 505, gameIds: ['jaipur','splendor','patchwork','lost_cities','sushi_go','love_letter','coup','hanabi','skull','no_thanks','bohnanza','hive']),
  ShelfRow(label: 'NEW & HOT',    seed: 606, gameIds: ['wingspan','azul','viticulture','concordia','agricola','kingdomino','carcassonne','7wonders','ticket_ride','dominion','pandemic','catan']),
];
