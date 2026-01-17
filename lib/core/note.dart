// Note, Chord, Rest, and GraceGroup for MNote
//
// Core musical elements that populate VoiceSlice.
// NoteLike is a sealed class for type-safe pattern matching.

import 'package:flutter/foundation.dart';
import 'types.dart';
import 'pitch.dart';
import 'duration.dart';

/// Articulation marks
enum Articulation {
  staccato,
  staccatissimo,
  tenuto,
  accent,
  marcato,
  fermata,
}

/// Grace note type
enum GraceType {
  acciaccatura, // Slashed, very short before beat
  appoggiatura, // Steals time from principal note
}

/// Base class for all elements in a VoiceSlice
sealed class NoteLike {
  EntityId get id;
  VoiceId get voice;
  int get staff;

  const NoteLike();
}

/// A single note
@immutable
class Note extends NoteLike {
  @override
  final NoteId id;
  final NotatedPitch pitch;
  final PlaybackPitch playbackPitch;
  final WrittenDuration written;
  final TickDuration playbackDuration;
  @override
  final VoiceId voice;
  @override
  final int staff;
  final int velocity;
  final List<Articulation> articulations;
  final TieId? tieStart;
  final TieId? tieEnd;
  final bool forceBeamBreak;

  const Note({
    required this.id,
    required this.pitch,
    required this.playbackPitch,
    required this.written,
    required this.playbackDuration,
    required this.voice,
    required this.staff,
    this.velocity = 80,
    this.articulations = const [],
    this.tieStart,
    this.tieEnd,
    this.forceBeamBreak = false,
  });

  @override
  bool operator ==(Object other) => other is Note && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A chord (multiple pitches, shared duration)
@immutable
class Chord extends NoteLike {
  @override
  final ChordId id;
  final List<NotatedPitch> pitches;
  final List<PlaybackPitch> playbackPitches;
  final WrittenDuration written;
  final TickDuration playbackDuration;
  @override
  final VoiceId voice;
  @override
  final int staff;
  final int velocity;
  final List<Articulation> articulations;
  final bool forceBeamBreak;

  const Chord({
    required this.id,
    required this.pitches,
    required this.playbackPitches,
    required this.written,
    required this.playbackDuration,
    required this.voice,
    required this.staff,
    this.velocity = 80,
    this.articulations = const [],
    this.forceBeamBreak = false,
  });

  @override
  bool operator ==(Object other) => other is Chord && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A rest
@immutable
class Rest extends NoteLike {
  @override
  final RestId id;
  final WrittenDuration written;
  final TickDuration playbackDuration;
  @override
  final VoiceId voice;
  @override
  final int staff;
  final bool isMeasureRest;

  const Rest({
    required this.id,
    required this.written,
    required this.playbackDuration,
    required this.voice,
    required this.staff,
    this.isMeasureRest = false,
  });

  @override
  bool operator ==(Object other) => other is Rest && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A group of grace notes attached to a principal note
/// Grace notes have zero tick duration - playback engine handles timing
@immutable
class GraceGroup extends NoteLike {
  @override
  final GraceGroupId id;
  final List<Note> notes;
  final NoteId principalNoteId;
  final GraceType type;

  const GraceGroup({
    required this.id,
    required this.notes,
    required this.principalNoteId,
    required this.type,
  });

  @override
  VoiceId get voice => notes.first.voice;

  @override
  int get staff => notes.first.staff;

  @override
  bool operator ==(Object other) => other is GraceGroup && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
