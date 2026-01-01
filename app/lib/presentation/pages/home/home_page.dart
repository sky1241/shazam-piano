import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../widgets/big_record_button.dart';
import '../../widgets/mode_chip.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/banner_ad_placeholder.dart';
import '../../state/recording_provider.dart';
import '../../state/recording_state.dart';
import '../../state/process_provider.dart';
import '../../state/process_state.dart';
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

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  RecordButtonState _buttonState = RecordButtonState.idle;
  bool _isProcessing = false;
  late final ProviderSubscription<RecordingState> _recordingSubscription;
  late final ProviderSubscription<ProcessState> _processSubscription;
  late final ProcessNotifier _processNotifier;
  bool _isNavigating = false;
  bool _isAdGateVisible = false;
  bool _pendingCompletion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _processNotifier = ref.read(processProvider.notifier);
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
          });
          ref.read(processProvider.notifier).reset();
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
          });
          ref.read(processProvider.notifier).reset();
        }
        return;
      }

      if (_buttonState == RecordButtonState.processing || _isProcessing) {
        return;
      }

      _startProcessing(next.recordedFile!);
    });
    _processSubscription = ref.listenManual(
      processProvider,
      _handleProcessStateChanged,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _processNotifier.stopPolling();
    _recordingSubscription.close();
    _processSubscription.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _processNotifier.stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      _processNotifier.resumePollingIfActive();
    }
  }

  @override
  Widget build(BuildContext context) {
    final processState = ref.watch(processProvider);
    final levelStatuses = processState.levelStatuses;
    return Scaffold(
      bottomNavigationBar: const BannerAdPlaceholder(),
      body: Container(
        decoration: BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isCompact = constraints.maxHeight < 720;
              final gapLg = isCompact
                  ? AppConstants.spacing16
                  : AppConstants.spacing32;
              final sectionPad = isCompact
                  ? AppConstants.spacing16
                  : AppConstants.spacing24;
              final chipGap = isCompact
                  ? AppConstants.spacing8
                  : AppConstants.spacing12;
              return Column(
                children: [
                  // App bar
                  Padding(
                    padding: const EdgeInsets.all(AppConstants.spacing16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: Icon(Icons.menu, color: AppColors.textPrimary),
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

                  // Main content: Big record button
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, innerConstraints) {
                        return Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth:
                                    innerConstraints.maxWidth -
                                    (AppConstants.spacing16 * 2),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  BigRecordButton(
                                    state: _buttonState,
                                    onTap: _handleRecordButtonTap,
                                  ),
                                  SizedBox(height: gapLg),
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
                          ),
                        );
                      },
                    ),
                  ),

                  // Level status chips + ad placeholder
                  Padding(
                    padding: EdgeInsets.all(sectionPad),
                    child: Column(
                      children: [
                        Text(
                          'Progression des niveaux',
                          style: AppTextStyles.caption,
                        ),
                        SizedBox(height: chipGap),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int i = 1; i <= 4; i++) ...[
                              ModeChip(
                                level: i,
                                status:
                                    levelStatuses[i] ?? ModeChipStatus.queued,
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

  void _handleProcessStateChanged(ProcessState? previous, ProcessState next) {
    if (!mounted) {
      return;
    }
    final statusErrorChanged =
        next.jobStatus == 'error' && previous?.jobStatus != 'error';
    if (next.hasError && next.error != previous?.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(next.error ?? 'Erreur de traitement'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() {
        _buttonState = RecordButtonState.idle;
      });
      _isProcessing = false;
      return;
    }

    if (statusErrorChanged && next.error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Erreur de traitement'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() {
        _buttonState = RecordButtonState.idle;
      });
      _isProcessing = false;
      return;
    }

    if (next.jobStatus == 'complete' && next.result != null) {
      if (_isAdGateVisible) {
        _pendingCompletion = true;
        return;
      }
      unawaited(_handleCompletion(next));
    }
  }

  Future<void> _handleCompletion(ProcessState processState) async {
    if (_isNavigating) {
      return;
    }
    _isNavigating = true;
    try {
      final result = processState.result;
      if (result == null || !mounted) {
        return;
      }

      ref.read(historyProvider.notifier).add(result);

      if (result.identifiedTitle == null && result.identifiedArtist == null) {
        await showDialog<void>(
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

      if (!mounted) {
        return;
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => ResultBottomSheet(result: result),
      );

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => PreviewsPage(
            levels: result.levels,
            isUnlocked: true,
            trackTitle: result.identifiedTitle,
            trackArtist: result.identifiedArtist,
          ),
        ),
      );

      if (mounted) {
        setState(() {
          _buttonState = RecordButtonState.idle;
        });
      }
    } finally {
      _isNavigating = false;
    }
  }

  String _formatIdentifiedTitle(ProcessState processState) {
    final title = processState.identifiedTitle;
    final artist = processState.identifiedArtist;
    final parts = [
      if (title != null && title.trim().isNotEmpty) title.trim(),
      if (artist != null && artist.trim().isNotEmpty) artist.trim(),
    ];
    if (parts.isEmpty) {
      return 'Inconnu';
    }
    return parts.join(' - ');
  }

  Future<_AdDecision> _showAdGateDialog(ProcessState processState) async {
    final identified = _formatIdentifiedTitle(processState);
    final decision = await showDialog<_AdDecision>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Titre trouve'),
        content: Text('Titre trouve: $identified'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_AdDecision.skip),
            child: const Text('Passer'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_AdDecision.watch),
            child: const Text('Soutenir le projet - regarder une pub (30s)'),
          ),
        ],
      ),
    );
    return decision ?? _AdDecision.skip;
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
          });
          ref.read(processProvider.notifier).reset();
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
    _pendingCompletion = false;

    setState(() {
      _buttonState = RecordButtonState.processing;
    });

    try {
      final processNotifier = ref.read(processProvider.notifier);
      processNotifier.reset();
      await processNotifier.createJob(
        audioFile: recordedFile,
        withAudio: false,
        levels: [1, 2, 3, 4],
      );

      final processState = ref.read(processProvider);

      if (processState.hasError) {
        return;
      }
      if (processState.jobId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Erreur de traitement'),
              backgroundColor: AppColors.error,
            ),
          );
          setState(() {
            _buttonState = RecordButtonState.idle;
          });
        }
        return;
      }

      if (!mounted) {
        return;
      }

      final decision = await _showAdGateDialog(processState);
      if (!mounted) {
        return;
      }

      await processNotifier.startJob(
        jobId: processState.jobId!,
        withAudio: false,
        levels: [1, 2, 3, 4],
      );
      if (!mounted) {
        return;
      }

      final afterStartState = ref.read(processProvider);
      if (afterStartState.hasError) {
        return;
      }

      if (decision == _AdDecision.watch) {
        _isAdGateVisible = true;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) =>
                const _AdGatePage(duration: Duration(seconds: 30)),
          ),
        );
        _isAdGateVisible = false;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Merci pour ton soutien !')),
          );
        }
        _handlePendingCompletion();
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('OK - tu peux soutenir le projet plus tard'),
            ),
          );
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  void _handlePendingCompletion() {
    if (!_pendingCompletion) {
      return;
    }
    _pendingCompletion = false;
    final processState = ref.read(processProvider);
    if (processState.jobStatus == 'complete' && processState.result != null) {
      unawaited(_handleCompletion(processState));
    }
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

enum _AdDecision { watch, skip }

class _AdGatePage extends StatefulWidget {
  final Duration duration;

  const _AdGatePage({required this.duration});

  @override
  State<_AdGatePage> createState() => _AdGatePageState();
}

class _AdGatePageState extends State<_AdGatePage> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.duration.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        if (mounted) {
          Navigator.of(context).pop();
        }
        return;
      }
      setState(() {
        _remainingSeconds -= 1;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inSeconds;
    final progress = total > 0 ? 1 - (_remainingSeconds / total) : 1.0;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppConstants.spacing24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Publicite (placeholder)',
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppConstants.spacing16),
                Container(
                  height: 240,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(
                      AppConstants.radiusCard,
                    ),
                    border: Border.all(color: AppColors.divider),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Espace pub plein ecran',
                    style: AppTextStyles.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: AppConstants.spacing24),
                LinearProgressIndicator(
                  value: progress,
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                ),
                const SizedBox(height: AppConstants.spacing12),
                Text(
                  'Merci ! Retour dans $_remainingSeconds s',
                  style: AppTextStyles.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
