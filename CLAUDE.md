# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MNote is a Flutter-based music notation app for composing and transcribing music on tablets/phones. Users draw music notation, the app interprets it, and plays it back with various instruments.

## Architecture

See `docs/plans/2026-01-17-architecture-design.md` for the complete design.

**Core principle:** "The sheet is a spatial index. The music lives in a semantic model."

**Layer separation:**
- Input (Flutter) → Interpretation (Pure Dart) → Commands → Music Model → Layout → Playback
- Interpretation never mutates the score directly
- All mutations go through reversible Commands
- Layout is always derived from ticks, never stored

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
3. **Layout is derived, never stored** - the score knows ticks, not pixels
4. **Playback reads, never writes** - no playback-induced state corruption
5. **480 ticks per quarter note** - industry standard timing

## Code Organization

```
lib/
├── core/              # Music model (Score, Note, Measure, etc.)
├── interpretation/    # Stroke classification, gesture grammar
├── commands/          # Reversible score mutations
├── layout/            # Tick → pixel conversion
├── playback/          # MIDI event generation, cursor sync
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
