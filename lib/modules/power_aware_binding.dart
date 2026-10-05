import 'package:flutter/widgets.dart';
import 'services/app_power_manager.dart';

/// TickerMode alone cannot suppress frames from caret/image/business updates.
/// This gate affects rendering only, never timers, isolates or network work.
mixin PowerFrameGate on WidgetsBinding {
  @override
  bool get framesEnabled =>
      super.framesEnabled && AppPowerManager.instance.shouldAnimateIndicators;

  @override
  void initInstances() {
    super.initInstances();
    AppPowerManager.instance.indicatorsAnimationNotifier.addListener(
      _onPowerFrameStateChanged,
    );
  }

  void _onPowerFrameStateChanged() {
    // Replay dirty UI accumulated while inactive, without synthetic lifecycle
    // events that could recursively grant focus or interrupt business logic.
    if (framesEnabled) scheduleFrame();
  }
}

class PowerAwareWidgetsBinding extends WidgetsFlutterBinding
    with PowerFrameGate {}
