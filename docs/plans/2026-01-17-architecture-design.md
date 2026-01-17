# MNote Architecture Design

**Date:** 2026-01-17
**Status:** Approved
**Platform:** Flutter (iOS, Android, Web, Desktop)

## Vision

A music composition and transcription app that lets users write music notes on a tablet/phone, transcribe handwritten notation, and play it back with multiple instruments. Future goals include accompaniment generation and alternative renditions.

## Core Principle

> **"The sheet is a spatial index. The music lives in a semantic model."**

The visual representation (coordinates, pixels) is separate from the musical meaning (pitches, durations, articulations). This separation enables:
- Multiple input methods (tap-to-place, handwriting, recording)
- Multiple output methods (playback, export, AI composition)
- Clean undo/redo
- Future collaboration

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     INPUT LAYER (Flutter)                       │
│  Stylus strokes → Stroke{ points[], pressure[], velocity[] }   │
│  Uses: Listener widget, PointerDeviceKind.stylus detection     │
│  Manual palm rejection (radiusMajor threshold)                  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                 INTERPRETATION LAYER (Pure Dart)                │
│  Stroke classifier: $1 Recognizer + geometric heuristics       │
│  Staff snapping: Y → pitch (diatonic), X → beat (quantized)    │
│  Gesture grammar: stem+head→note, arc between notes→slur       │
│  Output: GestureIntent (never mutates score directly)           │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    COMMAND LAYER (Pure Dart)                    │
│  GestureIntent → Command → Score mutation                       │
│  All mutations are reversible (undo/redo)                       │
│  CommandHistory with revision tracking                          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                 MUSIC MODEL (Platform-Agnostic)                 │
│  Score → Part[] → Measure[] → Segment[] → Note/Rest/Chord      │
│  480 ticks per quarter note, dual pitch (semantic + MIDI)       │
│  Spanners stored separately (slurs, wedges, ties)              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    LAYOUT ENGINE (Pure Dart)                    │
│  Score (ticks) → LayoutResult (coordinates)                     │
│  tickToPosition() / positionToTick() queries                    │
│  Hit-testing via elementBounds map                              │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    PLAYBACK LAYER (Flutter)                     │
│  flutter_midi_pro + SoundFont (.sf2) for instrument sounds     │
│  Position stream → cursor sync with notation                    │
│  Playback reads score, never writes                             │
└─────────────────────────────────────────────────────────────────┘
```

---

## Layer 1: Input

### Stroke Capture

```dart
class Stroke {
  final List<StrokePoint> points;
  final DateTime timestamp;
  final PointerDeviceKind deviceKind;
}

class StrokePoint {
  final Offset position;
  final double pressure;      // 0.0 to 1.0+
  final double velocity;      // Derived from deltas + timestamps
  final int timestamp;        // Milliseconds
}
```

### Stylus Detection

```dart
Listener(
  onPointerDown: (event) {
    if (event.kind == PointerDeviceKind.stylus) {
      startDrawing(event);
    } else if (event.kind == PointerDeviceKind.touch) {
      startPanning(event);  // Finger = pan, stylus = draw
    }
  },
)
```

### Palm Rejection

- Filter by `radiusMajor` threshold (palms have larger contact area)
- Ignore multi-touch during stylus contact
- Confidence window: first 20ms of stroke defines intent

---

## Layer 2: Interpretation

### Pipeline

```
Stroke → Classify → Contextualize → Resolve → GestureIntent
```

### Classification

```dart
enum StrokeClass {
  noteHead,           // Elliptical, aspect ~1.3:1
  stem,               // Vertical, length/width > 5:1
  beam,               // Thick angled line
  slurArc,            // Curved, endpoints near notes
  accidentalSharp, accidentalFlat, accidentalNatural,
  dot,                // Small circle
  horizontalLine,     // Tenuto
  accentStroke,       // Vertical tick
  unknown
}
```

Uses $1 Unistroke Recognizer for template matching, geometric heuristics for fast paths.

### Contextualization

```dart
class StrokeContext {
  final StaffPosition staffPos;
  final Pitch inferredPitch;
  final TickPosition beatPosition;
  final NoteId? nearestNote;
  final MeasureId measureId;
  final double pitchConfidence;   // For ambiguity handling
  final double beatConfidence;
}
```

### Resolution (Grammar Rules)

- Note head alone → whole note
- Note head + stem → quarter note (duration refinable by later flags/beams)
- Arc connecting same pitch → tie
- Arc connecting different pitches → slur
- Dot right of note → augmentation
- Dot above/below note → staccato
- Horizontal line near note → tenuto

### Snapping

- **Soft snap** during drawing (visual feedback, reversible)
- **Hard snap** on stroke complete (commits to grid)

### Ambiguity Handling

```dart
class AmbiguousIntent extends GestureIntent {
  final List<GestureIntent> possibilities;
  final GestureIntent recommended;
}
```

UI can show disambiguation menu or auto-accept recommended.

---

## Layer 3: Command System

### Core Interface

```dart
abstract class Command {
  CommandResult apply(Score score);
  void revert(Score score);
  String get description;
}

class CommandResult {
  final bool success;
  final String? error;
}
```

### Command Examples

```dart
class AddNoteCommand implements Command {
  final NoteId noteId;
  final NoteData data;
  final MeasureId measureId;
}

class AddSlurCommand implements Command {
  final SlurId slurId;
  final NoteId startNoteId;
  final NoteId endNoteId;
}

class CompoundCommand implements Command {
  final List<Command> commands;

  void apply(Score s) => commands.forEach((c) => c.apply(s));
  void revert(Score s) => commands.reversed.forEach((c) => c.revert(s));
}
```

### Command History

```dart
class CommandHistory {
  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];
  int revision = 0;

  void execute(Command cmd, Score score) {
    final result = cmd.apply(score);
    if (result.success) {
      _undoStack.add(cmd);
      _redoStack.clear();
      revision++;
    }
  }
}
```

### Key Rules

- Commands reference **IDs**, not objects (for serialization/collaboration)
- Commands are **semantic** (AddNote, AddSlur) not mechanical (InsertAtIndex)
- Interpretation **never** touches the score directly

---

## Layer 4: Music Model

### Timing

- 480 ticks per quarter note (industry standard)
- All time positions are absolute tick values

### Pitch Representation

```dart
// Semantic pitch (for notation)
class Pitch {
  final PitchStep step;  // C, D, E, F, G, A, B
  final int alter;       // -2 to +2 (double-flat to double-sharp)
  final int octave;      // 0-9 (middle C = octave 4)
}

// Playback pitch
class PlaybackPitch {
  final int midiPitch;   // 0-127
  final double? cents;   // Microtonal deviation
}
```

Dual representation preserves enharmonic spelling (C# vs Db).

### Core Elements

```dart
class Note {
  final NoteId id;
  final Pitch pitch;
  final PlaybackPitch playbackPitch;
  final Duration duration;
  final int voice;
  final int staff;
  final int velocity;
  final List<Articulation> articulations;
  final TieId? tieStart;
  final TieId? tieEnd;
}

class Measure {
  final MeasureId id;
  final int number;
  final TickPosition startTick;
  final TickPosition duration;
  final TimeSignature? timeSignature;  // Only if changed
  final KeySignature? keySignature;    // Only if changed
  final List<Segment> segments;
}

class Segment {
  final TickPosition tick;
  final Map<int, List<Element>> elements;  // Keyed by track
}
```

### Spanners (Cross-Measure Elements)

```dart
class Slur {
  final SlurId id;
  final NoteId startNoteId;
  final NoteId endNoteId;
  final TimeRange range;
  final Placement placement;
}

class TimeRange {
  final TickPosition startTick;
  final TickPosition endTick;
}
```

Spanners are stored separately from notes, referenced by ID.

### Score Structure

```dart
class Score {
  final ScoreId id;
  final List<Part> parts;
  final List<Measure> measures;
  final Spanners spanners;  // slurs, wedges, ties, ottavas
  final List<Tempo> tempos;
  final int divisions = 480;
}
```

---

## Layer 5: Layout Engine

### Interface

```dart
abstract class LayoutEngine {
  LayoutResult layout(Score score, LayoutConstraints constraints);
}

class LayoutConstraints {
  final double pageWidth;
  final double staffHeight;
  final double systemSpacing;
  final double measureMinWidth;
  final double measureMaxWidth;
  final int measuresPerSystem;  // Hint
}
```

### Layout Result

```dart
class LayoutResult {
  final List<SystemLayout> systems;
  final Map<ElementId, Rect> elementBounds;  // For hit-testing

  Offset tickToPosition(TickPosition tick, int staff);
  TickPosition positionToTick(Offset pos, int staff);
  ElementId? hitTest(Offset pos);
}
```

### Measure & Staff Layout

```dart
class MeasureLayout {
  final MeasureId id;
  final double x;
  final double width;
  final TickPosition startTick;
  final TickPosition endTick;

  double tickToX(TickPosition tick) {
    final progress = (tick - startTick) / (endTick - startTick);
    return x + (progress * width);
  }
}

class StaffLayout {
  final int staffIndex;
  final double y;
  final double lineSpacing;

  double pitchToY(Pitch pitch, Clef clef);
  Pitch yToPitch(double y, Clef clef);
}
```

### Key Invariant

> **The score never stores pixel coordinates. Layout is always derived.**

Layout is:
- Immutable
- Recomputable
- Cacheable (keyed by score revision + constraints)

---

## Layer 6: Playback

### Interface

```dart
abstract class PlaybackEngine {
  Stream<TickPosition> get positionStream;
  PlaybackState get state;

  Future<void> play({TickPosition? from});
  Future<void> pause();
  Future<void> stop();
  Future<void> seekTo(TickPosition tick);

  void setTempo(double bpm);
  void setInstrument(int partIndex, MidiInstrument instrument);
}
```

### Implementation Notes

- Use **wall-clock deltas** for tick calculation (not timer-based incrementing)
- Pre-compute MIDI events before playback starts
- Tempo changes are stored in Score.tempos, not playback state

### Cursor Synchronization

```dart
StreamBuilder<TickPosition>(
  stream: playback.positionStream,
  builder: (context, snapshot) {
    final position = layout.tickToPosition(snapshot.data!, staff: 0);
    return PlaybackCursor(position: position);
  },
)
```

### Key Invariant

> **Playback reads, never writes.** Score mutations only via Commands.

---

## Technology Stack

### Flutter Packages

| Component | Package | Purpose |
|-----------|---------|---------|
| MIDI Playback | `flutter_midi_pro` | SoundFont-based synthesis |
| Audio (backup) | `flutter_soloud` | Low-latency if needed |
| Gesture Recognition | Custom + $1 Recognizer | Stroke classification |

### Rendering

- `CustomPainter` for notation rendering
- SMuFL fonts (Bravura) for music glyphs
- `InteractiveViewer` for zoom/pan (with bitmap caching for performance)

---

## Build Phases

### Phase 1: Structured Notation MVP
- Staff rendering
- Tap-to-place notes (snap to grid)
- Simple playback (single instrument, piano)
- Basic undo/redo

### Phase 2: Gesture Layer
- Slur/tie recognition
- Articulation gestures (staccato, tenuto, accent)
- Dynamics (p, f, crescendo)

### Phase 3: Handwriting Recognition
- Freehand note heads
- Gesture-based rhythm input
- ML-assisted classification (optional enhancement)

### Phase 4: Composition Intelligence
- Harmony suggestions
- Accompaniment generation
- Alternative renditions (different octave, instrument)

---

## Appendix: Key Invariants

1. **Interpretation never mutates the score** - only Commands do
2. **Commands reference IDs, not objects** - for serialization safety
3. **Layout is derived, never stored** - the score knows ticks, not pixels
4. **Playback reads, never writes** - no playback-induced state corruption
5. **Musical time (ticks) is authoritative** - visual position is computed
6. **Undo is free** - because all mutations are reversible Commands
