import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';
import 'package:logging/logging.dart';

/// Single Source of Truth cho quản lý năng lượng và tối ưu hóa GPU/CPU trên Desktop.
/// Quản lý 4 trạng thái cửa sổ (Focus, Inactive, Minimized, Idle 12s) và cung cấp
/// 3 ValueNotifier riêng biệt cho các tầng hiệu ứng giao diện:
/// - [backgroundAnimationNotifier]: Dành cho hiệu ứng nền nặng (MeshOrb gradient). Tự động dừng khi Inactive, Minimized hoặc Idle.
/// - [indicatorsAnimationNotifier]: Dành cho các chỉ báo trạng thái (Radar Beacon, Typing Bubble, Sprite Stickers). Dừng khi Inactive hoặc Minimized; vẫn chạy khi Idle.
/// - [marqueeAnimationNotifier]: Dành cho chữ cuộn Marquee. Dừng và đóng băng khi Inactive hoặc Minimized; vẫn chạy khi Idle.
class AppPowerManager {
  static final AppPowerManager instance = AppPowerManager._internal();
  factory AppPowerManager() => instance;

  AppPowerManager._internal();

  bool _isWindowFocused = true;
  bool _isWindowVisible = true;
  bool _isWindowMinimized = false;
  bool _isUserIdle = false;

  bool _enableIdleSleep = true;
  int _idleTimeoutSeconds = 12;

  Timer? _idleTimer;
  Timer? _nativeMonitor;
  bool _nativeCheckPending = false;
  int _stateEpoch = 0;
  bool _explicitlyHidden = false;
  Future<void>? _transition;
  DateTime _lastInteractionTime = DateTime.now();

  /// Notifier cho các hiệu ứng nền tốn nhiều GPU (ví dụ: MeshOrb)
  final ValueNotifier<bool> backgroundAnimationNotifier = ValueNotifier<bool>(
    true,
  );

  /// Notifier cho các thanh chỉ báo trạng thái UI (Wave, Radar, Typing)
  final ValueNotifier<bool> indicatorsAnimationNotifier = ValueNotifier<bool>(
    true,
  );

  /// Notifier cho chữ cuộn Marquee (BounceMarqueeText)
  final ValueNotifier<bool> marqueeAnimationNotifier = ValueNotifier<bool>(
    true,
  );

  bool get shouldAnimateBackground => backgroundAnimationNotifier.value;
  bool get shouldAnimateIndicators => indicatorsAnimationNotifier.value;
  bool get shouldAnimateMarquee => marqueeAnimationNotifier.value;

  bool get isWindowFocused => _isWindowFocused;
  bool get isWindowVisible => _isWindowVisible;
  bool get isWindowMinimized => _isWindowMinimized;
  bool get isUserIdle => _isUserIdle;
  bool get enableIdleSleep => _enableIdleSleep;
  int get idleTimeoutSeconds => _idleTimeoutSeconds;

  /// Cập nhật giá trị cho cả 3 ValueNotifier dựa theo ma trận trạng thái chuẩn
  void _updateNotifiers() {
    final bool active =
        _isWindowFocused && _isWindowVisible && !_isWindowMinimized;
    final bool bgActive = active && (!_enableIdleSleep || !_isUserIdle);

    if (backgroundAnimationNotifier.value != bgActive) {
      backgroundAnimationNotifier.value = bgActive;
    }
    if (indicatorsAnimationNotifier.value != active) {
      Logger('Power').info(
        'render_active=$active focused=$_isWindowFocused '
        'visible=$_isWindowVisible minimized=$_isWindowMinimized '
        'explicit_hide=$_explicitlyHidden',
      );
      indicatorsAnimationNotifier.value = active;
    }
    if (marqueeAnimationNotifier.value != active) {
      marqueeAnimationNotifier.value = active;
    }
  }

  /// Khi cửa sổ nhận focus (người dùng click vào app)
  void onWindowFocus() {
    if (_explicitlyHidden) return;
    _stateEpoch++;
    _isWindowFocused = true;
    _isWindowVisible = true;
    _isWindowMinimized = false;
    _isUserIdle = false;
    _lastInteractionTime = DateTime.now();
    _resetIdleTimer();
    _updateNotifiers();
  }

  /// Khi cửa sổ mất focus (người dùng chuyển sang cửa sổ khác)
  void onWindowBlur() {
    _stateEpoch++;
    _isWindowFocused = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _updateNotifiers();
  }

  /// Khi cửa sổ bị thu nhỏ xuống Taskbar hoặc ẩn vào khay hệ thống
  void onWindowMinimize() {
    _stateEpoch++;
    _isWindowFocused = false;
    _isWindowMinimized = true;
    _isWindowVisible = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _updateNotifiers();
  }

  /// Khi cửa sổ được phục hồi kích thước từ Taskbar hoặc khay hệ thống
  void onWindowRestore() {
    _stateEpoch++;
    _explicitlyHidden = false;
    _isWindowMinimized = false;
    _isWindowVisible = true;
    // Khi restore, cửa sổ hiển thị trở lại. Nếu có focus thì khởi động lại bộ đếm idle.
    if (_isWindowFocused) {
      _resetIdleTimer();
    }
    _updateNotifiers();
  }

  /// Đồng bộ với vòng đời Flutter AppLifecycleListener
  void onLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        reconcileActivation();
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _markHidden();
        break;
      case AppLifecycleState.inactive:
        onWindowBlur();
        break;
      case AppLifecycleState.detached:
        _markHidden();
        break;
    }
    _updateNotifiers();
  }

  /// Lifecycle/focus events during remote reconnect are hints, not visibility proof.
  void reconcileActivation() {
    onWindowBlur();
    unawaited(synchronizeNative());
  }

  void startNativeMonitoring({bool Function()? isAlive}) {
    stopNativeMonitoring();
    _nativeMonitor = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_nativeCheckPending || !(isAlive?.call() ?? true)) return;
      _nativeCheckPending = true;
      try {
        await synchronizeNative(isAlive: isAlive);
      } finally {
        _nativeCheckPending = false;
      }
    });
  }

  void stopNativeMonitoring() {
    _stateEpoch++;
    _nativeMonitor?.cancel();
    _nativeMonitor = null;
  }

  void _markHidden() {
    _stateEpoch++;
    _isWindowVisible = false;
    _isWindowFocused = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _updateNotifiers();
  }

  /// A native snapshot may not overwrite a newer event or a disposed owner.
  Future<void> synchronizeNative({bool Function()? isAlive}) async {
    final epoch = ++_stateEpoch;
    try {
      final state = await Future.wait([
        windowManager.isVisible(),
        windowManager.isMinimized(),
        windowManager.isFocused(),
      ]);
      if (epoch != _stateEpoch || !(isAlive?.call() ?? true)) return;
      final wasActive =
          _isWindowFocused && _isWindowVisible && !_isWindowMinimized;
      _isWindowVisible = state[0] && !_explicitlyHidden;
      _isWindowMinimized = state[1];
      _isWindowFocused = state[2] && _isWindowVisible && !state[1];
      final active =
          _isWindowFocused && _isWindowVisible && !_isWindowMinimized;
      if (!active || !wasActive) {
        _isUserIdle = false;
        _resetIdleTimer();
      }
      _updateNotifiers();
    } catch (_) {
      // Stay conservative if the native state cannot be queried.
      if (epoch == _stateEpoch && (isAlive?.call() ?? true)) _markHidden();
    }
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final previous = _transition;
    final pending = previous == null
        ? operation()
        : previous.then(
            (_) => operation(),
            onError: (Object error, StackTrace stack) => operation(),
          );
    _transition = pending;
    void clear() {
      if (identical(_transition, pending)) _transition = null;
    }

    unawaited(
      pending.then(
        (_) => clear(),
        onError: (Object error, StackTrace stack) => clear(),
      ),
    );
    return pending;
  }

  Future<void> hideWindow() => _serialize(() async {
    _explicitlyHidden = true;
    _markHidden();
    try {
      await windowManager.hide();
    } catch (_) {
      _explicitlyHidden = false;
      await synchronizeNative();
      rethrow;
    }
  });

  Future<void> showWindow({bool requestFocus = true}) => _serialize(() async {
    // Showing only establishes visibility. Native focus must be confirmed.
    _isWindowFocused = false;
    onWindowRestore();
    try {
      await windowManager.show();
      if (requestFocus) await windowManager.focus();
    } finally {
      await synchronizeNative();
    }
  });

  /// Ghi nhận tương tác từ chuột hoặc bàn phím để thoát chế độ Idle Sleep.
  /// Throttled 600ms khi người dùng đang thao tác liên tục; thức dậy ngay lập tức nếu đang ngủ.
  void recordUserInteraction({DateTime? now}) {
    if (!_isWindowFocused || !_isWindowVisible || _isWindowMinimized) return;

    final currentTime = now ?? DateTime.now();
    if (_isUserIdle) {
      // Đang ngủ rảnh tay -> thức dậy ngay lập tức không cần throttle
      _isUserIdle = false;
      _lastInteractionTime = currentTime;
      _resetIdleTimer();
      _updateNotifiers();
      return;
    }

    if (currentTime.difference(_lastInteractionTime).inMilliseconds >= 600) {
      _lastInteractionTime = currentTime;
      _resetIdleTimer();
    }
  }

  /// Cấu hình tùy chọn chế độ ngủ rảnh tay từ Settings
  void configure({bool? enableIdleSleep, int? idleTimeoutSeconds}) {
    if (enableIdleSleep != null) {
      _enableIdleSleep = enableIdleSleep;
      if (!_enableIdleSleep && _isUserIdle) {
        _isUserIdle = false;
      }
    }
    if (idleTimeoutSeconds != null && idleTimeoutSeconds > 0) {
      _idleTimeoutSeconds = idleTimeoutSeconds;
    }
    _resetIdleTimer();
    _updateNotifiers();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (!_enableIdleSleep ||
        !_isWindowFocused ||
        !_isWindowVisible ||
        _isWindowMinimized) {
      return;
    }
    _idleTimer = Timer(Duration(seconds: _idleTimeoutSeconds), _onIdleTimeout);
  }

  void _onIdleTimeout() {
    if (!_isUserIdle) {
      _isUserIdle = true;
      _updateNotifiers();
    }
  }

  /// Dành riêng cho Unit / Widget Test: Đặt lại trạng thái ban đầu
  @visibleForTesting
  void resetForTesting({
    bool isWindowFocused = true,
    bool isWindowVisible = true,
    bool isWindowMinimized = false,
    bool isUserIdle = false,
    bool enableIdleSleep = true,
    int idleTimeoutSeconds = 12,
  }) {
    _stateEpoch++;
    stopNativeMonitoring();
    _explicitlyHidden = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _isWindowFocused = isWindowFocused;
    _isWindowVisible = isWindowVisible;
    _isWindowMinimized = isWindowMinimized;
    _isUserIdle = isUserIdle;
    _enableIdleSleep = enableIdleSleep;
    _idleTimeoutSeconds = idleTimeoutSeconds;
    _lastInteractionTime = DateTime.now();
    _updateNotifiers();
  }

  @visibleForTesting
  void triggerIdleTimeoutForTesting() {
    _onIdleTimeout();
  }
}
