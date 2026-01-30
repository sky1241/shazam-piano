part of '../practice_page.dart';

/// Mixin for video initialization, disposal, and playback control.
/// Extracted from _PracticePageState to reduce file size.
mixin _PracticeVideoLogicMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  void _resanitizeNoteEventsForVideoDuration();
  Future<void> _stopPractice({bool showSummary, String reason});
  double? _guidanceElapsedSec(); // SESSION-052: For delayed mic stop calculation

  // ══════════════════════════════════════════════════════════════════════════
  // SESSION-052: Delayed mic stop - keep processing until last note window expires
  // ══════════════════════════════════════════════════════════════════════════

  /// Safety padding added to processingEndSec (in seconds).
  /// Ensures mic stays active a bit longer to catch late detections.
  static const double _micStopSafetyPadSec = 0.35;

  /// Calculate the time until all note windows have expired.
  /// Returns the required processing end time in elapsed seconds.
  double _computeProcessingEndSec() {
    if (_noteEvents.isEmpty) return 0.0;

    // Find the latest note window end
    double maxWindowEnd = 0.0;
    for (final note in _noteEvents) {
      final windowEnd = note.end + _targetWindowTailSec;
      if (windowEnd > maxWindowEnd) {
        maxWindowEnd = windowEnd;
      }
    }

    // Add safety padding
    return maxWindowEnd + _micStopSafetyPadSec;
  }

  // ignore: unused_element (called from _PracticeLifecycleMixin)
  void _showVideoNotReadyHint() {
    if (!mounted) return;
    // BUG FIX #14: Message plus précis selon ce qui manque
    String message;
    if (_notesLoading) {
      message = 'Notes en cours de chargement, reessaye dans un instant.';
    } else if (_noteEvents.isEmpty) {
      message = 'Notes indisponibles pour ce niveau.';
    } else if (_videoLoading) {
      message = 'Video en cours de chargement, reessaye dans un instant.';
    } else {
      message = 'Chargement en cours, reessaye dans un instant.';
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ignore: unused_element, unused_element_parameter (called from _PracticeLifecycleMixin)
  Future<void> _startPracticeVideo({Duration? startPosition}) async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    try {
      // CRITICAL FIX: Always start from t=0, ignore any non-zero startPosition
      // (unintended auto-start was passing controller.value.position, causing mid-screen spawn)
      final target = Duration.zero;
      await controller.seekTo(target);
      // FEATURE A: Don't play immediately; wait for countdown to finish
      // Play is triggered in _updateCountdown()
    } catch (_) {}
  }

  // ignore: unused_element (called from _PracticeLifecycleMixin, _PracticeUiVideoMixin)
  Future<void> _initVideo() async {
    // Token guard against double concurrent init
    final token = ++_videoInitToken;

    try {
      await _disposeVideoControllers();
      _videoEndFired = false;

      // Check token again after async gap
      if (token != _videoInitToken) {
        return; // Another init started, abort this one
      }

      setState(() {
        _videoLoading = true;
        _videoError = null;
      });

      final previewUrl = widget.level.previewUrl;
      final fullUrl = widget.level.videoUrl;
      String selectedUrl;

      // BUG 2 FIX: Use the variant that was selected in preview, or fall back to logic
      if (widget.forcePreview) {
        // Always use preview if forced
        if (previewUrl.isEmpty) {
          setState(() {
            _videoError = 'Aucun aperçu disponible';
            _videoLoading = false;
          });
          return;
        }
        selectedUrl = previewUrl;
        _selectedVideoVariant = 'preview';
      } else if (_selectedVideoVariant == 'preview') {
        // User explicitly chose preview in preview mode - stick with it
        if (previewUrl.isEmpty) {
          // Fallback to full if preview no longer available
          selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
          _selectedVideoVariant = 'full';
        } else {
          selectedUrl = previewUrl;
        }
      } else if (_selectedVideoVariant == 'full') {
        // User explicitly chose full in preview mode - stick with it
        selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
      } else {
        // First time in practice: default to full, fallback to preview if needed
        selectedUrl = fullUrl.isNotEmpty ? fullUrl : previewUrl;
        _selectedVideoVariant = fullUrl.isNotEmpty ? 'full' : 'preview';
      }

      final url = _resolveBackendUrl(selectedUrl);
      if (url.isEmpty) {
        setState(() {
          _videoError = 'Aucune video';
          _videoLoading = false;
        });
        return;
      }

      _videoController = VideoPlayerController.networkUrl(Uri.parse(url));
      await _videoController!.initialize();
      _videoController!.setLooping(false);
      await _videoController!.pause();
      final duration = _videoController!.value.duration;
      _videoDurationSec = duration > Duration.zero
          ? duration.inMilliseconds / 1000.0
          : null;
      _videoListener = () {
        if (_videoController == null) return;
        final value = _videoController!.value;
        if (!value.isInitialized || value.duration == Duration.zero) {
          return;
        }
        if (_videoEndFired) {
          // FIX BUG SESSION-005 #5: Force pause if video loops despite setLooping(false)
          // Some Android video_player versions ignore looping=false
          if (value.isPlaying) {
            _videoController?.pause();
          }
          return;
        }
        if (_practiceRunning && isVideoEnded(value.position, value.duration)) {
          _videoEndFired = true;
          // FIX BUG SESSION-005 #5: Force pause immediately to prevent visual respawn
          _videoController?.pause();

          // ════════════════════════════════════════════════════════════════════
          // SESSION-052: Delay mic stop until all note windows have expired
          // This ensures the last note can still be detected even if video ends early
          // ════════════════════════════════════════════════════════════════════
          final elapsedNow = _guidanceElapsedSec() ?? 0.0;
          final processingEndSec = _computeProcessingEndSec();
          final delayMs = ((processingEndSec - elapsedNow) * 1000).clamp(0, 2000).toInt();

          if (kDebugMode) {
            debugPrint(
              'STOP_SCHEDULE videoEnd elapsed=${elapsedNow.toStringAsFixed(2)} '
              'processingEnd=${processingEndSec.toStringAsFixed(2)} delayMs=$delayMs',
            );
          }

          if (delayMs > 50) {
            // Delay stop to allow last note detection
            Future.delayed(Duration(milliseconds: delayMs), () {
              if (mounted && _videoEndFired) {
                if (kDebugMode) {
                  debugPrint('AUDIO_STOP delayed=$delayMs ms');
                }
                unawaited(_stopPractice(showSummary: true, reason: 'video_end'));
              }
            });
          } else {
            // No delay needed, stop immediately
            unawaited(_stopPractice(showSummary: true, reason: 'video_end'));
          }
        }
      };
      // C4: Track listener attachment for debugging
      _listenerAttachCount += 1;
      _videoController!.addListener(_videoListener!);
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        showControls: false,
        // PATCH: Disable center play button to prevent dual entrypoint
        // Users must use AppBar _togglePractice() only for consistent state
        aspectRatio: _videoController!.value.aspectRatio == 0
            ? 16 / 9
            : _videoController!.value.aspectRatio,
      );
      _resanitizeNoteEventsForVideoDuration();

      setState(() {
        _videoLoading = false;
      });
    } catch (e) {
      setState(() {
        _videoError = 'Erreur video: $e';
        _videoLoading = false;
      });
    }
  }

  Future<void> _disposeVideoControllers() async {
    _chewieController?.dispose();
    _chewieController = null;
    if (_videoListener != null && _videoController != null) {
      _videoController!.removeListener(_videoListener!);
    }
    _videoListener = null;
    _videoController?.dispose();
    _videoController = null;
    _videoDurationSec = null;
  }

  String _resolveBackendUrl(String url) {
    if (url.isEmpty) return url;
    if (url.startsWith('http')) return url;
    final baseRaw = AppConstants.backendBaseUrl.trim();
    final base = baseRaw.isEmpty ? 'http://127.0.0.1:8000' : baseRaw;
    final baseWithSlash = base.endsWith('/') ? base : '$base/';
    final cleaned = url.startsWith('/') ? url.substring(1) : url;
    return Uri.parse(baseWithSlash).resolve(cleaned).toString();
  }
}
