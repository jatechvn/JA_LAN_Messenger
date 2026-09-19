import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget quản lý hiệu ứng nhấp nháy trắng (White Strobe Flash) và Rung chấn (Shake)
/// khi nhận được tín hiệu Buzz / Nudge từ đồng nghiệp.
class BuzzFlashOverlay extends StatefulWidget {
  /// Số hiệu kích hoạt Buzz (tăng lên mỗi khi có Buzz mới)
  final int buzzTrigger;

  /// Bật/tắt hiệu ứng chớp sáng trắng toàn màn hình
  final bool enableFlash;

  /// Bật/tắt hiệu ứng rung chấn UI widget
  final bool enableShake;

  /// Widget con bên dưới lớp phủ (thường là toàn bộ bố cục cửa sổ)
  final Widget child;

  const BuzzFlashOverlay({
    super.key,
    required this.buzzTrigger,
    this.enableFlash = true,
    this.enableShake = true,
    required this.child,
  });

  @override
  State<BuzzFlashOverlay> createState() => _BuzzFlashOverlayState();
}

class _BuzzFlashOverlayState extends State<BuzzFlashOverlay>
    with TickerProviderStateMixin {
  late AnimationController _flashController;
  late AnimationController _shakeController;
  int _lastTrigger = 0;

  @override
  void initState() {
    super.initState();
    _lastTrigger = widget.buzzTrigger;

    // Flash controller: chạy 900ms với 4 nhịp chớp (Strobe) mờ dần
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // Shake controller: chạy 600ms rung lắc vật lý
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
  }

  @override
  void didUpdateWidget(BuzzFlashOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.buzzTrigger > _lastTrigger) {
      _lastTrigger = widget.buzzTrigger;
      _triggerBuzz();
    }
  }

  void _triggerBuzz() {
    if (widget.enableFlash) {
      _flashController.forward(from: 0.0);
    }
    if (widget.enableShake) {
      _shakeController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  /// Tính toán độ sáng nhấp nháy Strobe theo tiến trình (0.0 -> 1.0)
  /// 4 nhịp chớp tắt liên hồi:
  /// - Nhịp 1 (0.00 - 0.25): Đỉnh sáng 0.88
  /// - Nhịp 2 (0.25 - 0.50): Đỉnh sáng 0.65
  /// - Nhịp 3 (0.50 - 0.75): Đỉnh sáng 0.40
  /// - Nhịp 4 (0.75 - 1.00): Đỉnh sáng 0.18
  double _calculateStrobeOpacity(double progress) {
    if (progress <= 0.0 || progress >= 1.0) return 0.0;

    final double phaseProgress;
    final double maxPeak;

    if (progress < 0.25) {
      phaseProgress = progress / 0.25;
      maxPeak = 0.88;
    } else if (progress < 0.50) {
      phaseProgress = (progress - 0.25) / 0.25;
      maxPeak = 0.65;
    } else if (progress < 0.75) {
      phaseProgress = (progress - 0.50) / 0.25;
      maxPeak = 0.40;
    } else {
      phaseProgress = (progress - 0.75) / 0.25;
      maxPeak = 0.18;
    }

    // Sine curve: 0 -> peak -> 0
    return math.sin(phaseProgress * math.pi) * maxPeak;
  }

  /// Tính toán độ lệch rung lắc vật lý theo tiến trình (0.0 -> 1.0)
  Offset _calculateShakeOffset(double progress) {
    if (progress <= 0.0 || progress >= 1.0) return Offset.zero;

    // Suy giảm biên độ theo thời gian: từ 14px về 0px
    final decay = 1.0 - progress;
    final frequency = 32.0; // Tần số rung nhanh
    final dx = math.sin(progress * math.pi * frequency) * 14.0 * decay;
    final dy = math.cos(progress * math.pi * (frequency / 2)) * 3.5 * decay;

    return Offset(dx, dy);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_flashController, _shakeController]),
      builder: (context, child) {
        final flashProgress = _flashController.value;
        final shakeProgress = _shakeController.value;

        final strobeOpacity = widget.enableFlash
            ? _calculateStrobeOpacity(flashProgress)
            : 0.0;
        final shakeOffset = widget.enableShake
            ? _calculateShakeOffset(shakeProgress)
            : Offset.zero;

        return Transform.translate(
          offset: shakeOffset,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              // Nội dung chính bên dưới
              widget.child,

              // Lớp phủ White Strobe Flash toàn màn hình
              if (strobeOpacity > 0.01)
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: true,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 1.1,
                          colors: [
                            Colors.white.withValues(alpha: strobeOpacity),
                            const Color(0xFFF0F9FF).withValues(
                              alpha: (strobeOpacity * 0.95).clamp(0.0, 1.0),
                            ),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.white.withValues(
                              alpha: (strobeOpacity * 0.8).clamp(0.0, 1.0),
                            ),
                            blurRadius: 40,
                            spreadRadius: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
