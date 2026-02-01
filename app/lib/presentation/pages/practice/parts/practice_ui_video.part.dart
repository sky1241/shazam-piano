part of '../practice_page.dart';

/// Mixin for video player and notes overlay UI widgets.
/// Extracted from _PracticePageState to reduce file size.
///
/// SESSION-056: Legacy flash methods removed - S56 UIFeedbackEngine handles all feedback.
mixin _PracticeUiVideoMixin on _PracticePageStateBase {
  // Abstract method that must be implemented by the class using this mixin
  Future<void> _initVideo();

  Widget _wrapPracticeVideo(Widget child) {
    return KeyedSubtree(key: const Key('practice_video'), child: child);
  }

  Widget _buildCroppedVideoLayer({
    required Widget child,
    required double aspectRatio,
  }) {
    final safeAspect = aspectRatio > 0 ? aspectRatio : 16 / 9;
    const baseWidth = 1000.0;
    final baseHeight = baseWidth / safeAspect;

    return FittedBox(
      fit: BoxFit.cover,
      alignment: Alignment.topCenter,
      child: ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: _videoCropFactor,
          child: SizedBox(width: baseWidth, height: baseHeight, child: child),
        ),
      ),
    );
  }

  // ignore: unused_element (called from _PracticeUiStageMixin)
  Widget _buildVideoPlayer({
    required _KeyboardLayout layout,
    required Set<int> targetNotes,
    required double? elapsedSec,
  }) {
    return _wrapPracticeVideo(
      LayoutBuilder(
        builder: (context, constraints) {
          final aspectRatio = _chewieController?.aspectRatio ?? 16 / 9;
          final videoLayer = _buildCroppedVideoLayer(
            aspectRatio: aspectRatio,
            child: _buildVideoContent(),
          );
          assert(() {
            if (_overlayBuiltInBuild) {
              debugPrint(
                'Practice overlay built more than once in a build pass',
              );
            }
            _overlayBuiltInBuild = true;
            return true;
          }());
          // Now constraints.maxHeight is stable (bottomNavigationBar always present as 50px spacer)
          final overlay = _buildNotesOverlay(
            layout: layout,
            overlayHeight: constraints.maxHeight,
            targetNotes: targetNotes,
            elapsedSec: elapsedSec,
          );
          // PATCH: Hide video layer permanently + show only Flutter overlay
          // Chewie continues running for timing, but is opacity=0 to prevent "two streams"
          // All visual notes come from _FallingNotesPainter only
          // FIX BUG 1: Use SizedBox with explicit dimensions instead of Positioned.fill
          // to respect CustomPaint.size (otherwise Stack collapses canvas to parent height)
          final stack = Stack(
            children: [
              // Opacity 0: video runs for timing/audio but isn't visible
              Positioned.fill(child: Opacity(opacity: 0.0, child: videoLayer)),
              // Paint overlay during countdown + running (notes visible during lead-in)
              // FIX: Wrap overlay in SizedBox matching constraints.maxHeight (now stable)
              if (_practiceRunning ||
                  _practiceState == _PracticeState.countdown)
                SizedBox(
                  width: layout.displayWidth,
                  height: constraints.maxHeight,
                  child: overlay,
                ),
              // Render empty overlay container for key when not in countdown/running
              if (!(_practiceRunning ||
                  _practiceState == _PracticeState.countdown))
                const KeyedSubtree(
                  key: Key('practice_notes_overlay'),
                  child: SizedBox.expand(),
                ),
            ],
          );
          final stage = SizedBox(
            width: layout.outerWidth,
            height: constraints.maxHeight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: layout.stagePadding),
              child: stack,
            ),
          );
          final aligned = layout.shouldScroll
              ? Align(alignment: Alignment.centerLeft, child: stage)
              : Align(alignment: Alignment.center, child: stage);
          return ClipRect(child: aligned);
        },
      ),
    );
  }

  Widget _buildVideoContent() {
    if (_isTestEnv) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text(
          'Video placeholder',
          style: TextStyle(color: Colors.white),
        ),
      );
    }
    if (_videoError != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppConstants.spacing12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _videoError!,
              style: AppTextStyles.caption.copyWith(color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing8),
            TextButton(onPressed: _initVideo, child: const Text('Reessayer')),
          ],
        ),
      );
    }
    if (_videoLoading || _chewieController == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(),
      );
    }
    return Chewie(controller: _chewieController!);
  }

  Widget _buildNotesOverlay({
    required _KeyboardLayout layout,
    required double overlayHeight,
    required Set<int> targetNotes,
    required double? elapsedSec,
  }) {
    // C4: Track overlay build count for debugging
    _overlayBuildCount += 1;

    // SESSION-056: Legacy flash removed - S56 UIFeedbackEngine handles keyboard feedback
    // Falling notes painter no longer needs flash states
    final elapsed = elapsedSec;
    // BUG FIX #9: Must paint notes during COUNTDOWN to allow falling animation
    // Notes need to spawn offscreen (spawnY < 0) and fall during countdown
    // Previous condition blocked countdown rendering, causing "notes pop mid-screen" bug
    // FIX BUG 4: Wait 100ms after countdown start for layout to stabilize
    // Prevents notes appearing "en bas" with incorrect overlayHeight
    // FIX BUG SESSION-007 #4: Also check !_videoEndFired to prevent notes respawning after session end
    final shouldPaintNotes =
        (_practiceRunning || _practiceState == _PracticeState.countdown) &&
        !_videoEndFired && // SESSION-007: Block painting after video ends
        elapsed != null &&
        _noteEvents.isNotEmpty &&
        _isLayoutStable(); // Only paint when layout is stable
    final paintElapsedSec = elapsed ?? 0.0;
    final resolvedTargets = shouldPaintNotes ? targetNotes : <int>{};
    var noteEvents = shouldPaintNotes ? _noteEvents : const <_NoteEvent>[];

    // D2: Debug log to track note spawning during countdown
    if (kDebugMode &&
        _practiceState == _PracticeState.countdown &&
        shouldPaintNotes &&
        _noteEvents.isNotEmpty) {
      if (_spawnLogCount < 3) {
        // Log only first 3 frames to avoid spam
        _spawnLogCount++;
        final firstNote = _noteEvents.first;
        final effectiveFallForLog =
            _effectiveLeadInSec; // Use effective lead during countdown
        final spawnTimeTheoreticalSec = firstNote.start - effectiveFallForLog;
        final yTop =
            (paintElapsedSec - spawnTimeTheoreticalSec) /
            effectiveFallForLog *
            overlayHeight;
        final yBottom =
            (paintElapsedSec - (firstNote.end - effectiveFallForLog)) /
            effectiveFallForLog *
            overlayHeight;
        debugPrint(
          'SPAWN note midi=${firstNote.pitch} at guidanceElapsed=${paintElapsedSec.toStringAsFixed(3)} '
          'yTop=${yTop.toStringAsFixed(1)} yBottom=${yBottom.toStringAsFixed(1)} '
          'noteStart=${firstNote.start.toStringAsFixed(3)} spawnAt=${spawnTimeTheoreticalSec.toStringAsFixed(3)}',
        );
      }
    }

    // 4) Debug toggle: show only target notes (ghost test isolation)
    if (_showOnlyTargets && shouldPaintNotes) {
      noteEvents = noteEvents
          .where((n) => resolvedTargets.contains(n.pitch))
          .toList();
    }

    final scrollOffset = layout.shouldScroll ? _keyboardScrollOffset : 0.0;
    final showGuides = kDebugMode && _showKeyboardGuides;
    final baseNoteToX = layout.noteToX;
    double noteToX(int note) => baseNoteToX(note) - scrollOffset;

    // C4: Track painter instance for debugging duplicate overlays
    _painterInstanceId += 1;

    // FIX BUG 2: Always use constant fallLead to prevent visual jump at countdown→running transition
    // Previous: Used _effectiveLeadInSec (3.0s) during countdown, _fallLeadSec (2.0s) during running
    // Problem: When transitioning, all note Y positions suddenly shifted (3.0→2.0 ratio change)
    // Solution: Use constant _fallLeadSec (2.0s) for both states - notes fall at consistent speed
    final effectiveFallLead = _fallLeadSec;

    // ══════════════════════════════════════════════════════════════════════════
    // LOI V3: Stocker les paramètres du painter pour le JUGE
    // Ces valeurs sont utilisées pour calculer quand la dernière note sort de l'écran
    // MUST be identical to values passed to _FallingNotesPainter
    // ══════════════════════════════════════════════════════════════════════════
    _judgeFallAreaHeight = overlayHeight;
    _judgeFallLeadSec = effectiveFallLead;

    // SESSION-056: Pass neutral values - S56 handles all visual feedback on keyboard
    // Falling notes only show bars, no flash feedback needed
    return IgnorePointer(
      child: CustomPaint(
        key: const Key('practice_notes_overlay'),
        size: Size(layout.displayWidth, overlayHeight),
        painter: _FallingNotesPainter(
          noteEvents: noteEvents,
          elapsedSec: paintElapsedSec,
          whiteWidth: layout.whiteWidth,
          blackWidth: layout.blackWidth,
          fallAreaHeight: overlayHeight,
          fallLead: effectiveFallLead,
          fallTail: _fallTailSec,
          noteToX: noteToX,
          firstKey: layout.firstKey,
          lastKey: layout.lastKey,
          targetNotes: resolvedTargets,
          successNote: null, // S56: flash handled by UIFeedbackEngine
          successNoteIndex: null,
          successFlashActive: false,
          wrongNote: null,
          wrongFlashActive: false,
          forceLabels: true,
          showGuides: showGuides,
          showMidiNumbers: _showMidiNumbers,
        ),
      ),
    );
  }
}
