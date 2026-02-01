part of '../practice_page.dart';

/// Mixin for microphone input, permission handling, and audio stream management.
/// Extracted from _PracticePageState to reduce file size.
mixin _PracticeInputLogicMixin on _PracticePageStateBase {
  // Abstract methods that must be implemented by the class using this mixin
  Future<void> _togglePractice();
  void _processSamples(
    List<double> samples, {
    required DateTime now,
    // ignore: unused_element_parameter
    bool injected,
    // ignore: unused_element_parameter
    int? sessionId,
  });
  void _processAudioChunk(Uint8List samples);
  @override
  String _formatMidiNote(int midi, {bool withOctave});

  // ignore: unused_element (called from _PracticeUiStageMixin)
  Future<void> _refreshMicPermission() async {
    try {
      final status = await Permission.microphone.status;
      if (mounted) {
        setState(() {
          _micPermissionStatus = status;
        });
      } else {
        _micPermissionStatus = status;
      }
    } catch (_) {
      // ignore permission errors
    }
  }

  /// Request microphone permission proactively at page startup.
  /// Unlike _ensureMicPermission(), this doesn't show a rationale dialog
  /// to avoid blocking the UI - the rationale will be shown if user taps Play
  /// and permission is still not granted.
  // ignore: unused_element (called from _PracticeLifecycleMixin.initState)
  Future<void> _requestMicPermissionProactive() async {
    if (_isTestEnv) {
      return;
    }
    try {
      final status = await Permission.microphone.status;
      if (kDebugMode) {
        debugPrint('MIC_PERMISSION_PROACTIVE: initial status=$status');
      }
      _setMicPermissionStatus(status);
      if (status.isGranted) {
        if (kDebugMode) {
          debugPrint('MIC_PERMISSION_PROACTIVE: already granted, skipping');
        }
        return;
      }
      if (status.isPermanentlyDenied) {
        if (kDebugMode) {
          debugPrint('MIC_PERMISSION_PROACTIVE: permanently denied, need settings');
        }
        return;
      }
      // Request directly without rationale dialog at startup
      if (kDebugMode) {
        debugPrint('MIC_PERMISSION_PROACTIVE: requesting permission now...');
      }
      final requestStatus = await Permission.microphone.request();
      if (kDebugMode) {
        debugPrint('MIC_PERMISSION_PROACTIVE: request result=$requestStatus');
      }
      _setMicPermissionStatus(requestStatus);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('MIC_PERMISSION_PROACTIVE: error=$e');
      }
    }
  }

  Future<bool> _ensureMicPermission() async {
    if (_isTestEnv) {
      return true;
    }
    PermissionStatus status;
    try {
      status = await Permission.microphone.status;
    } catch (_) {
      return false;
    }
    _setMicPermissionStatus(status);
    if (status.isGranted) {
      _setMicPermissionFallback(false);
      return true;
    }
    if (status.isPermanentlyDenied) {
      _setMicPermissionFallback(true);
      return false;
    }
    final proceed = await _showMicRationaleDialog();
    if (!proceed) {
      return false;
    }
    final requestStatus = await Permission.microphone.request();
    _setMicPermissionStatus(requestStatus);
    if (!requestStatus.isGranted) {
      _setMicPermissionFallback(true);
      return false;
    }
    _setMicPermissionFallback(false);
    return true;
  }

  void _setMicPermissionStatus(PermissionStatus status) {
    if (mounted) {
      setState(() {
        _micPermissionStatus = status;
      });
    } else {
      _micPermissionStatus = status;
    }
  }

  void _setMicPermissionFallback(bool show) {
    if (mounted) {
      setState(() {
        _showMicPermissionFallback = show;
      });
    } else {
      _showMicPermissionFallback = show;
    }
  }

  void _setMicDisabled(bool disabled) {
    if (_micDisabled == disabled) {
      return;
    }
    if (mounted) {
      setState(() {
        _micDisabled = disabled;
        if (disabled && !_useMidi) {
          _isListening = false;
        }
      });
    } else {
      _micDisabled = disabled;
      if (disabled && !_useMidi) {
        _isListening = false;
      }
    }
  }

  Future<bool> _showMicRationaleDialog() async {
    if (!mounted) {
      return false;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text(StringsFr.micAccessTitle),
        content: const Text(StringsFr.micRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(StringsFr.micRationaleCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(StringsFr.micRationaleContinue),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // ignore: unused_element (called from _PracticeUiStageMixin)
  Future<void> _handleRetryMicPermission() async {
    _setMicPermissionFallback(false);
    if (_practiceRunning) {
      final granted = await _ensureMicPermission();
      if (!granted || _useMidi) {
        return;
      }
      _setMicDisabled(false);
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      } else {
        _isListening = true;
      }
      await _startMicStream();
      return;
    }
    await _togglePractice();
  }

  // ignore: unused_element (called from _PracticeNotesLogicMixin)
  void _logMicDebug(DateTime now) {
    if (!kDebugMode) {
      return;
    }
    if (_lastMicLogAt != null &&
        now.difference(_lastMicLogAt!) < const Duration(seconds: 1)) {
      return;
    }
    _lastMicLogAt = now;
    final freqText = _micFrequency?.toStringAsFixed(1) ?? '--';
    final noteText = _micNote != null
        ? _formatMidiNote(_micNote!, withOctave: true)
        : '--';
    debugPrint(
      'MIC: rms=${_micRms.toStringAsFixed(3)} '
      'f0=$freqText note=$noteText conf=${_micConfidence.toStringAsFixed(2)}',
    );
  }

  void _setStopReason(String reason) {
    if (_stopReason == reason) {
      return;
    }
    _stopReason = reason;
    if (kDebugMode) {
      debugPrint('Practice stop reason: $reason');
    }
    if (mounted) {
      setState(() {});
    }
  }

  bool _shouldKeepMicOn() {
    return mounted && _practiceRunning && !_useMidi && !_micDisabled;
  }

  Future<void> _startMicStream() async {
    _micSub?.cancel();
    _micSub = null;
    _micConfigLogged = false; // Reset config logging for new session
    try {
      await _recorder.stop();
    } catch (_) {}

    try {
      await _recorder.initialize(sampleRate: PitchDetector.sampleRate);
      await _recorder.start();
      // D1+D3: Log MIC_FORMAT once per session (audio setup diagnostic)
      if (!_micConfigLogged && kDebugMode) {
        _micConfigLogged = true;
        // FIX BUG CRITIQUE: Log actual detected sampleRate from MicEngine (may differ from requested)
        final actualSr =
            _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
        debugPrint(
          'MIC_FORMAT sessionId=$_practiceSessionId requested=${PitchDetector.sampleRate} actual=$actualSr '
          'bufferMs=${(PitchDetector.bufferSize * 1000 ~/ actualSr)} '
          'offset=${_micScoringOffsetSec.toStringAsFixed(3)}s',
        );
      }
      // D3: Default latency compensation (~100ms for buffer latency)
      _micLatencyCompSec = 0.10;
      if (kDebugMode) {
        debugPrint(
          'MIC_LATENCY_COMP sessionId=$_practiceSessionId compSec=${_micLatencyCompSec.toStringAsFixed(3)}',
        );
      }
      _micSub = _recorder.audioStream.listen(
        _processAudioChunk,
        onError: (error, _) {
          _handleMicStreamStop('mic_error', error: error);
        },
        onDone: () {
          _handleMicStreamStop('mic_done');
        },
        cancelOnError: true,
      );
    } catch (e) {
      await _handleMicStreamStop('mic_start_error', error: e);
    }
  }

  Future<void> _handleMicStreamStop(String reason, {Object? error}) async {
    if (kDebugMode && error != null) {
      debugPrint('Mic stream error ($reason): $error');
    }
    if (!_shouldKeepMicOn()) {
      if (_isListening) {
        _setStopReason(reason);
      }
      return;
    }
    if (_micRestarting) {
      return;
    }
    final now = DateTime.now();
    if (_lastMicRestartAt != null &&
        now.difference(_lastMicRestartAt!) < const Duration(seconds: 2)) {
      return;
    }
    const maxAttempts = 2;
    if (_micRestartAttempts >= maxAttempts) {
      _setStopReason(reason);
      _setMicDisabled(true);
      return;
    }
    _micRestarting = true;
    _micRestartAttempts += 1;
    _lastMicRestartAt = now;
    _setStopReason('mic_restart_$reason');
    await Future.delayed(const Duration(milliseconds: 250));
    if (_shouldKeepMicOn()) {
      await _startMicStream();
    }
    _micRestarting = false;
  }

  // ignore: unused_element (called from _PracticeMicDebugMixin)
  Future<void> _runDetectionSelfTest() async {
    if (!kDebugMode) {
      return;
    }
    const freq = 440.0;
    final samples = Float32List(PitchDetector.bufferSize);
    // FIX BUG CRITIQUE: Generate test samples with actual detected sampleRate
    final actualSr = _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = sin(2 * pi * freq * i / actualSr);
    }
    final detected = _pitchDetector.detectPitch(samples, sampleRate: actualSr);
    if (!mounted) {
      return;
    }
    final message = detected == null
        ? 'No pitch detected'
        : 'Detected ${detected.toStringAsFixed(1)} Hz '
              '(${_formatMidiNote(_pitchDetector.frequencyToMidiNote(detected), withOctave: true)})';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // ignore: unused_element (called from _PracticeMicDebugMixin)
  void _injectA4() {
    if (!kDebugMode) {
      return;
    }
    if (!_practiceRunning || _startTime == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Press Play to inject A4')),
        );
      }
      return;
    }
    const freq = 440.0;
    final samples = Float32List(PitchDetector.bufferSize);
    // FIX BUG CRITIQUE: Generate injection with actual detected sampleRate
    final actualSr = _micEngine?.detectedSampleRate ?? PitchDetector.sampleRate;
    for (int i = 0; i < samples.length; i++) {
      samples[i] = sin(2 * pi * freq * i / actualSr);
    }
    _processSamples(samples, now: DateTime.now(), injected: true);
  }
}
