// Layout engine interface for MNote
//
// Converts musical time (ticks) to visual coordinates.
// Layout is always derived, never stored in the score.

import 'dart:ui';
import '../core/core.dart';

/// Layout constraints for rendering
class LayoutConstraints {
  final double pageWidth;
  final double staffHeight;
  final double systemSpacing;
  final double measureMinWidth;
  final double measureMaxWidth;
  final int measuresPerSystem; // Hint, can be overridden

  const LayoutConstraints({
    required this.pageWidth,
    this.staffHeight = 40.0,
    this.systemSpacing = 60.0,
    this.measureMinWidth = 80.0,
    this.measureMaxWidth = 300.0,
    this.measuresPerSystem = 4,
  });
}

/// Cache key for layout memoization
class LayoutCacheKey {
  final int scoreRevision;
  final LayoutConstraints constraints;

  const LayoutCacheKey({
    required this.scoreRevision,
    required this.constraints,
  });

  @override
  bool operator ==(Object other) =>
      other is LayoutCacheKey &&
      scoreRevision == other.scoreRevision &&
      constraints == other.constraints;

  @override
  int get hashCode => Object.hash(scoreRevision, constraints);
}

/// Layout of a single measure
class MeasureLayout {
  final MeasureId id;
  final double x;
  final double width;
  final TickPosition startTick;
  final TickPosition endTick;

  const MeasureLayout({
    required this.id,
    required this.x,
    required this.width,
    required this.startTick,
    required this.endTick,
  });

  /// Convert tick within this measure to X coordinate
  double tickToX(TickPosition tick) {
    if (endTick == startTick) return x;
    final progress = (tick - startTick) / (endTick - startTick);
    return x + (progress * width);
  }

  /// Convert X coordinate to tick within this measure
  TickPosition xToTick(double xPos) {
    if (width == 0) return startTick;
    final progress = (xPos - x) / width;
    return startTick + ((endTick - startTick) * progress).round();
  }
}

/// Layout of a single staff
class StaffLayout {
  final int staffIndex;
  final double y;
  final double lineSpacing;
  final Clef clef;

  const StaffLayout({
    required this.staffIndex,
    required this.y,
    required this.lineSpacing,
    required this.clef,
  });

  /// Convert pitch to Y coordinate
  double pitchToY(Pitch pitch) {
    final staffPosition = _pitchToStaffPosition(pitch);
    // Staff position 0 = bottom line, each increment = half space
    return y + (4 * lineSpacing) - (staffPosition * lineSpacing / 2);
  }

  /// Convert Y coordinate to nearest pitch
  Pitch yToPitch(double yPos) {
    final staffPosition = ((y + 4 * lineSpacing) - yPos) / (lineSpacing / 2);
    return _staffPositionToPitch(staffPosition.round());
  }

  int _pitchToStaffPosition(Pitch pitch) {
    // Treble clef: middle C (C4) is at position -2 (below staff)
    // Each step up = +1, each octave = +7
    const basePositions = {
      PitchStep.C: 0,
      PitchStep.D: 1,
      PitchStep.E: 2,
      PitchStep.F: 3,
      PitchStep.G: 4,
      PitchStep.A: 5,
      PitchStep.B: 6,
    };

    final basePosition = basePositions[pitch.step]!;
    final octaveOffset = (pitch.octave - 4) * 7;

    switch (clef.type) {
      case ClefType.treble:
        return basePosition + octaveOffset - 2; // C4 = -2
      case ClefType.bass:
        return basePosition + octaveOffset + 10; // C4 = 10
      case ClefType.alto:
        return basePosition + octaveOffset + 4; // C4 = 4
      case ClefType.tenor:
        return basePosition + octaveOffset + 6; // C4 = 6
      case ClefType.percussion:
        return 4; // Center line
    }
  }

  Pitch _staffPositionToPitch(int position) {
    // Inverse of _pitchToStaffPosition
    int adjustedPosition;
    switch (clef.type) {
      case ClefType.treble:
        adjustedPosition = position + 2;
      case ClefType.bass:
        adjustedPosition = position - 10;
      case ClefType.alto:
        adjustedPosition = position - 4;
      case ClefType.tenor:
        adjustedPosition = position - 6;
      case ClefType.percussion:
        adjustedPosition = 0;
    }

    final octave = 4 + (adjustedPosition ~/ 7);
    final stepIndex = adjustedPosition % 7;
    final step = PitchStep.values[stepIndex < 0 ? stepIndex + 7 : stepIndex];

    return Pitch(step: step, octave: octave);
  }
}

/// Layout of a system (one or more staves)
class SystemLayout {
  final int systemIndex;
  final double y;
  final double height;
  final List<MeasureLayout> measures;
  final List<StaffLayout> staves;

  const SystemLayout({
    required this.systemIndex,
    required this.y,
    required this.height,
    required this.measures,
    required this.staves,
  });
}

/// Complete layout result
class LayoutResult {
  final List<SystemLayout> systems;
  final Map<EntityId, Rect> elementBounds;

  const LayoutResult({
    required this.systems,
    required this.elementBounds,
  });

  /// Convert tick to visual position
  Offset? tickToPosition(TickPosition tick, int staff) {
    for (final system in systems) {
      for (final measure in system.measures) {
        if (tick >= measure.startTick && tick < measure.endTick) {
          final x = measure.tickToX(tick);
          if (staff < system.staves.length) {
            final y = system.staves[staff].y;
            return Offset(x, y);
          }
        }
      }
    }
    return null;
  }

  /// Convert visual position to tick
  TickPosition? positionToTick(Offset pos, int staff) {
    for (final system in systems) {
      for (final measure in system.measures) {
        if (pos.dx >= measure.x && pos.dx < measure.x + measure.width) {
          return measure.xToTick(pos.dx);
        }
      }
    }
    return null;
  }

  /// Hit test for element at position
  EntityId? hitTest(Offset pos) {
    for (final entry in elementBounds.entries) {
      if (entry.value.contains(pos)) {
        return entry.key;
      }
    }
    return null;
  }
}

/// Abstract layout engine interface
abstract class LayoutEngine {
  LayoutResult layout(Score score, LayoutConstraints constraints);
}

/// Proportional layout engine (MVP implementation)
class ProportionalLayoutEngine implements LayoutEngine {
  @override
  LayoutResult layout(Score score, LayoutConstraints c) {
    final systems = <SystemLayout>[];
    final elementBounds = <EntityId, Rect>{};

    var currentMeasures = <MeasureLayout>[];
    var currentX = 0.0;
    var systemY = 0.0;
    var systemIndex = 0;

    for (final measure in score.measures) {
      final idealWidth = _calculateMeasureWidth(measure, c);

      // Check if measure fits on current system
      if (currentX + idealWidth > c.pageWidth && currentMeasures.isNotEmpty) {
        // Justify current system and start new one
        systems.add(_createSystem(
          currentMeasures,
          c.pageWidth,
          systemY,
          systemIndex,
          c,
        ));
        currentMeasures = [];
        currentX = 0.0;
        systemY += _systemHeight(c) + c.systemSpacing;
        systemIndex++;
      }

      currentMeasures.add(MeasureLayout(
        id: measure.id,
        x: currentX,
        width: idealWidth,
        startTick: measure.startTick,
        endTick: measure.startTick + measure.duration,
      ));
      currentX += idealWidth;
    }

    // Finalize last system
    if (currentMeasures.isNotEmpty) {
      systems.add(_createSystem(
        currentMeasures,
        c.pageWidth,
        systemY,
        systemIndex,
        c,
      ));
    }

    return LayoutResult(systems: systems, elementBounds: elementBounds);
  }

  double _calculateMeasureWidth(Measure m, LayoutConstraints c) {
    // Simple proportional: more segments = wider
    final density = m.segments.length / (m.duration / ticksPerQuarter);
    return (c.measureMinWidth + density * 50)
        .clamp(c.measureMinWidth, c.measureMaxWidth);
  }

  double _systemHeight(LayoutConstraints c) {
    return c.staffHeight * 2 + 20; // Grand staff + spacing
  }

  SystemLayout _createSystem(
    List<MeasureLayout> measures,
    double width,
    double y,
    int index,
    LayoutConstraints c,
  ) {
    // Justify measures to fill width
    final totalWidth = measures.fold(0.0, (sum, m) => sum + m.width);
    final scale = width / totalWidth;

    final justifiedMeasures = <MeasureLayout>[];
    var x = 0.0;
    for (final m in measures) {
      final newWidth = m.width * scale;
      justifiedMeasures.add(MeasureLayout(
        id: m.id,
        x: x,
        width: newWidth,
        startTick: m.startTick,
        endTick: m.endTick,
      ));
      x += newWidth;
    }

    return SystemLayout(
      systemIndex: index,
      y: y,
      height: _systemHeight(c),
      measures: justifiedMeasures,
      staves: [
        StaffLayout(
          staffIndex: 0,
          y: y,
          lineSpacing: c.staffHeight / 4,
          clef: Clef.treble,
        ),
        StaffLayout(
          staffIndex: 1,
          y: y + c.staffHeight + 20,
          lineSpacing: c.staffHeight / 4,
          clef: Clef.bass,
        ),
      ],
    );
  }
}

/// Incremental layout engine with dirty tracking
class IncrementalLayoutEngine implements LayoutEngine {
  final Set<MeasureId> _dirtyMeasures = {};
  LayoutResult? _cached;
  int _cachedRevision = -1;

  void markDirty(MeasureId id) => _dirtyMeasures.add(id);

  void invalidateAll() {
    _cached = null;
    _dirtyMeasures.clear();
  }

  @override
  LayoutResult layout(Score score, LayoutConstraints c) {
    // For now, just use proportional layout
    // TODO: Implement incremental updates
    if (_cached != null && _dirtyMeasures.isEmpty) {
      return _cached!;
    }

    final engine = ProportionalLayoutEngine();
    _cached = engine.layout(score, c);
    _dirtyMeasures.clear();
    return _cached!;
  }
}
