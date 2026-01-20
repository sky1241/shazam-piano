part of '../practice_page.dart';

_NormalizedNotes _normalizeEventsInternal({
  required List<_NoteEvent> events,
  required int firstKey,
  required int lastKey,
  required double epsilonSec,
}) {
  final totalCount = events.length;
  if (events.isEmpty) {
    return const _NormalizedNotes(
      events: [],
      totalCount: 0,
      dedupedCount: 0,
      filteredCount: 0,
    );
  }
  final sorted = List<_NoteEvent>.from(events)
    ..sort((a, b) {
      final startCmp = a.start.compareTo(b.start);
      if (startCmp != 0) {
        return startCmp;
      }
      final pitchCmp = a.pitch.compareTo(b.pitch);
      if (pitchCmp != 0) {
        return pitchCmp;
      }
      return a.end.compareTo(b.end);
    });

  final deduped = <_NoteEvent>[];
  _NoteEvent? previous;
  for (final note in sorted) {
    if (previous != null &&
        note.pitch == previous.pitch &&
        (note.start - previous.start).abs() <= epsilonSec &&
        (note.end - previous.end).abs() <= epsilonSec) {
      continue;
    }
    deduped.add(note);
    previous = note;
  }

  final filtered = <_NoteEvent>[];
  for (final note in deduped) {
    if (note.pitch < firstKey || note.pitch > lastKey) {
      continue;
    }
    filtered.add(note);
  }

  return _NormalizedNotes(
    events: filtered,
    totalCount: totalCount,
    dedupedCount: deduped.length,
    filteredCount: filtered.length,
  );
}
