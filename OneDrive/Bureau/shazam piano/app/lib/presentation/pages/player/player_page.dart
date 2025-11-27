import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_constants.dart';
import '../../../domain/entities/level_result.dart';
import '../practice/practice_page.dart';

class PlayerPage extends StatefulWidget {
  final LevelResult level;
  final bool isUnlocked;

  const PlayerPage({
    super.key,
    required this.level,
    required this.isUnlocked,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Use preview or full video based on unlock status
      final videoUrl = widget.isUnlocked 
          ? widget.level.videoUrl 
          : widget.level.previewUrl;

      if (videoUrl == null) {
        setState(() {
          _error = 'Aucune vidéo disponible';
          _isLoading = false;
        });
        return;
      }

      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
      );

      await _videoPlayerController.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: true,
        aspectRatio: 16 / 9,
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
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(widget.level.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _handleShare,
          ),
          if (widget.isUnlocked)
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: _handleDownload,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Video Player
              AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              color: Colors.black,
              child: _buildVideoPlayer(),
            ),
          ),

          // Metadata Card
          Padding(
            padding: const EdgeInsets.all(AppConstants.spacing16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppConstants.spacing16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.level.name,
                      style: AppTextStyles.title,
                    ),
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
                      widget.isUnlocked ? 'Complète' : '16s preview',
                    ),
                    if (!widget.isUnlocked) ...[
                      const SizedBox(height: AppConstants.spacing16),
                      Container(
                        padding: const EdgeInsets.all(AppConstants.spacing12),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(0.1),
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
                                'Débloquez pour la vidéo complète',
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
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _handlePracticeMode,
                      icon: const Icon(Icons.piano),
                      label: const Text('Mode Pratique 🎹'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _handleUnlock,
                      child: const Text('Débloquer pour 1\$ 🔓'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
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

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.error,
              size: 48,
            ),
            const SizedBox(height: AppConstants.spacing16),
            Text(
              _error!,
              style: AppTextStyles.body.copyWith(
                color: AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppConstants.spacing16),
            TextButton(
              onPressed: _initializePlayer,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }

    if (_chewieController == null) {
      return const Center(
        child: Text('Aucune vidéo'),
      );
    }

    return Chewie(controller: _chewieController!);
  }

  Widget _buildMetadataRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
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
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  void _handleShare() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Partage en cours d\'implémentation'),
      ),
    );
  }

  void _handleDownload() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Téléchargement en cours d\'implémentation'),
      ),
    );
  }

  void _handlePracticeMode() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PracticePage(
          level: widget.level,
        ),
      ),
    );
  }

  void _handleUnlock() {
    // TODO: Show paywall modal
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Paywall en cours d\'implémentation'),
        backgroundColor: AppColors.warning,
      ),
    );
  }
}

