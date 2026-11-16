part of '../peer_list_view.dart';

class _ScanStatusBanner extends StatelessWidget {
  const _ScanStatusBanner();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final isScanning = coordinator.isScanning;
    final scanState = coordinator.scanState;
    final subnetText = scanState.activeSubnets.isNotEmpty
        ? scanState.activeSubnets.first
        : 'LAN';
    final adapterCount = scanState.activeAdaptersCount;

    return Container(
      decoration: BoxDecoration(
        color: (theme.isDark ? Colors.white : Colors.black).withValues(
          alpha: theme.isDark ? 0.03 : 0.02,
        ),
        border: Border(
          bottom: BorderSide(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: theme.isDark ? 0.07 : 0.05,
            ),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                _RadarBeacon(isScanning: isScanning, size: 8),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BounceMarqueeText(
                        text:
                            '$subnetText • $adapterCount ${lang.tr('cardAdapters')}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Consolas',
                          color: theme.isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      BounceMarqueeText(
                        text: coordinator.getLocalizedScanStatus(lang),
                        style: TextStyle(
                          fontSize: 10,
                          color: isScanning
                              ? theme.colors.accentBlue
                              : (theme.isDark
                                    ? Colors.white38
                                    : Colors.black45),
                          fontWeight: isScanning
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _ScanActionButton(
                  isScanning: isScanning,
                  tooltip: lang.tr('rescanTooltip'),
                  onPressed: () => coordinator.rescanNetwork(),
                ),
              ],
            ),
          ),
          // Micro progress bar when scanning
          if (isScanning)
            LinearProgressIndicator(
              value: coordinator.scanProgress > 0
                  ? coordinator.scanProgress
                  : null,
              minHeight: 2,
              backgroundColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colors.accentBlue,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanActionButton extends StatefulWidget {
  final bool isScanning;
  final String tooltip;
  final VoidCallback onPressed;

  const _ScanActionButton({
    required this.isScanning,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_ScanActionButton> createState() => _ScanActionButtonState();
}

class _ScanActionButtonState extends State<_ScanActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    AppPowerManager.instance.indicatorsAnimationNotifier.addListener(
      _onPowerStateChanged,
    );
    if (widget.isScanning && AppPowerManager.instance.shouldAnimateIndicators) {
      _controller.repeat();
    }
  }

  void _onPowerStateChanged() {
    if (!mounted) return;
    if (widget.isScanning && AppPowerManager.instance.shouldAnimateIndicators) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _ScanActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning &&
        !_controller.isAnimating &&
        AppPowerManager.instance.shouldAnimateIndicators) {
      _controller.repeat();
    } else if (!widget.isScanning && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    AppPowerManager.instance.indicatorsAnimationNotifier.removeListener(
      _onPowerStateChanged,
    );
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: widget.isScanning
                    ? theme.colors.accentBlue.withValues(alpha: 0.16)
                    : (_isHovered
                          ? (isDark ? Colors.white : Colors.black).withValues(
                              alpha: 0.08,
                            )
                          : (isDark ? Colors.white : Colors.black).withValues(
                              alpha: 0.03,
                            )),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isScanning
                      ? theme.colors.accentBlue.withValues(alpha: 0.35)
                      : (_isHovered
                            ? (isDark ? Colors.white : Colors.black).withValues(
                                alpha: 0.15,
                              )
                            : (isDark ? Colors.white : Colors.black).withValues(
                                alpha: 0.07,
                              )),
                  width: 1,
                ),
              ),
              child: Center(
                child: RotationTransition(
                  turns: _controller,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: widget.isScanning
                        ? theme.colors.accentBlue
                        : (_isHovered
                              ? (isDark ? Colors.white : Colors.black87)
                              : (isDark ? Colors.white70 : Colors.black54)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarBeacon extends StatefulWidget {
  final bool isScanning;
  final double size;

  const _RadarBeacon({required this.isScanning, this.size = 14});

  @override
  State<_RadarBeacon> createState() => _RadarBeaconState();
}

class _RadarBeaconState extends State<_RadarBeacon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    AppPowerManager.instance.indicatorsAnimationNotifier.addListener(
      _onPowerStateChanged,
    );
    if (AppPowerManager.instance.shouldAnimateIndicators) {
      _controller.repeat();
    }
  }

  void _onPowerStateChanged() {
    if (!mounted) return;
    if (AppPowerManager.instance.shouldAnimateIndicators) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      if (_controller.isAnimating) _controller.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _RadarBeacon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning != oldWidget.isScanning) {
      _controller.duration = Duration(
        milliseconds: widget.isScanning ? 700 : 1600,
      );
      if (AppPowerManager.instance.shouldAnimateIndicators &&
          !_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    AppPowerManager.instance.indicatorsAnimationNotifier.removeListener(
      _onPowerStateChanged,
    );
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final color = widget.isScanning
        ? theme.colors.accentBlue
        : theme.colors.accentEmerald;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.8);
        final opacity = (1.0 - _controller.value).clamp(0.0, 1.0);

        return SizedBox(
          width: widget.size * 2,
          height: widget.size * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ripple wave
              Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size * 1.4,
                  height: widget.size * 1.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: opacity * 0.7),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // Inner glowing core
              Container(
                width: widget.size * 0.75,
                height: widget.size * 0.75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyPeerState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final isScanning = coordinator.isScanning;
    final subnetText = coordinator.scanState.activeSubnets.isNotEmpty
        ? coordinator.scanState.activeSubnets.join(', ')
        : 'LAN';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _RadarBeacon(isScanning: true, size: 20),
            const SizedBox(height: 16),
            Text(
              isScanning ? lang.tr('scanning') : lang.tr('readyDiscover'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${lang.tr('listeningOn')} $subnetText.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: theme.isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(
                      color: (theme.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.15),
                    ),
                  ),
                  onPressed: () => coordinator.rescanNetwork(),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text(
                    lang.tr('rescan'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
