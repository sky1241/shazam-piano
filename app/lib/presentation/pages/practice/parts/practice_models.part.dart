part of '../practice_page.dart';

class _DiagTarget {
  final String label;
  final String url;

  const _DiagTarget(this.label, this.url);
}

class _DiagResult {
  final String label;
  final String url;
  final int? statusCode;
  final String method;
  final String? error;

  const _DiagResult({
    required this.label,
    required this.url,
    this.statusCode,
    required this.method,
    this.error,
  });

  factory _DiagResult.missing(String label) {
    return _DiagResult(label: label, url: '', method: 'N/A', error: 'missing');
  }

  String get _safeUrl {
    if (url.isEmpty) return url;
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      return url;
    }
    return parsed.replace(query: '', fragment: '').toString();
  }

  String get summary {
    if (statusCode != null) {
      final ok = statusCode! >= 200 && statusCode! < 300;
      final tag = ok ? 'OK' : 'HTTP $statusCode';
      return '$label: $tag ($method) $_safeUrl';
    }
    final detail = error ?? 'error';
    return '$label: $detail ($method) $_safeUrl';
  }
}

class _NoteEvent {
  final int pitch;
  final double start;
  final double end;
  _NoteEvent({required this.pitch, required this.start, required this.end});
}

class _NormalizedNotes {
  final List<_NoteEvent> events;
  final int totalCount;
  final int dedupedCount;
  final int filteredCount;

  const _NormalizedNotes({
    required this.events,
    required this.totalCount,
    required this.dedupedCount,
    required this.filteredCount,
  });
}

class _SanitizedNotes {
  final List<_NoteEvent> events;
  final int displayFirstKey;
  final int displayLastKey;
  final int droppedOutOfVideo;
  final int droppedDup;

  const _SanitizedNotes({
    required this.events,
    required this.displayFirstKey,
    required this.displayLastKey,
    required this.droppedOutOfVideo,
    required this.droppedDup,
  });
}

class _KeyboardLayout {
  final double whiteWidth;
  final double blackWidth;
  final double displayWidth;
  final double outerWidth;
  final double stagePadding;
  final bool shouldScroll;
  final double leftPadding;
  final int firstKey;
  final int lastKey;
  final List<int> blackKeys;

  const _KeyboardLayout({
    required this.whiteWidth,
    required this.blackWidth,
    required this.displayWidth,
    required this.outerWidth,
    required this.stagePadding,
    required this.shouldScroll,
    required this.leftPadding,
    required this.firstKey,
    required this.lastKey,
    required this.blackKeys,
  });

  double noteToX(int note) {
    return PracticeKeyboard.noteToX(
      note: note,
      firstKey: firstKey,
      whiteWidth: whiteWidth,
      blackWidth: blackWidth,
      blackKeys: blackKeys,
      offset: leftPadding,
    );
  }
}
