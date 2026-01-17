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
  final Map<String, EntityId> createdIds;  // IDs generated by this command
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

// Notated pitch (separates meaning from display)
class NotatedPitch {
  final Pitch pitch;
  final AccidentalDisplay display;  // How to show accidental
}

enum AccidentalDisplay {
  none,       // Implied by key signature
  show,       // Explicitly shown
  courtesy,   // Cautionary (parenthesized)
  editorial,  // Editor-added (bracketed)
}

// Playback pitch
class PlaybackPitch {
  final int midiPitch;   // 0-127
  final double? cents;   // Microtonal deviation
}
```

Three-way representation:
- `Pitch` = semantic meaning (C# in any context)
- `NotatedPitch` = how to engrave it (with/without accidental)
- `PlaybackPitch` = what to play (MIDI 61)

### Duration Representation

```dart
// Written duration (for notation)
class WrittenDuration {
  final NoteValue base;      // whole, half, quarter, eighth, 16th, etc.
  final int dots;            // 0-3 augmentation dots
  final TupletRef? tuplet;   // Reference to tuplet group if applicable
}

class TupletRef {
  final TupletId id;
  final int actual;          // e.g., 3 (in 3:2)
  final int normal;          // e.g., 2 (in 3:2)
}

enum NoteValue { whole, half, quarter, eighth, sixteenth, thirtySecond, sixtyFourth }
```

Two durations per note:
- `WrittenDuration` = rhythmic spelling (dotted quarter in 3:2 tuplet)
- `TickDuration` (int) = actual playback length in ticks

### Core Elements

```dart
class Note {
  final NoteId id;
  final NotatedPitch pitch;           // Includes accidental display
  final PlaybackPitch playbackPitch;
  final WrittenDuration written;      // Rhythmic spelling
  final TickPosition playbackDuration; // Actual ticks
  final int voice;
  final int staff;
  final int velocity;
  final List<Articulation> articulations;
  final TieId? tieStart;
  final TieId? tieEnd;
}

class Chord {
  final ChordId id;
  final List<NotatedPitch> pitches;   // Multiple notes, shared duration
  final WrittenDuration written;
  final TickPosition playbackDuration;
  final int voice;
  final int staff;
}

class Measure {
  final MeasureId id;
  final int number;
  final TickPosition startTick;
  final TickPosition duration;
  final TimeSignature? timeSignature;  // Only if changed
  final KeySignature? keySignature;    // Only if changed
  final List<Segment> segments;
  final Set<MeasureId> dirtyFlags;     // For incremental layout
}

class Segment {
  final TickPosition tick;
  final Map<VoiceId, VoiceSlice> voices;  // Sparse: not all voices populated
}

class VoiceSlice {
  final List<NoteLike> elements;  // Notes, chords, rests, grace groups
}

// NoteLike = Note | Chord | Rest | GraceGroup
// VoiceSlice keeps the segment from becoming a "semantic junk drawer"
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

// Cache key for layout memoization
class LayoutCacheKey {
  final int scoreRevision;
  final LayoutConstraints constraints;
}
```

### Granular Invalidation

For responsive editing on large scores:

```dart
class IncrementalLayoutEngine implements LayoutEngine {
  final Set<MeasureId> _dirtyMeasures = {};
  LayoutResult? _cached;

  void markDirty(MeasureId id) => _dirtyMeasures.add(id);

  LayoutResult layout(Score score, LayoutConstraints c) {
    if (_cached != null && _dirtyMeasures.isEmpty) return _cached!;

    // Only recompute affected measures
    // Propagate to system boundaries if width changes
    return _incrementalLayout(score, c, _dirtyMeasures);
  }
}
```

This keeps mobile responsive during drag operations.

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

- Use **wall-clock deltas** for tick calculation (never increment ticks in a periodic timer)
- Pre-compute MIDI events before playback starts
- Tempo changes are stored in Score.tempos, not playback state

```dart
// CORRECT: Wall-clock based timing
final startTime = DateTime.now();
final startTick = _currentTick;

ticker.tick((elapsed) {
  final elapsedMs = elapsed.inMilliseconds;
  final tick = startTick + (elapsedMs / msPerTick).floor();
  _positionController.add(tick);
  _fireEventsUpTo(tick);
});

// WRONG: Timer-based incrementing (will drift)
// Timer.periodic(duration, (_) { _currentTick++; });  // DON'T DO THIS
```

Wall-clock timing ensures:
- Cursor stays aligned with audio
- Seeking is accurate
- Tempo changes are smooth

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

## Layer 7: Selection & Editing

Selection is **UI state only** - it never affects the score directly.

### Selection Model

```dart
class Selection {
  final Set<ElementId> notes;
  final Set<SpannerId> spanners;
  final SelectionRange? range;  // Optional tick range for region selection
}

class SelectionRange {
  final TickPosition startTick;
  final TickPosition endTick;
  final int? staff;  // null = all staves
}
```

### Selection Rules

- Selection is **ephemeral UI state**, not part of the score
- Commands operate on IDs extracted from selection
- Multi-note edits produce `CompoundCommand`
- Clearing selection does not undo changes

### Hit Testing

Uses `LayoutResult.elementBounds` and `hitTest()`:

```dart
void onTapDown(TapDownDetails details) {
  final hitId = layout.hitTest(details.localPosition);
  if (hitId != null) {
    selection.toggle(hitId);
  } else {
    selection.clear();
  }
}
```

### Drag Operations

Dragging follows a preview → commit pattern:

```dart
// During drag: preview only (no score mutation)
void onDragUpdate(DragUpdateDetails details) {
  final newPitch = layout.yToPitch(details.localPosition.dy, staff, clef);
  _previewOverlay.show(selectedNote, newPitch);  // Visual feedback only
}

// On drag end: commit via Command
void onDragEnd(DragEndDetails details) {
  final newPitch = layout.yToPitch(details.localPosition.dy, staff, clef);
  final cmd = ChangePitchCommand(noteId: selectedNote, newPitch: newPitch);
  commandHistory.execute(cmd, score);
  _previewOverlay.hide();
}
```

### Key Invariant

> **Selection is never undoable. Only score mutations are undoable.**

Dragging, selecting, and deselecting do not create commands. Only the final commit does.

---

## Layer 8: Persistence

Persistence is **command-based**, not snapshot-based.

### Storage Model

```dart
class ScoreDocument {
  final ScoreId id;
  final ScoreMetadata metadata;
  final List<SerializedCommand> commandLog;  // Full history
  final Score? snapshot;                      // Optional checkpoint
  final int snapshotRevision;                 // Revision at snapshot
}

class SerializedCommand {
  final String type;           // "AddNote", "AddSlur", etc.
  final Map<String, dynamic> payload;
  final DateTime timestamp;
  final String? authorId;      // For collaboration
}
```

### Why Command Log > Score Snapshot

Saving commands instead of (or alongside) score state enables:
- **Versioning**: Roll back to any point
- **Recovery**: Reconstruct from partial corruption
- **Collaboration**: Merge concurrent edits
- **AI editing history**: Track what was human vs generated
- **Debugging**: Replay to reproduce bugs

### Rebuild Strategy

```dart
Score rebuildFromLog(List<SerializedCommand> log, {Score? fromSnapshot}) {
  var score = fromSnapshot ?? Score.empty();
  for (final cmd in log.skip(fromSnapshot != null ? snapshotRevision : 0)) {
    final command = deserializeCommand(cmd);
    command.apply(score);
  }
  return score;
}
```

### Snapshot Frequency

Take snapshots periodically (every N commands or on save) for fast load:
- Load snapshot
- Apply commands since snapshot
- Result: full score in milliseconds even with thousands of edits

### Key Invariant

> **Commands are the source of truth. Snapshots are optimization.**

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
3. **Commands return created IDs** - for follow-up operations and UI selection
4. **Layout is derived, never stored** - the score knows ticks, not pixels
5. **Playback reads, never writes** - no playback-induced state corruption
6. **Musical time (ticks) is authoritative** - visual position is computed
7. **Selection is UI state only** - not undoable, not persisted
8. **Undo is free** - because all mutations are reversible Commands
9. **Wall-clock timing for playback** - never increment ticks in a timer
10. **Commands are source of truth** - snapshots are optimization for load speed
11. **Three-way pitch representation** - Pitch (semantic) + NotatedPitch (display) + PlaybackPitch (MIDI)
12. **Two-way duration representation** - WrittenDuration (notation) + TickDuration (playback)
