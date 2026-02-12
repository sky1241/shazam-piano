import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

/// Large circular record button (Shazam-style)
/// States: idle, recording, processing
///
/// UX rules applied: haptic feedback, reduced motion support,
/// idle breathe pulse, recording active pulse.
class BigRecordButton extends StatefulWidget {
  final VoidCallback? onTap;
  final RecordButtonState state;
  final double size;

  const BigRecordButton({
    super.key,
    this.onTap,
    this.state = RecordButtonState.idle,
    this.size = AppConstants.recordButtonSize,
  });

  @override
  State<BigRecordButton> createState() => _BigRecordButtonState();
}

class _BigRecordButtonState extends State<BigRecordButton>
    with TickerProviderStateMixin {
  late AnimationController _recordPulseController;
  late Animation<double> _recordPulseAnimation;
  late AnimationController _idleBreatheController;
  late Animation<double> _idleBreatheAnimation;

  @override
  void initState() {
    super.initState();
    // Recording pulse (bold)
    _recordPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _recordPulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _recordPulseController, curve: Curves.easeInOut),
    );
    _recordPulseController.repeat(reverse: true);

    // Idle breathe (subtle)
    _idleBreatheController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );
    _idleBreatheAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _idleBreatheController, curve: Curves.easeInOut),
    );
    _idleBreatheController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _recordPulseController.dispose();
    _idleBreatheController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return GestureDetector(
      onTap: widget.state != RecordButtonState.processing
          ? () {
              HapticFeedback.mediumImpact();
              widget.onTap?.call();
            }
          : null,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _recordPulseAnimation,
          _idleBreatheAnimation,
        ]),
        builder: (context, child) {
          double scale = 1.0;
          if (!reduceMotion) {
            if (widget.state == RecordButtonState.recording) {
              scale = _recordPulseAnimation.value;
            } else if (widget.state == RecordButtonState.idle) {
              scale = _idleBreatheAnimation.value;
            }
          }

          final iconSize = widget.size * 0.36;

          return Transform.scale(
            scale: scale,
            child: Container(
              width: widget.size,
              height: widget.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.buttonGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: AppConstants.shadowBlur,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Center(child: _buildIcon(iconSize)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIcon(double iconSize) {
    switch (widget.state) {
      case RecordButtonState.idle:
        return Icon(Icons.mic, size: iconSize, color: Colors.white);
      case RecordButtonState.recording:
        return Icon(Icons.stop, size: iconSize, color: Colors.white);
      case RecordButtonState.processing:
        return const CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 4,
        );
    }
  }
}

enum RecordButtonState { idle, recording, processing }
