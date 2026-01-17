// Core type aliases for MNote
//
// All entity IDs use UUID v7 format for:
// - Chronological ordering (useful for command logs)
// - No coordination needed between devices
// - Collaboration-safe

typedef EntityId = String;

typedef ScoreId = EntityId;
typedef PartId = EntityId;
typedef MeasureId = EntityId;

typedef NoteId = EntityId;
typedef ChordId = EntityId;
typedef RestId = EntityId;
typedef GraceGroupId = EntityId;

typedef SlurId = EntityId;
typedef TieId = EntityId;
typedef TupletId = EntityId;

/// Voice identifier (1–4 per staff, sparse)
typedef VoiceId = int;

/// Tick position in the score (absolute, not measure-relative)
/// 480 ticks per quarter note
typedef TickPosition = int;

/// Tick duration (playback time)
typedef TickDuration = int;

/// Divisions per quarter note (industry standard)
const int ticksPerQuarter = 480;
