# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MNote is a Flutter-based music notation app for composing and transcribing music on tablets/phones. Users draw music notation, the app interprets it, and plays it back with various instruments.

## Architecture

See `docs/plans/2026-01-17-architecture-design.md` for the complete design.

**Core principle:** "The sheet is a spatial index. The music lives in a semantic model."

**7 Layers:**
1. Input (Flutter) - stylus/touch capture
2. Interpretation (Pure Dart) - stroke → intent
3. Commands - reversible score mutations
4. Music Model - Score, Note, Measure, Segment
5. Layout - tick → pixel conversion
6. Playback - MIDI synthesis, cursor sync
7. Selection - ephemeral UI state

## Commands

```bash
# Run the app
flutter run

# Run tests
flutter test

# Run a single test file
flutter test test/path/to/test.dart

# Analyze code
flutter analyze

# Format code
dart format .
```

## Key Invariants

1. **Interpretation never mutates the score** - only Commands do
2. **Commands reference IDs, not objects** - for serialization safety
3. **Commands return created IDs** - for follow-up operations
4. **Layout is derived, never stored** - the score knows ticks, not pixels
5. **Playback reads, never writes** - no playback-induced state corruption
6. **Selection is UI state only** - not undoable, not persisted
7. **Wall-clock timing for playback** - never increment ticks in a timer
8. **480 ticks per quarter note** - industry standard timing

## Code Organization

```
lib/
├── core/              # Music model (Score, Note, Measure, etc.)
├── interpretation/    # Stroke classification, gesture grammar
├── commands/          # Reversible score mutations
├── layout/            # Tick → pixel conversion
├── playback/          # MIDI event generation, cursor sync
├── selection/         # UI selection state, hit testing
└── ui/                # Flutter widgets, CustomPainter rendering
```

## Dual Pitch Representation

Always maintain both:
- `Pitch` (step, alter, octave) - for notation (preserves C# vs Db)
- `PlaybackPitch` (midiPitch) - for audio

## Testing Strategy

- Unit test interpretation layer with stroke fixtures
- Unit test command apply/revert symmetry
- Unit test layout tick↔position conversions
- Integration test gesture→command→score flow
