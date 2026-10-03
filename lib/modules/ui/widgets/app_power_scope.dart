import 'package:flutter/widgets.dart';
import '../../services/app_power_manager.dart';

/// Covers Navigator routes and overlays, including ordinary/implicit tickers.
/// Business timers and services are deliberately outside this gate.
class AppPowerScope extends StatelessWidget {
  final Widget child;
  const AppPowerScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: AppPowerManager.instance.indicatorsAnimationNotifier,
    child: child,
    builder: (context, enabled, child) =>
        TickerMode(enabled: enabled, child: child!),
  );
}
