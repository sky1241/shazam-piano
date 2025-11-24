import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/big_record_button.dart';
import '../../widgets/mode_chip.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  RecordButtonState _buttonState = RecordButtonState.idle;
  final Map<int, ModeChipStatus> _levelStatuses = {
    1: ModeChipStatus.queued,
    2: ModeChipStatus.queued,
    3: ModeChipStatus.queued,
    4: ModeChipStatus.queued,
  };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppColors.backgroundGradient,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // App bar
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.menu,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () {
                        // TODO: Open menu
                      },
                    ),
                    Text(
                      'ShazaPiano',
                      style: AppTextStyles.title,
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.history,
                        color: AppColors.textPrimary,
                      ),
                      onPressed: () {
                        // TODO: Open history
                      },
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // Main content: Big record button
              Column(
                children: [
                  BigRecordButton(
                    state: _buttonState,
                    onTap: _handleRecordButtonTap,
                  ),
                  const SizedBox(height: AppConstants.spacing32),
                  Text(
                    _getButtonText(),
                    style: AppTextStyles.display.copyWith(fontSize: 20),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppConstants.spacing8),
                  Text(
                    _getSubtitleText(),
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),

              const Spacer(),

              // Level status chips
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacing24),
                child: Column(
                  children: [
                    Text(
                      'Progression des niveaux',
                      style: AppTextStyles.caption,
                    ),
                    const SizedBox(height: AppConstants.spacing12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (int i = 1; i <= 4; i++) ...[
                          ModeChip(
                            level: i,
                            status: _levelStatuses[i]!,
                          ),
                          if (i < 4)
                            const SizedBox(width: AppConstants.spacing8),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getButtonText() {
    switch (_buttonState) {
      case RecordButtonState.idle:
        return 'Appuie pour créer\ntes 4 vidéos piano';
      case RecordButtonState.recording:
        return 'Enregistrement...\n${AppConstants.recommendedRecordingDurationSec}s recommandés';
      case RecordButtonState.processing:
        return 'Génération en cours...';
    }
  }

  String _getSubtitleText() {
    switch (_buttonState) {
      case RecordButtonState.idle:
        return 'Enregistre environ ${AppConstants.recommendedRecordingDurationSec} secondes de piano';
      case RecordButtonState.recording:
        return 'Appuie pour arrêter';
      case RecordButtonState.processing:
        return 'Création de tes 4 niveaux...';
    }
  }

  void _handleRecordButtonTap() async {
    if (_buttonState == RecordButtonState.idle) {
      // Start recording
      setState(() {
        _buttonState = RecordButtonState.recording;
      });

      // TODO: Implement actual recording
      // For now, simulate with delay
      await Future.delayed(const Duration(seconds: 8));

      setState(() {
        _buttonState = RecordButtonState.processing;
        _levelStatuses[1] = ModeChipStatus.processing;
      });

      // TODO: Upload and process
      // Simulate processing
      await _simulateProcessing();
    } else if (_buttonState == RecordButtonState.recording) {
      // Stop recording
      setState(() {
        _buttonState = RecordButtonState.processing;
      });

      // TODO: Process recording
      await _simulateProcessing();
    }
  }

  Future<void> _simulateProcessing() async {
    // Simulate processing each level
    for (int i = 1; i <= 4; i++) {
      await Future.delayed(const Duration(seconds: 2));
      setState(() {
        _levelStatuses[i] = ModeChipStatus.completed;
        if (i < 4) {
          _levelStatuses[i + 1] = ModeChipStatus.processing;
        }
      });
    }

    // Navigate to previews
    await Future.delayed(const Duration(seconds: 1));
    if (mounted) {
      // TODO: Navigate to PreviewsPage
      setState(() {
        _buttonState = RecordButtonState.idle;
        for (int i = 1; i <= 4; i++) {
          _levelStatuses[i] = ModeChipStatus.queued;
        }
      });
    }
  }
}

