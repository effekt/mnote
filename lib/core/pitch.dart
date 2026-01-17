// Pitch representation for MNote
//
// Three-way pitch model:
// - Pitch: semantic meaning (C# in any context)
// - NotatedPitch: how to engrave it (with/without accidental)
// - PlaybackPitch: what to play (MIDI number)

import 'package:flutter/foundation.dart';

/// Pitch step (diatonic note name)
enum PitchStep { C, D, E, F, G, A, B }

/// Semantic pitch (musical meaning)
@immutable
class Pitch {
  final PitchStep step;
  final int alter; // -2 to +2 (double-flat to double-sharp)
  final int octave; // 0–9 (middle C = octave 4)

  const Pitch({
    required this.step,
    this.alter = 0,
    required this.octave,
  })  : assert(alter >= -2 && alter <= 2),
        assert(octave >= 0 && octave <= 9);

  /// Convert to MIDI pitch number
  int get midiPitch {
    const stepToSemitone = {
      PitchStep.C: 0,
      PitchStep.D: 2,
      PitchStep.E: 4,
      PitchStep.F: 5,
      PitchStep.G: 7,
      PitchStep.A: 9,
      PitchStep.B: 11,
    };
    return (octave + 1) * 12 + stepToSemitone[step]! + alter;
  }

  @override
  bool operator ==(Object other) =>
      other is Pitch &&
      step == other.step &&
      alter == other.alter &&
      octave == other.octave;

  @override
  int get hashCode => Object.hash(step, alter, octave);

  @override
  String toString() {
    const alterSymbols = {
      -2: '𝄫',
      -1: '♭',
      0: '',
      1: '♯',
      2: '𝄪',
    };
    return '${step.name}${alterSymbols[alter]}$octave';
  }
}

/// How to display an accidental
enum AccidentalDisplay {
  none,      // Implied by key signature
  show,      // Explicitly shown
  courtesy,  // Cautionary (parenthesized)
  editorial, // Editor-added (bracketed)
}

/// Notated pitch (separates meaning from display)
@immutable
class NotatedPitch {
  final Pitch pitch;
  final AccidentalDisplay display;

  const NotatedPitch({
    required this.pitch,
    this.display = AccidentalDisplay.none,
  });

  @override
  bool operator ==(Object other) =>
      other is NotatedPitch &&
      pitch == other.pitch &&
      display == other.display;

  @override
  int get hashCode => Object.hash(pitch, display);
}

/// Playback pitch (acoustic reality)
@immutable
class PlaybackPitch {
  final int midiPitch; // 0–127
  final double? cents; // Microtonal deviation from equal temperament

  const PlaybackPitch({
    required this.midiPitch,
    this.cents,
  }) : assert(midiPitch >= 0 && midiPitch <= 127);

  /// Create from semantic Pitch
  factory PlaybackPitch.fromPitch(
    Pitch pitch, {
    double? cents,
  }) {
    return PlaybackPitch(
      midiPitch: pitch.midiPitch,
      cents: cents,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PlaybackPitch &&
      midiPitch == other.midiPitch &&
      cents == other.cents;

  @override
  int get hashCode => Object.hash(midiPitch, cents);
}
