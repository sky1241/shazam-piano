import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import 'pitch_detector.dart';

class PracticePage extends StatefulWidget {
  final LevelResult level;

  const PracticePage({
    super.key,
    required this.level,
  });

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final PitchDetector _pitchDetector = PitchDetector();
  
  bool _isListening = false;
  int? _detectedNote;
  int? _expectedNote;
  NoteAccuracy _accuracy = NoteAccuracy.miss;
  int _score = 0;
  int _totalNotes = 0;
  int _correctNotes = 0;

  // Piano keyboard (2 octaves for practice - C4 to C6)
  static const int _firstKey = 60; // C4
  static const int _lastKey = 84;  // C6
  static const List<int> _blackKeys = [1, 3, 6, 8, 10]; // C#, D#, F#, G#, A#

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Practice - ${widget.level.name}'),
        actions: [
          IconButton(
            icon: Icon(
              _isListening ? Icons.stop : Icons.play_arrow,
              color: AppColors.primary,
            ),
            onPressed: _togglePractice,
          ),
        ],
      ),
      body: Column(
        children: [
          // Score display
          Container(
            padding: const EdgeInsets.all(AppConstants.spacing16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(color: AppColors.divider, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildScoreStat('Score', _score.toString()),
                _buildScoreStat(
                  'Précision',
                  _totalNotes > 0
                      ? '${(_correctNotes / _totalNotes * 100).toStringAsFixed(1)}%'
                      : '0%',
                ),
                _buildScoreStat('Notes', '$_correctNotes/$_totalNotes'),
              ],
            ),
          ),

          const SizedBox(height: AppConstants.spacing24),

          // Current note display
          Text(
            _isListening ? 'Écoute...' : 'Appuie sur Play',
            style: AppTextStyles.title,
          ),
          
          const SizedBox(height: AppConstants.spacing16),

          // Accuracy indicator
          if (_detectedNote != null)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppConstants.spacing24,
                vertical: AppConstants.spacing12,
              ),
              decoration: BoxDecoration(
                color: _getAccuracyColor().withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                border: Border.all(
                  color: _getAccuracyColor(),
                  width: 2,
                ),
              ),
              child: Text(
                _getAccuracyText(),
                style: AppTextStyles.title.copyWith(
                  color: _getAccuracyColor(),
                ),
              ),
            ),

          const Spacer(),

          // Virtual Piano Keyboard
          _buildPianoKeyboard(),

          const SizedBox(height: AppConstants.spacing32),

          // Instructions
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacing16),
            child: Text(
              'Joue les notes sur ton piano.\n'
              'Les touches s\'allumeront selon ta précision.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScoreStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: AppTextStyles.display.copyWith(
            fontSize: 28,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTextStyles.caption,
        ),
      ],
    );
  }

  Widget _buildPianoKeyboard() {
    return Container(
      height: 200,
      padding: const EdgeInsets.symmetric(horizontal: AppConstants.spacing16),
      child: Stack(
        children: [
          // White keys
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int note = _firstKey; note <= _lastKey; note++)
                if (!_isBlackKey(note))
                  _buildPianoKey(note, isBlack: false),
            ],
          ),
          // Black keys (positioned absolutely)
          Positioned.fill(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int note = _firstKey; note <= _lastKey; note++)
                  if (_isBlackKey(note))
                    _buildPianoKey(note, isBlack: true)
                  else
                    const SizedBox(width: 30), // Space for white keys
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPianoKey(int note, {required bool isBlack}) {
    final isExpected = note == _expectedNote;
    final isDetected = note == _detectedNote;
    
    Color keyColor;
    if (isDetected && isExpected) {
      keyColor = _getAccuracyColor();
    } else if (isExpected) {
      keyColor = AppColors.primary.withOpacity(0.5);
    } else if (isBlack) {
      keyColor = AppColors.blackKey;
    } else {
      keyColor = AppColors.whiteKey;
    }

    return Container(
      width: isBlack ? 20 : 30,
      height: isBlack ? 120 : 180,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: keyColor,
        border: Border.all(color: AppColors.divider, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  bool _isBlackKey(int note) {
    return _blackKeys.contains(note % 12);
  }

  Color _getAccuracyColor() {
    switch (_accuracy) {
      case NoteAccuracy.correct:
        return AppColors.success;
      case NoteAccuracy.close:
        return AppColors.warning;
      case NoteAccuracy.wrong:
        return AppColors.error;
      case NoteAccuracy.miss:
        return AppColors.divider;
    }
  }

  String _getAccuracyText() {
    switch (_accuracy) {
      case NoteAccuracy.correct:
        return '✓ Parfait !';
      case NoteAccuracy.close:
        return '~ Proche';
      case NoteAccuracy.wrong:
        return '✗ Faux';
      case NoteAccuracy.miss:
        return 'Aucune note';
    }
  }

  void _togglePractice() {
    setState(() {
      _isListening = !_isListening;
      
      if (_isListening) {
        _startPractice();
      } else {
        _stopPractice();
      }
    });
  }

  Future<void> _startPractice() async {
    // TODO: Start audio input stream
    // For now, simulate practice mode
    _score = 0;
    _totalNotes = 0;
    _correctNotes = 0;
    
    // Simulate expected notes (would come from MIDI file)
    _expectedNote = 60 + (DateTime.now().second % 12); // Random for demo
  }

  void _stopPractice() {
    // TODO: Stop audio input stream
    setState(() {
      _detectedNote = null;
      _expectedNote = null;
    });
  }

  // This would be called when processing audio samples
  void _onAudioSample(List<double> samples) {
    // Convert to Float32List if needed
    // final frequency = _pitchDetector.detectPitch(samples);
    
    // if (frequency != null) {
    //   final note = _pitchDetector.frequencyToMidiNote(frequency);
    //   
    //   if (_expectedNote != null) {
    //     final expectedFreq = _pitchDetector.midiNoteToFrequency(_expectedNote!);
    //     final cents = _pitchDetector.centsDifference(expectedFreq, frequency);
    //     final accuracy = _pitchDetector.classifyAccuracy(cents);
    //     
    //     setState(() {
    //       _detectedNote = note;
    //       _accuracy = accuracy;
    //       _totalNotes++;
    //       
    //       if (accuracy == NoteAccuracy.correct) {
    //         _correctNotes++;
    //         _score += 100;
    //       } else if (accuracy == NoteAccuracy.close) {
    //         _score += 60;
    //       }
    //     });
    //   }
    // }
  }
}

