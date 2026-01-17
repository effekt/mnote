// Duration representation for MNote
//
// Two-way duration model:
// - WrittenDuration: rhythmic spelling for notation
// - TickDuration: actual playback length in ticks

import 'package:flutter/foundation.dart';
import 'types.dart';

/// Note value (rhythmic type)
enum NoteValue {
  whole,
  half,
  quarter,
  eighth,
  sixteenth,
  thirtySecond,
  sixtyFourth,
}

/// Base ticks for each note value (at 480 ticks per quarter)
const Map<NoteValue, int> noteValueTicks = {
  NoteValue.whole: 1920,
  NoteValue.half: 960,
  NoteValue.quarter: 480,
  NoteValue.eighth: 240,
  NoteValue.sixteenth: 120,
  NoteValue.thirtySecond: 60,
  NoteValue.sixtyFourth: 30,
};

/// Reference to a tuplet group
@immutable
class TupletRef {
  final TupletId id;
  final int actual; // e.g., 3 (in 3:2)
  final int normal; // e.g., 2 (in 3:2)

  const TupletRef({
    required this.id,
    required this.actual,
    required this.normal,
  });

  /// Tuplet ratio as a multiplier (e.g., 2/3 for triplets)
  double get ratio => normal / actual;

  @override
  bool operator ==(Object other) =>
      other is TupletRef &&
      id == other.id &&
      actual == other.actual &&
      normal == other.normal;

  @override
  int get hashCode => Object.hash(id, actual, normal);
}

/// Written duration (for notation)
@immutable
class WrittenDuration {
  final NoteValue base;
  final int dots; // 0-3 augmentation dots
  final TupletRef? tuplet;

  const WrittenDuration({
    required this.base,
    this.dots = 0,
    this.tuplet,
  }) : assert(dots >= 0 && dots <= 3);

  /// Calculate tick duration from written duration
  TickDuration get ticks {
    var baseTicks = noteValueTicks[base]!;

    // Apply dots: each dot adds half of the previous value
    var total = baseTicks;
    var dotValue = baseTicks;
    for (var i = 0; i < dots; i++) {
      dotValue ~/= 2;
      total += dotValue;
    }

    // Apply tuplet ratio
    if (tuplet != null) {
      total = (total * tuplet!.ratio).round();
    }

    return total;
  }

  @override
  bool operator ==(Object other) =>
      other is WrittenDuration &&
      base == other.base &&
      dots == other.dots &&
      tuplet == other.tuplet;

  @override
  int get hashCode => Object.hash(base, dots, tuplet);

  @override
  String toString() {
    final dotStr = '.' * dots;
    final tupletStr = tuplet != null ? ' (${tuplet!.actual}:${tuplet!.normal})' : '';
    return '${base.name}$dotStr$tupletStr';
  }
}
