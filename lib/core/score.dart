// Score, Measure, Segment, and VoiceSlice for MNote
//
// The complete score structure. Score is the root,
// containing measures which contain segments which contain voice slices.

import 'package:flutter/foundation.dart';
import 'types.dart';
import 'note.dart';

/// Time signature
@immutable
class TimeSignature {
  final int beats;
  final int beatType;

  const TimeSignature({
    required this.beats,
    required this.beatType,
  });

  /// Ticks per measure
  int get ticksPerMeasure => (ticksPerQuarter * 4 * beats) ~/ beatType;

  @override
  bool operator ==(Object other) =>
      other is TimeSignature && beats == other.beats && beatType == other.beatType;

  @override
  int get hashCode => Object.hash(beats, beatType);

  @override
  String toString() => '$beats/$beatType';
}

/// Key signature
@immutable
class KeySignature {
  final int fifths; // -7 to +7 (flats to sharps)
  final KeyMode mode;

  const KeySignature({
    required this.fifths,
    this.mode = KeyMode.major,
  }) : assert(fifths >= -7 && fifths <= 7);

  @override
  bool operator ==(Object other) =>
      other is KeySignature && fifths == other.fifths && mode == other.mode;

  @override
  int get hashCode => Object.hash(fifths, mode);
}

enum KeyMode { major, minor }

/// Clef type
enum ClefType { treble, bass, alto, tenor, percussion }

/// Clef
@immutable
class Clef {
  final ClefType type;
  final int line; // Staff line (1-5, bottom to top)

  const Clef({
    required this.type,
    required this.line,
  });

  static const treble = Clef(type: ClefType.treble, line: 2);
  static const bass = Clef(type: ClefType.bass, line: 4);
  static const alto = Clef(type: ClefType.alto, line: 3);

  @override
  bool operator ==(Object other) =>
      other is Clef && type == other.type && line == other.line;

  @override
  int get hashCode => Object.hash(type, line);
}

/// Tempo marking
@immutable
class Tempo {
  final TickPosition tick;
  final double bpm;

  const Tempo({
    required this.tick,
    required this.bpm,
  });

  /// Milliseconds per tick
  double get msPerTick => 60000 / (bpm * ticksPerQuarter);

  @override
  bool operator ==(Object other) =>
      other is Tempo && tick == other.tick && bpm == other.bpm;

  @override
  int get hashCode => Object.hash(tick, bpm);
}

/// A slice of a voice at a specific tick
@immutable
class VoiceSlice {
  final List<NoteLike> elements;

  const VoiceSlice({
    this.elements = const [],
  });

  @override
  bool operator ==(Object other) =>
      other is VoiceSlice && listEquals(elements, other.elements);

  @override
  int get hashCode => Object.hashAll(elements);
}

/// A segment at a specific tick position
@immutable
class Segment {
  final TickPosition tick;
  final Map<VoiceId, VoiceSlice> voices;

  const Segment({
    required this.tick,
    this.voices = const {},
  });

  @override
  bool operator ==(Object other) =>
      other is Segment && tick == other.tick && mapEquals(voices, other.voices);

  @override
  int get hashCode => Object.hash(tick, Object.hashAll(voices.entries));
}

/// A measure in the score
@immutable
class Measure {
  final MeasureId id;
  final int number;
  final TickPosition startTick;
  final TickDuration duration;
  final TimeSignature? timeSignature; // Only if changed
  final KeySignature? keySignature; // Only if changed
  final Clef? clef; // Only if changed
  final List<Segment> segments;

  const Measure({
    required this.id,
    required this.number,
    required this.startTick,
    required this.duration,
    this.timeSignature,
    this.keySignature,
    this.clef,
    this.segments = const [],
  });

  TickPosition get endTick => startTick + duration;

  @override
  bool operator ==(Object other) => other is Measure && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A part (instrument/voice track)
@immutable
class Part {
  final PartId id;
  final String name;
  final String? abbreviation;
  final int midiProgram;

  const Part({
    required this.id,
    required this.name,
    this.abbreviation,
    this.midiProgram = 0,
  });

  @override
  bool operator ==(Object other) => other is Part && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Spanner placement
enum Placement { above, below }

/// Time range for spanners
@immutable
class TimeRange {
  final TickPosition startTick;
  final TickPosition endTick;

  const TimeRange({
    required this.startTick,
    required this.endTick,
  });

  @override
  bool operator ==(Object other) =>
      other is TimeRange &&
      startTick == other.startTick &&
      endTick == other.endTick;

  @override
  int get hashCode => Object.hash(startTick, endTick);
}

/// A slur connecting notes
@immutable
class Slur {
  final SlurId id;
  final NoteId startNoteId;
  final NoteId endNoteId;
  final TimeRange range;
  final Placement placement;

  const Slur({
    required this.id,
    required this.startNoteId,
    required this.endNoteId,
    required this.range,
    this.placement = Placement.above,
  });

  @override
  bool operator ==(Object other) => other is Slur && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A tie connecting notes of same pitch
@immutable
class Tie {
  final TieId id;
  final NoteId startNoteId;
  final NoteId endNoteId;

  const Tie({
    required this.id,
    required this.startNoteId,
    required this.endNoteId,
  });

  @override
  bool operator ==(Object other) => other is Tie && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// All spanners in a score
@immutable
class Spanners {
  final List<Slur> slurs;
  final List<Tie> ties;

  const Spanners({
    this.slurs = const [],
    this.ties = const [],
  });
}

/// The complete score
@immutable
class Score {
  final ScoreId id;
  final String title;
  final List<Part> parts;
  final List<Measure> measures;
  final Spanners spanners;
  final List<Tempo> tempos;

  const Score({
    required this.id,
    this.title = 'Untitled',
    this.parts = const [],
    this.measures = const [],
    this.spanners = const Spanners(),
    this.tempos = const [],
  });

  /// Create an empty score
  factory Score.empty() {
    return const Score(
      id: '',
      tempos: [Tempo(tick: 0, bpm: 120)],
    );
  }

  /// Total duration in ticks
  TickDuration get totalDuration {
    if (measures.isEmpty) return 0;
    final lastMeasure = measures.last;
    return lastMeasure.startTick + lastMeasure.duration;
  }

  /// Get tempo at a specific tick
  Tempo tempoAt(TickPosition tick) {
    for (var i = tempos.length - 1; i >= 0; i--) {
      if (tempos[i].tick <= tick) {
        return tempos[i];
      }
    }
    return const Tempo(tick: 0, bpm: 120);
  }

  @override
  bool operator ==(Object other) => other is Score && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
