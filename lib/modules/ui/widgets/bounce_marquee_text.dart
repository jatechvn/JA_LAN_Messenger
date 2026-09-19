import 'dart:async';
import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed && mounted) {
        _scheduleStart();
      }
    });
  }

  @override
  void didUpdateWidget(covariant BounceMarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isDisposed && mounted) {
          _scheduleStart();
        }
      });
    }
  }

  void _scheduleStart() {
    _timer?.cancel();
    if (_isDisposed || !mounted) return;
    if (!_scrollController.hasClients) {
      _timer = Timer(const Duration(milliseconds: 150), _scheduleStart);
      return;
    }

    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    _timer = Timer(widget.pauseStart, _animateForward);
  }

  void _animateForward() {
    _timer?.cancel();
    if (_isDisposed || !mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final duration = Duration(
      milliseconds: ((maxScroll / widget.velocity) * 1000)
          .round()
          .clamp(600, 6000)
          .toInt(),
    );

    _scrollController
        .animateTo(maxScroll, duration: duration, curve: widget.forwardCurve)
        .then((_) {
          if (_isDisposed || !mounted) return;
          _timer = Timer(widget.pauseEnd, _animateReturn);
        });
  }

  void _animateReturn() {
    _timer?.cancel();
    if (_isDisposed || !mounted || !_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    if (maxScroll <= 0) return;

    final duration = Duration(
      milliseconds: ((maxScroll / (widget.velocity * 1.5)) * 1000)
          .round()
          .clamp(400, 4000)
          .toInt(),
    );

    _scrollController
        .animateTo(0, duration: duration, curve: widget.returnCurve)
        .then((_) {
          if (_isDisposed || !mounted) return;
          _timer = Timer(widget.pauseStart, _animateForward);
        });
  }

  @override
  void dispose() {
    _isDisposed = true;
    _timer?.cancel();
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
