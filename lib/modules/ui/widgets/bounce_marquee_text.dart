import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/app_power_manager.dart';

/// Chữ lướt bật nảy (Asymmetric Ping-Pong Bouncing Marquee Text)
/// - Kế thừa từ chuẩn thiết kế motion của JA_Mini_Showcase:
///   1. Tự động đo đạc độ tràn chuỗi: nếu chuỗi vừa vặn, tắt hoàn toàn animation (0% CPU overhead).
///   2. Nếu chuỗi dài vượt quá kích thước:
///      - Dừng ở đầu [pauseStart] (mặc định 1400ms).
///      - Lướt mượt tới cuối chuỗi với vận tốc [velocity] (35 px/s) theo [forwardCurve].
///      - Dừng ở cuối [pauseEnd] (mặc định 1400ms).
///      - Búng giật nảy về đầu cực nhanh theo [returnCurve] (Curves.easeOutCubic).
///      - Dừng và lặp lại tuần hoàn.
///   3. Tích hợp Tooltip kính mờ: rê chuột vào để xem ngay toàn bộ chuỗi.
///   4. Tích hợp Session Epoch Guard & Đóng băng Offset theo chuẩn `flutter-power-optimizer`:
///      - Đóng băng cuộn khi Inactive/Minimized, không rò rỉ Timer/ghost callback.
///      - Tiếp tục cuộn từ offset đã đóng băng khi Active trở lại mà không bị giật về 0.
class BounceMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration pauseStart;
  final Duration pauseEnd;
  final double velocity; // px/s
  final Curve forwardCurve;
  final Curve returnCurve;
  final bool enableTooltip;

  const BounceMarqueeText({
    super.key,
    required this.text,
    this.style,
    this.pauseStart = const Duration(milliseconds: 1400),
    this.pauseEnd = const Duration(milliseconds: 1400),
    this.velocity = 35.0,
    this.forwardCurve = Curves.easeInOutCubic,
    this.returnCurve = Curves.easeOutCubic,
    this.enableTooltip = true,
  });

  @override
  State<BounceMarqueeText> createState() => _BounceMarqueeTextState();
}

class _BounceMarqueeTextState extends State<BounceMarqueeText> {
  final ScrollController _scrollController = ScrollController();
  Timer? _timer;
  bool _isDisposed = false;
  int _sessionEpoch = 0;
  bool _isPaused = false;

  @visibleForTesting
  ScrollController get scrollController => _scrollController;

  @visibleForTesting
  int get sessionEpoch => _sessionEpoch;

  @visibleForTesting
  bool get isPaused => _isPaused;

  @override
  void initState() {
    super.initState();
    _isPaused = !AppPowerManager.instance.shouldAnimateMarquee;
    AppPowerManager.instance.marqueeAnimationNotifier.addListener(
      _onPowerStateChanged,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && mounted && !_isPaused) {
        _scheduleStart();
      }
    });
  }

  void _onPowerStateChanged() {
    if (_isDisposed || !mounted) return;
    final shouldAnimate = AppPowerManager.instance.shouldAnimateMarquee;
    if (shouldAnimate && _isPaused) {
      _resumeMarquee();
    } else if (!shouldAnimate && !_isPaused) {
      _pauseMarquee();
    }
  }

  void _pauseMarquee() {
    _sessionEpoch++;
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
    if (_scrollController.hasClients) {
      final currentOffset = _scrollController.offset;
      _scrollController.jumpTo(currentOffset);
    }
  }

  void _resumeMarquee() {
    _sessionEpoch++;
    _isPaused = false;
    if (!_scrollController.hasClients) {
      _scheduleStart();
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final currentOffset = _scrollController.offset;
    if (currentOffset >= maxScroll) {
      final epoch = _sessionEpoch;
      _timer = Timer(widget.pauseEnd, () {
        if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
          return;
        }
        _animateReturn();
      });
    } else if (currentOffset <= 0) {
      final epoch = _sessionEpoch;
      _timer = Timer(widget.pauseStart, () {
        if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
          return;
        }
        _animateForward();
      });
    } else {
      _animateForwardFromOffset(currentOffset);
    }
  }

  @override
  void didUpdateWidget(covariant BounceMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _sessionEpoch++;
      _timer?.cancel();
      _timer = null;
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted && !_isPaused) {
          _scheduleStart();
        }
      });
    }
  }

  void _scheduleStart() {
    _timer?.cancel();
    if (_isDisposed || !mounted || _isPaused) {
      return;
    }
    if (!_scrollController.hasClients) {
      final epoch = _sessionEpoch;
      _timer = Timer(const Duration(milliseconds: 150), () {
        if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
          return;
        }
        _scheduleStart();
      });
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }

    final epoch = _sessionEpoch;
    _timer = Timer(widget.pauseStart, () {
      if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
        return;
      }
      _animateForward();
    });
  }

  void _animateForward() {
    _timer?.cancel();
    if (_isDisposed || !mounted || _isPaused || !_scrollController.hasClients) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }

    final duration = Duration(
      milliseconds: ((maxScroll / widget.velocity) * 1000)
          .round()
          .clamp(600, 6000)
          .toInt(),
    );

    final epoch = _sessionEpoch;
    _scrollController
        .animateTo(maxScroll, duration: duration, curve: widget.forwardCurve)
        .then((_) {
          if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
            return;
          }
          _timer = Timer(widget.pauseEnd, _animateReturn);
        });
  }

  void _animateForwardFromOffset(double currentOffset) {
    _timer?.cancel();
    if (_isDisposed || !mounted || _isPaused || !_scrollController.hasClients) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    final remainingDistance = (maxScroll - currentOffset).clamp(0.0, maxScroll);
    if (remainingDistance <= 0) {
      final epoch = _sessionEpoch;
      _timer = Timer(widget.pauseEnd, () {
        if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
          return;
        }
        _animateReturn();
      });
      return;
    }

    final duration = Duration(
      milliseconds: ((remainingDistance / widget.velocity) * 1000)
          .round()
          .clamp(200, 6000)
          .toInt(),
    );

    final epoch = _sessionEpoch;
    _scrollController
        .animateTo(maxScroll, duration: duration, curve: widget.forwardCurve)
        .then((_) {
          if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
            return;
          }
          _timer = Timer(widget.pauseEnd, _animateReturn);
        });
  }

  void _animateReturn() {
    _timer?.cancel();
    if (_isDisposed || !mounted || _isPaused || !_scrollController.hasClients) {
      return;
    }
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) {
      return;
    }

    final duration = Duration(
      milliseconds: ((maxScroll / (widget.velocity * 1.5)) * 1000)
          .round()
          .clamp(400, 4000)
          .toInt(),
    );

    final epoch = _sessionEpoch;
    _scrollController
        .animateTo(0, duration: duration, curve: widget.returnCurve)
        .then((_) {
          if (epoch != _sessionEpoch || _isPaused || _isDisposed || !mounted) {
            return;
          }
          _timer = Timer(widget.pauseStart, _animateForward);
        });
  }

  @override
  void dispose() {
    AppPowerManager.instance.marqueeAnimationNotifier.removeListener(
      _onPowerStateChanged,
    );
    _sessionEpoch++;
    _isDisposed = true;
    _timer?.cancel();
    _timer = null;
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(
        widget.text,
        style: widget.style,
        maxLines: 1,
        softWrap: false,
      ),
    );

    if (widget.enableTooltip) {
      child = Tooltip(
        message: widget.text,
        waitDuration: const Duration(milliseconds: 350),
        child: child,
      );
    }

    return child;
  }
}

typedef AsymmetricMarqueeText = BounceMarqueeText;
