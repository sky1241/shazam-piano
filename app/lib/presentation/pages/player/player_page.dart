import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import '../practice/practice_page.dart';

class PlayerPage extends StatefulWidget {
  final LevelResult level;
  final bool isUnlocked;
  final String? trackTitle;
  final String? trackArtist;
  final String? localVideoPath;
  final String? localPreviewPath;

  const PlayerPage({
    super.key,
    required this.level,
    required this.isUnlocked,
    this.trackTitle,
    this.trackArtist,
    this.localVideoPath,
    this.localPreviewPath,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;
  static const String _expertModeKey = 'expert_mode';
  bool _expertMode = false;
  // Fullscreen state kept for future UI toggles (kept but unused).
  // ignore: unused_field
  // Fullscreen state kept for future UI toggles (kept but unused).
  // ignore: unused_field
  final bool _isFullScreen = false;
  double _videoSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    _loadExpertMode();
  }

  Future<void> _loadExpertMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_expertModeKey) ?? false;
      if (mounted) {
        setState(() {
          _expertMode = value;
        });
      } else {
        _expertMode = value;
      }
    } catch (_) {
      // ignore preference errors
    }
  }

  Future<void> _setExpertMode(bool enabled) async {
    if (_expertMode == enabled) {
      return;
    }
    setState(() {
      _expertMode = enabled;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_expertModeKey, enabled);
    } catch (_) {
      // ignore preference errors
    }
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      String resolveUrl(String url) {
        if (url.isEmpty) return url;
        if (url.startsWith('http')) return url;
        final baseRaw = AppConstants.backendBaseUrl.trim();
        final base = baseRaw.isEmpty ? 'http://127.0.0.1:8000' : baseRaw;
        final baseWithSlash = base.endsWith('/')
            ? base
            : '$base/'; // ensure trailing slash
        final cleaned = url.startsWith('/') ? url.substring(1) : url;
        final resolved = Uri.parse(baseWithSlash).resolve(cleaned).toString();
        // Debug base + resolved
        // ignore: avoid_print
        print('[Player] base=$base resolved=$resolved');
        return resolved;
      }

      final useFull = widget.isUnlocked;
      final localPath = useFull
          ? widget.localVideoPath
          : widget.localPreviewPath;

      VideoPlayerController controller;
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (file.existsSync() && file.lengthSync() > 0) {
          controller = VideoPlayerController.file(file);
        } else {
          // Use preview or full video based on unlock status
          final videoUrl = resolveUrl(
            useFull ? widget.level.videoUrl : widget.level.previewUrl,
          );

          // Debug: log final URL used by the player
          // ignore: avoid_print
          print('[Player] loading video: $videoUrl');

          if (videoUrl.isEmpty) {
            setState(() {
              _error = 'Aucune video disponible';
              _isLoading = false;
            });
            return;
          }

          controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
        }
      } else {
        // Use preview or full video based on unlock status
        final videoUrl = resolveUrl(
          useFull ? widget.level.videoUrl : widget.level.previewUrl,
        );

        // Debug: log final URL used by the player
        // ignore: avoid_print
        print('[Player] loading video: $videoUrl');

        if (videoUrl.isEmpty) {
          setState(() {
            _error = 'Aucune video disponible';
            _isLoading = false;
          });
          return;
        }

        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }

      _videoPlayerController = controller;

      await _videoPlayerController!.initialize();

      final aspect = _videoPlayerController!.value.aspectRatio == 0
          ? (16 / 9)
          : _videoPlayerController!.value.aspectRatio;

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: true,
        aspectRatio: aspect,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: AppColors.divider,
          bufferedColor: AppColors.textSecondary,
        ),
      );

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Erreur de chargement: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    if (isLandscape) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(widget.level.name),
          actions: [
            IconButton(icon: const Icon(Icons.share), onPressed: _handleShare),
            if (widget.isUnlocked)
              IconButton(
                icon: const Icon(Icons.download),
                onPressed: _handleDownload,
              ),
            _buildExpertMenu(),
          ],
        ),
        body: SafeArea(
          child: Container(color: Colors.black, child: _buildVideoPlayer()),
        ),
      );
    }

    // Portrait mode (original layout)
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.level.name),
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _handleShare),
          if (widget.isUnlocked)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _handleDownload,
            ),
          _buildExpertMenu(),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Track title/artist hidden to avoid duplicate overlays with rendered video

              // Video Player
              Container(color: Colors.black, child: _buildVideoPlayer()),

              // Metadata Card
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppConstants.spacing16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.level.name, style: AppTextStyles.title),
                        const SizedBox(height: AppConstants.spacing8),
                        _buildMetadataRow(
                          'Tonalité',
                          widget.level.keyGuess ?? 'N/A',
                        ),
                        _buildMetadataRow(
                          'Tempo',
                          '${widget.level.tempoGuess ?? 0} BPM',
                        ),
                        _buildMetadataRow(
                          'Durée',
                          widget.isUnlocked
                              ? 'Vidéo complète'
                              : 'Aperçu gratuit (12 secondes)',
                          subLabel: _expertMode
                              ? (widget.isUnlocked
                                    ? 'tech: full video'
                                    : 'tech: 12s preview')
                              : null,
                        ),
                        if (!widget.isUnlocked) ...[
                          const SizedBox(height: AppConstants.spacing16),
                          Container(
                            padding: const EdgeInsets.all(
                              AppConstants.spacing12,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.lock,
                                  color: AppColors.warning,
                                  size: 20,
                                ),
                                const SizedBox(width: AppConstants.spacing8),
                                Expanded(
                                  child: Text(
                                    'Accède à la vidéo complète',
                                    style: AppTextStyles.caption.copyWith(
                                      color: AppColors.warning,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppConstants.spacing16),

              // Action Buttons
              Padding(
                padding: const EdgeInsets.all(AppConstants.spacing24),
                child: Column(
                  children: [
                    if (widget.isUnlocked)
                      _buildActionButton(
                        label: 'Mode Pratique',
                        onPressed: _handlePracticeMode,
                      )
                    else ...[
                      Text(
                        'Paiement unique – pas d’abonnement',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppConstants.spacing8),
                      _buildActionButton(
                        label: 'Débloquer pour 1\$',
                        onPressed: _handleUnlock,
                      ),
                      const SizedBox(height: AppConstants.spacing12),
                      _buildActionButton(
                        label: 'Mode Pratique',
                        onPressed: _handlePracticeMode,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppConstants.spacing16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 48),
              const SizedBox(height: AppConstants.spacing16),
              Text(
                _error!,
                style: AppTextStyles.body.copyWith(color: AppColors.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppConstants.spacing16),
              TextButton(
                onPressed: _initializePlayer,
                child: const Text('Reessayer'),
              ),
            ],
          ),
        ),
      );
    }

    if (_chewieController == null) {
      return const Center(child: Text('Aucune video'));
    }

    final size = _videoPlayerController?.value.size;
    final aspectRatio = (size?.aspectRatio ?? 16 / 9);

    return Stack(
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Chewie(controller: _chewieController!),
          ),
        ),
        // Custom speed + fullscreen controls (overlay)
        Positioned(
          bottom: 10,
          right: 10,
          child: Row(
            children: [
              // Speed control menu
              PopupMenuButton<double>(
                initialValue: _videoSpeed,
                onSelected: (speed) {
                  setState(() {
                    _videoSpeed = speed;
                  });
                  _videoPlayerController?.setPlaybackSpeed(speed);
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 0.5, child: Text('0.5x')),
                  const PopupMenuItem(value: 0.75, child: Text('0.75x')),
                  const PopupMenuItem(value: 1.0, child: Text('1.0x (Normal)')),
                  const PopupMenuItem(value: 1.25, child: Text('1.25x')),
                  const PopupMenuItem(value: 1.5, child: Text('1.5x')),
                ],
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.white, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        '${_videoSpeed.toStringAsFixed(2)}x',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Fullscreen exit button
              IconButton(
                icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                onPressed: () {
                  // Exit fullscreen (navigate back or dismiss)
                  if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                iconSize: 24,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataRow(String label, String value, {String? subLabel}) {
    final trimmedSub = subLabel?.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                value,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (trimmedSub != null && trimmedSub.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              trimmedSub,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(label),
      ),
    );
  }

  Widget _buildExpertMenu() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.tune),
      onSelected: (value) {
        if (value == 'expert') {
          _setExpertMode(!_expertMode);
        }
      },
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: 'expert',
          checked: _expertMode,
          child: const Text('Mode expert'),
        ),
      ],
    );
  }

  void _handleShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Partage en cours d implementation')),
    );
  }

  void _handleDownload() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telechargement en cours d implementation')),
    );
  }

  void _handlePracticeMode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            PracticePage(level: widget.level, forcePreview: !widget.isUnlocked),
      ),
    );
  }

  void _handleUnlock() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.card,
        title: const Text('Désolé, contenu premium'),
        content: const Text(
          'Débloque tous les niveaux pour accéder à cette vidéo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Voir l’offre'),
          ),
        ],
      ),
    );
  }
}
