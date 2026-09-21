import 'dart:ui';
import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Single drifting ambient glow orb with Gaussian blur.
class MeshOrb extends StatefulWidget {
  const MeshOrb({
    super.key,
    required this.color,
    required this.size,
    required this.duration,
    required this.travel,
    this.enableAnimation = true,
  });

  final Color color;
  final double size;
  final Duration duration;
  final Offset travel;
  final bool enableAnimation;

  @override
  State<MeshOrb> createState() => _MeshOrbState();
}

class _MeshOrbState extends State<MeshOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);

    if (widget.enableAnimation) {
      _controller.repeat(reverse: true);
    }

    // Stops drifting while window is minimized or hidden (0% background CPU)
    _lifecycleListener = AppLifecycleListener(
      onStateChange: (state) {
        if (!widget.enableAnimation) return;
        switch (state) {
          case AppLifecycleState.hidden:
          case AppLifecycleState.paused:
            _controller.stop();
            break;
          case AppLifecycleState.resumed:
            _controller.repeat(reverse: true);
            break;
          case AppLifecycleState.inactive:
          case AppLifecycleState.detached:
            break;
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant MeshOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableAnimation != oldWidget.enableAnimation) {
      if (widget.enableAnimation) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
      }
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates the 85px blur into its own compositor layer.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = Curves.easeInOutSine.transform(_controller.value);
          return Transform.translate(
            offset: Offset(widget.travel.dx * t, widget.travel.dy * t),
            child: child,
          );
        },
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: 85, sigmaY: 85),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ambient mesh background: 3 drifting [MeshOrb]s behind the app content.
/// Directly adopted from JA_MES_Tool Liquid Glass architecture.
class MeshBackground extends StatelessWidget {
  const MeshBackground({
    super.key,
    required this.colors,
    this.enableAnimation = true,
    this.isLite = false,
  });

  final AppColors colors;
  final bool enableAnimation;
  final bool isLite;

  @override
  Widget build(BuildContext context) {
    if (isLite) {
      // Sleek zero-blur, zero-animation gradient for Lite performance tier
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colors.orb1.withValues(alpha: colors.orbOpacity * 0.4),
              colors.bgPrimary,
              colors.orb2.withValues(alpha: colors.orbOpacity * 0.3),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // Top-left Royal Blue orb
        Positioned(
          top: -160,
          left: -160,
          child: MeshOrb(
            color: colors.orb1.withValues(alpha: colors.orbOpacity),
            size: 480,
            duration: const Duration(seconds: 16),
            travel: const Offset(60, 70),
            enableAnimation: enableAnimation,
          ),
        ),
        // Bottom-right Vivid Violet/Purple orb
        Positioned(
          bottom: -140,
          right: -120,
          child: MeshOrb(
            color: colors.orb2.withValues(alpha: colors.orbOpacity),
            size: 440,
            duration: const Duration(seconds: 18),
            travel: const Offset(-60, -60),
            enableAnimation: enableAnimation,
          ),
        ),
        // Top-right Electric Cyan orb
        Positioned(
          top: 180,
          right: 120,
          child: MeshOrb(
            color: colors.orb3.withValues(alpha: colors.orbOpacity),
            size: 340,
            duration: const Duration(seconds: 20),
            travel: const Offset(-40, 45),
            enableAnimation: enableAnimation,
          ),
        ),
      ],
    );
  }
}
