import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/big_record_button.dart';
import '../../widgets/mode_chip.dart';
import '../../widgets/app_logo.dart';
import '../../state/recording_provider.dart';
import '../../state/recording_state.dart';
import '../../state/process_provider.dart';
import '../../state/history_provider.dart';
import '../previews/previews_page.dart';
import '../settings/settings_page.dart';
import '../history/history_page.dart';
import '../results/result_bottom_sheet.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  RecordButtonState _buttonState = RecordButtonState.idle;
  bool _isProcessing = false;
  late final ProviderSubscription<RecordingState> _recordingSubscription;
  final Map<int, ModeChipStatus> _levelStatuses = {
    1: ModeChipStatus.queued,
    2: ModeChipStatus.queued,
    3: ModeChipStatus.queued,
    4: ModeChipStatus.queued,
  };

  @override
  void initState() {
    super.initState();
    _recordingSubscription = ref.listenManual(recordingProvider, (prev, next) {
      final wasRecording = prev?.isRecording ?? false;
      if (!wasRecording || next.isRecording) {
        return;
      }

      if (next.hasError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(next.error ?? 'Erreur d enregistrement'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _buttonState = RecordButtonState.idle;
            _resetLevelStatuses();
          });
        }
        return;
      }

      if (next.recordedFile == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Aucun enregistrement trouvé'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _buttonState = RecordButtonState.idle;
            _resetLevelStatuses();
          });
        }
        return;
      }

      if (_buttonState == RecordButtonState.processing || _isProcessing) {
        return;
      }

      _startProcessing(next.recordedFile!);
    });
  }

  @override
  void dispose() {
    _recordingSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final processState = ref.watch(processProvider);
    final showProcessingAd =
        _buttonState == RecordButtonState.processing && processState.isActive;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: IntrinsicHeight(
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
                                onPressed: _openSettings,
                              ),
                              const AppLogo(width: 120, height: 40),
                              IconButton(
                                icon: Icon(
                                  Icons.history,
                                  color: AppColors.textPrimary,
                                ),
                                onPressed: _openHistory,
                              ),
                            ],
                          ),
                        ),

                        Flexible(flex: 1, child: Container()),

                        // Main content: Big record button
                        Flexible(
                          flex: 2,
                          child: Column(
                            children: [
                              BigRecordButton(
                                state: _buttonState,
                                onTap: _handleRecordButtonTap,
                              ),
                              const SizedBox(height: AppConstants.spacing32),
                              Text(
                                _getButtonText(),
                                style: AppTextStyles.display.copyWith(
                                  fontSize: 20,
                                ),
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
                        ),

                        Flexible(flex: 1, child: Container()),

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
                                      const SizedBox(
                                        width: AppConstants.spacing8,
                                      ),
                                  ],
                                ],
                              ),
                              if (showProcessingAd) ...[
                                const SizedBox(height: AppConstants.spacing16),
                                const _AdPlaceholderWidget(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
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
    final recordingNotifier = ref.read(recordingProvider.notifier);

    if (_buttonState == RecordButtonState.idle) {
      // Start recording
      setState(() {
        _buttonState = RecordButtonState.recording;
      });

      // Start actual audio recording
      await recordingNotifier.startRecording();

      // Recording started, wait for user to stop
      // (button will be tapped again to stop)
      final rec = ref.read(recordingProvider);
      if (!rec.isRecording) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                rec.error ?? 'Impossible de démarrer l\'enregistrement',
              ),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _buttonState = RecordButtonState.idle;
            _resetLevelStatuses();
          });
        }
        return;
      }
      return;
    }

    if (_buttonState == RecordButtonState.recording) {
      // Stop recording
      await recordingNotifier.stopRecording();
    }
  }

  Future<void> _startProcessing(File recordedFile) async {
    if (_isProcessing || _buttonState == RecordButtonState.processing) {
      return;
    }
    _isProcessing = true;

    setState(() {
      _buttonState = RecordButtonState.processing;
      _resetLevelStatuses();
      _levelStatuses[1] = ModeChipStatus.processing;
    });

    try {
      final processNotifier = ref.read(processProvider.notifier);
      await processNotifier.processAudio(
        audioFile: recordedFile,
        withAudio: false,
        levels: [1, 2, 3, 4],
      );

      final processState = ref.read(processProvider);

      if (processState.hasError) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(processState.error ?? 'Erreur de traitement'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _buttonState = RecordButtonState.idle;
            _resetLevelStatuses();
          });
        }
        return;
      }

      // Simulate progression through levels
      await _simulateProcessing();

      // Show identification + navigate to previews page with results
      if (mounted && processState.result != null) {
        // Save in history
        ref.read(historyProvider.notifier).add(processState.result!);

        // If no identification, prompt user to record full song
        if (processState.result!.identifiedTitle == null &&
            processState.result!.identifiedArtist == null) {
          // ignore: use_build_context_synchronously
          showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Titre non reconnu'),
              content: const Text(
                'Titre non reconnu. Pour de meilleurs resultats, enregistre toute la musique et evite le bruit.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }

        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => ResultBottomSheet(result: processState.result!),
        );

        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => PreviewsPage(
              levels: processState.result!.levels,
              isUnlocked: true, // full videos available
              trackTitle: processState.result!.identifiedTitle,
              trackArtist: processState.result!.identifiedArtist,
            ),
          ),
        );

        // Reset state
        setState(() {
          _buttonState = RecordButtonState.idle;
          _resetLevelStatuses();
        });
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _resetLevelStatuses() {
    for (int i = 1; i <= 4; i++) {
      _levelStatuses[i] = ModeChipStatus.queued;
    }
  }

  Future<void> _simulateProcessing() async {
    // Simulate processing each level for visual feedback
    for (int i = 1; i <= 4; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        setState(() {
          _levelStatuses[i] = ModeChipStatus.completed;
          if (i < 4) {
            _levelStatuses[i + 1] = ModeChipStatus.processing;
          }
        });
      }
    }

    await Future.delayed(const Duration(seconds: 1));
  }

  void _openSettings() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const SettingsPage()));
  }

  void _openHistory() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const HistoryPage()));
  }
}

class _AdPlaceholderWidget extends StatelessWidget {
  const _AdPlaceholderWidget();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      width: double.infinity,
      padding: const EdgeInsets.all(AppConstants.spacing16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppConstants.radiusCard),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Publicite',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppConstants.spacing8),
          Text(
            'Chargement...',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
