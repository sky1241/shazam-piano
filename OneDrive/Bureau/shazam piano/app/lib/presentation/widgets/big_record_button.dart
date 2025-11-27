import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Large circular record button (Shazam-style)
/// States: idle, recording, processing
class BigRecordButton extends StatefulWidget {
  final VoidCallback? onTap;
  final RecordButtonState state;

  const BigRecordButton({
    super.key,
    this.onTap,
    this.state = RecordButtonState.idle,
  });

  @override
  State<BigRecordButton> createState() => _BigRecordButtonState();
}

class _BigRecordButtonState extends State<BigRecordButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.state != RecordButtonState.processing ? widget.onTap : null,
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          final scale = widget.state == RecordButtonState.recording
              ? _pulseAnimation.value
              : 1.0;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: AppConstants.recordButtonSize,
              height: AppConstants.recordButtonSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.buttonGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.3),
                    blurRadius: AppConstants.shadowBlur,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(
                child: _buildIcon(),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon() {
    switch (widget.state) {
      case RecordButtonState.idle:
        return const Icon(
          Icons.mic,
          size: 80,
          color: Colors.white,
        );
      case RecordButtonState.recording:
        return const Icon(
          Icons.stop,
          size: 80,
          color: Colors.white,
        );
      case RecordButtonState.processing:
        return const CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 4,
        );
    }
  }
}

enum RecordButtonState {
  idle,
  recording,
  processing,
}


