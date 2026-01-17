// Command interface for MNote
//
// All score mutations go through Commands.
// Commands are reversible, serializable, and reference IDs (not objects).

import '../core/core.dart';

/// Result of applying a command
class CommandResult {
  final bool success;
  final String? error;
  final Map<String, EntityId> createdIds;

  const CommandResult.success([this.createdIds = const {}])
      : success = true,
        error = null;

  const CommandResult.failure(this.error)
      : success = false,
        createdIds = const {};
}

/// Base interface for all commands
abstract class Command {
  /// Apply the command to the score
  CommandResult apply(MutableScore score);

  /// Revert the command (undo)
  void revert(MutableScore score);

  /// Human-readable description for undo history
  String get description;

  /// Command type for serialization
  String get type;

  /// Serialize to JSON payload
  Map<String, dynamic> toJson();
}

/// Compound command for atomic multi-step operations
class CompoundCommand implements Command {
  final List<Command> commands;
  final String _description;

  CompoundCommand({
    required this.commands,
    required String description,
  }) : _description = description;

  @override
  CommandResult apply(MutableScore score) {
    final allCreatedIds = <String, EntityId>{};

    for (final cmd in commands) {
      final result = cmd.apply(score);
      if (!result.success) {
        // Rollback already-applied commands
        for (final applied in commands.takeWhile((c) => c != cmd).toList().reversed) {
          applied.revert(score);
        }
        return result;
      }
      allCreatedIds.addAll(result.createdIds);
    }

    return CommandResult.success(allCreatedIds);
  }

  @override
  void revert(MutableScore score) {
    for (final cmd in commands.reversed) {
      cmd.revert(score);
    }
  }

  @override
  String get description => _description;

  @override
  String get type => 'CompoundCommand';

  @override
  Map<String, dynamic> toJson() => {
        'commands': commands.map((c) => {'type': c.type, ...c.toJson()}).toList(),
        'description': _description,
      };
}

/// Command history with undo/redo stacks
class CommandHistory {
  final List<Command> _undoStack = [];
  final List<Command> _redoStack = [];
  int _revision = 0;

  int get revision => _revision;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  CommandResult execute(Command cmd, MutableScore score) {
    final result = cmd.apply(score);
    if (result.success) {
      _undoStack.add(cmd);
      _redoStack.clear();
      _revision++;
    }
    return result;
  }

  void undo(MutableScore score) {
    if (_undoStack.isEmpty) return;
    final cmd = _undoStack.removeLast();
    cmd.revert(score);
    _redoStack.add(cmd);
    _revision++;
  }

  void redo(MutableScore score) {
    if (_redoStack.isEmpty) return;
    final cmd = _redoStack.removeLast();
    cmd.apply(score);
    _undoStack.add(cmd);
    _revision++;
  }

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}

/// Mutable score wrapper for command execution
/// The immutable Score is rebuilt after each command
class MutableScore {
  Score _score;

  MutableScore(this._score);

  Score get score => _score;

  // Note operations
  void addNote(MeasureId measureId, TickPosition tick, VoiceId voice, Note note) {
    // Implementation will mutate internal state
    // Then rebuild immutable Score
  }

  void removeNote(NoteId noteId) {
    // Implementation
  }

  // Measure operations
  void addMeasure(Measure measure) {
    // Implementation
  }

  void removeMeasure(MeasureId measureId) {
    // Implementation
  }

  // Spanner operations
  void addSlur(Slur slur) {
    // Implementation
  }

  void removeSlur(SlurId slurId) {
    // Implementation
  }

  void addTie(Tie tie) {
    // Implementation
  }

  void removeTie(TieId tieId) {
    // Implementation
  }
}
