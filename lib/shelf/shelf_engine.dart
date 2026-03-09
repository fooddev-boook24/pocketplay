import 'dart:math' as math;
import 'package:flutter/painting.dart';
import '../data/models/game.dart';

enum BoxPose { spine, face, stack }

enum PopType { stand, plate, lean }

class PlacedBox {
  const PlacedBox({
    required this.game, required this.pose,
    required this.x, required this.row,
    required this.width, required this.height,
    this.tilt = 0.0, this.zIndex = 0,
    this.stackLayer = 0, this.stackTotal = 1,
  });
  final Game game;
  final BoxPose pose;
  final double x, width, height;
  final int row, zIndex, stackLayer, stackTotal;
  final double tilt;
}

class PlacedPop {
  const PlacedPop({
    required this.label, required this.type,
    required this.x,    required this.seed,
  });
  final String label;
  final PopType type;
  final double x;
  final int seed;
}

// ── geometry ──────────────────────────────────────────────────────────────────
const double kShelfTopH = 22.0;  // 棚板の上面（奥行き面）← NEW
const double kRowHeight = 210.0; // 本エリア高さ
const double kBoardH    = 14.0;  // 棚板前面の厚み
const double kPillarW   = 26.0;

const Map<PopType, Size> kPopSize = {
  PopType.stand: Size(44.0, 92.0),
  PopType.plate: Size(88.0, 28.0),
  PopType.lean:  Size(52.0, 82.0),
};

class ShelfLayoutEngine {
  ShelfLayoutEngine._();

  static List<PlacedBox> generateRow({
    required List<Game> games,
    required int row,
    required double wallWidth,
    required math.Random rng,
  }) {
    final result = <PlacedBox>[];
    double cursor = 40.0 + rng.nextDouble() * 30;
    int gi = rng.nextInt(games.length);
    int zi = 0;

    final estSlots = (wallWidth / 45).ceil();
    final faceSlots  = <int>{};
    final stackSlots = <int>{};

    int nextFace = 2 + rng.nextInt(2);
    while (nextFace < estSlots) {
      faceSlots.add(nextFace);
      nextFace += 4 + rng.nextInt(4);
    }
    for (int s = 0; s < 1 + rng.nextInt(2); s++) {
      int p = 3 + rng.nextInt(math.max(1, estSlots - 6));
      while (faceSlots.contains(p) || stackSlots.contains(p)) p++;
      stackSlots.add(p);
    }

    int slot = 0;
    while (cursor < wallWidth - 60) {
      final game = games[gi % games.length];
      gi++;

      if (faceSlots.contains(slot)) {
        cursor += _gap(rng, 8.0, 18.0);
        final h = _faceH(game.size);
        final w = h * game.faceAspect;
        result.add(PlacedBox(
          game: game, pose: BoxPose.face,
          x: cursor, row: row, width: w, height: h,
          tilt: (rng.nextDouble() - 0.5) * 0.005, zIndex: zi + 5,
        ));
        cursor += w + _gap(rng, 14.0, 28.0);
      } else if (stackSlots.contains(slot)) {
        cursor += _gap(rng, 6.0, 14.0);
        final count = 2 + rng.nextInt(2);
        final sw = 78.0 + rng.nextDouble() * 30;
        final lh = 20.0 + rng.nextDouble() * 7;
        for (int s = 0; s < count; s++) {
          result.add(PlacedBox(
            game: games[(gi + s) % games.length],
            pose: BoxPose.stack,
            x: cursor, row: row, width: sw, height: lh,
            tilt: (rng.nextDouble() - 0.5) * 0.003,
            zIndex: zi + s, stackLayer: s, stackTotal: count,
          ));
        }
        cursor += sw + _gap(rng, 12.0, 22.0);
        gi += count - 1; zi += count;
      } else {
        final sw = _spineW(game.size, rng);
        final sh = _spineH(game.size, rng);
        result.add(PlacedBox(
          game: game, pose: BoxPose.spine,
          x: cursor, row: row, width: sw, height: sh,
          tilt: (rng.nextDouble() - 0.5) * 0.016, zIndex: zi,
        ));
        final bigGap = rng.nextDouble() < 0.08;
        cursor += sw + (bigGap ? _gap(rng, 22.0, 55.0) : _gap(rng, 0.0, 1.5));
      }
      slot++; zi++;
      if (cursor > wallWidth + 100) break;
    }
    return result;
  }

  static List<PlacedPop> generatePops({
    required String label, required int seed, required double wallWidth,
  }) {
    final rng = math.Random(seed ^ 0xC4AD);
    final roll = rng.nextDouble();
    final count = roll < 0.15 ? 0 : roll < 0.70 ? 1 : 2;
    if (count == 0) return [];

    final types = PopType.values;
    final result = <PlacedPop>[];
    final usedX  = <double>[];

    for (int i = 0; i < count; i++) {
      double x;
      int tries = 0;
      do {
        x = wallWidth * (0.08 + rng.nextDouble() * 0.84);
        tries++;
      } while (tries < 20 && usedX.any((ux) => (ux - x).abs() < 120));
      usedX.add(x);
      result.add(PlacedPop(
        label: label, type: types[rng.nextInt(types.length)],
        x: x, seed: seed ^ (i * 0x7F3A),
      ));
    }
    return result;
  }

  static double _faceH(BoxSize s) {
    switch (s) {
      case BoxSize.tiny:   return kRowHeight * 0.50;
      case BoxSize.small:  return kRowHeight * 0.62;
      case BoxSize.medium: return kRowHeight * 0.74;
      case BoxSize.large:  return kRowHeight * 0.84;
    }
  }

  static double _spineW(BoxSize s, math.Random rng) {
    switch (s) {
      case BoxSize.tiny:   return 10.0 + rng.nextDouble() * 8;
      case BoxSize.small:  return 16.0 + rng.nextDouble() * 12;
      case BoxSize.medium: return 24.0 + rng.nextDouble() * 14;
      case BoxSize.large:  return 32.0 + rng.nextDouble() * 18;
    }
  }

  static double _spineH(BoxSize s, math.Random rng) {
    switch (s) {
      case BoxSize.tiny:   return kRowHeight * (0.44 + rng.nextDouble() * 0.14);
      case BoxSize.small:  return kRowHeight * (0.52 + rng.nextDouble() * 0.16);
      case BoxSize.medium: return kRowHeight * (0.62 + rng.nextDouble() * 0.16);
      case BoxSize.large:  return kRowHeight * (0.70 + rng.nextDouble() * 0.14);
    }
  }

  static double _gap(math.Random rng, double min, double max) =>
      min + rng.nextDouble() * (max - min);
}
