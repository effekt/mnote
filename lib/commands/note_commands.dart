// Note-related commands for MNote

import '../core/core.dart';
import 'command.dart';

/// Add a note to the score
class AddNoteCommand implements Command {
  final NoteId noteId;
  final MeasureId measureId;
  final TickPosition tick;
  final VoiceId voice;
  final NotatedPitch pitch;
  final PlaybackPitch playbackPitch;
  final WrittenDuration written;
  final TickDuration playbackDuration;
  final int staff;
  final int velocity;
  final List<Articulation> articulations;

  AddNoteCommand({
    required this.noteId,
    required this.measureId,
    required this.tick,
    required this.voice,
    required this.pitch,
    required this.playbackPitch,
    required this.written,
    required this.playbackDuration,
    required this.staff,
    this.velocity = 80,
    this.articulations = const [],
  });

  @override
  CommandResult apply(MutableScore score) {
    final note = Note(
      id: noteId,
      pitch: pitch,
      playbackPitch: playbackPitch,
      written: written,
      playbackDuration: playbackDuration,
      voice: voice,
      staff: staff,
      velocity: velocity,
      articulations: articulations,
    );

    score.addNote(measureId, tick, voice, note);
    return CommandResult.success({'noteId': noteId});
  }

  @override
  void revert(MutableScore score) {
    score.removeNote(noteId);
  }

  @override
  String get description => 'Add note ${pitch.pitch}';

  @override
  String get type => 'AddNote';

  @override
  Map<String, dynamic> toJson() => {
        'noteId': noteId,
        'measureId': measureId,
        'tick': tick,
        'voice': voice,
        'pitch': {
          'step': pitch.pitch.step.name,
          'alter': pitch.pitch.alter,
          'octave': pitch.pitch.octave,
          'display': pitch.display.name,
        },
        'playbackPitch': {
          'midiPitch': playbackPitch.midiPitch,
          'cents': playbackPitch.cents,
        },
        'written': {
          'base': written.base.name,
          'dots': written.dots,
          'tuplet': written.tuplet != null
              ? {
                  'id': written.tuplet!.id,
                  'actual': written.tuplet!.actual,
                  'normal': written.tuplet!.normal,
                }
              : null,
        },
        'playbackDuration': playbackDuration,
        'staff': staff,
        'velocity': velocity,
        'articulations': articulations.map((a) => a.name).toList(),
      };
}

/// Remove a note from the score
class RemoveNoteCommand implements Command {
  final NoteId noteId;

  // Stored for revert
  Note? _removedNote;
  MeasureId? _measureId;
  TickPosition? _tick;

  RemoveNoteCommand({required this.noteId});

  @override
  CommandResult apply(MutableScore score) {
    // TODO: Store note data before removing for revert
    score.removeNote(noteId);
    return const CommandResult.success();
  }

  @override
  void revert(MutableScore score) {
    if (_removedNote != null && _measureId != null && _tick != null) {
      score.addNote(_measureId!, _tick!, _removedNote!.voice, _removedNote!);
    }
  }

  @override
  String get description => 'Remove note';

  @override
  String get type => 'RemoveNote';

  @override
  Map<String, dynamic> toJson() => {'noteId': noteId};
}

/// Change pitch of a note
class ChangePitchCommand implements Command {
  final NoteId noteId;
  final NotatedPitch newPitch;
  final PlaybackPitch newPlaybackPitch;

  // Stored for revert
  NotatedPitch? _oldPitch;
  PlaybackPitch? _oldPlaybackPitch;

  ChangePitchCommand({
    required this.noteId,
    required this.newPitch,
    required this.newPlaybackPitch,
  });

  @override
  CommandResult apply(MutableScore score) {
    // TODO: Store old pitch, apply new pitch
    return const CommandResult.success();
  }

  @override
  void revert(MutableScore score) {
    // TODO: Restore old pitch
  }

  @override
  String get description => 'Change pitch to ${newPitch.pitch}';

  @override
  String get type => 'ChangePitch';

  @override
  Map<String, dynamic> toJson() => {
        'noteId': noteId,
        'newPitch': {
          'step': newPitch.pitch.step.name,
          'alter': newPitch.pitch.alter,
          'octave': newPitch.pitch.octave,
          'display': newPitch.display.name,
        },
        'newPlaybackPitch': {
          'midiPitch': newPlaybackPitch.midiPitch,
          'cents': newPlaybackPitch.cents,
        },
      };
}
