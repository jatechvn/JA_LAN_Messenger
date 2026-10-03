import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../services/app_power_manager.dart';

/// Widget chuyên dụng chạy Sprite Sheet Animation của Sticker Zalo
/// Tự động đo kích thước Width/Height, tính số lượng frames và vẽ qua GPU
/// Hỗ trợ cả file asset đóng gói sẵn lẫn file trực tiếp trên ổ đĩa
class SpriteStickerWidget extends StatefulWidget {
  final String? assetPath;
  final String? filePath;
  final double size;
  final bool autoPlay;
  final bool loop;
  final int fps;
  final VoidCallback? onTap;

  const SpriteStickerWidget({
    super.key,
    this.assetPath,
    this.filePath,
    this.size = 130,
    this.autoPlay = true,
    this.loop = true,
    this.fps = 10,
    this.onTap,
  }) : assert(
         assetPath != null || filePath != null,
         'Cần cung cấp ít nhất assetPath hoặc filePath',
       );

  @override
  State<SpriteStickerWidget> createState() => _SpriteStickerWidgetState();
}

class _SpriteStickerWidgetState extends State<SpriteStickerWidget> {
  ui.Image? _image;
  int _frameCount = 1;
  int _currentFrame = 0;
  Timer? _timer;
  bool _isLoading = true;
  bool _hasError = false;
  ImageStream? _imageStream;
  ImageStreamListener? _streamListener;

  @override
  void initState() {
    super.initState();
    AppPowerManager.instance.indicatorsAnimationNotifier.addListener(
      _onPowerStateChanged,
    );
    _loadImage();
  }

  @override
  void didUpdateWidget(covariant SpriteStickerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.filePath != widget.filePath) {
      _stopAnimation();
      _loadImage();
    }
  }

  void _loadImage() {
    if (_imageStream != null && _streamListener != null) {
      _imageStream!.removeListener(_streamListener!);
    }
    _image?.dispose();
    _image = null;
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final ImageProvider imageProvider;
      if (widget.filePath != null && widget.filePath!.isNotEmpty) {
        imageProvider = FileImage(File(widget.filePath!));
      } else {
        imageProvider = AssetImage(widget.assetPath!);
      }
      _imageStream = imageProvider.resolve(ImageConfiguration.empty);
      _streamListener = ImageStreamListener(
        (ImageInfo info, bool synchronousCall) {
          if (!mounted) {
            info.dispose();
            return;
          }
          final img = info.image;
          final w = img.width;
          final h = img.height;
          // Tỉ lệ ngang / dọc = số lượng frames
          final frames = (w / h).round().clamp(1, 120);

          setState(() {
            _image?.dispose();
            _image = img;
            _frameCount = frames;
            _currentFrame = 0;
            _isLoading = false;
          });

          if (widget.autoPlay && frames > 1) {
            _startAnimation();
          }
        },
        onError: (exception, stackTrace) {
          if (!mounted) return;
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        },
      );
      _imageStream?.addListener(_streamListener!);
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  void _onPowerStateChanged() {
    if (!mounted) return;
    if (AppPowerManager.instance.shouldAnimateIndicators) {
      if (widget.autoPlay && widget.loop && _timer == null && _frameCount > 1) {
        _startAnimation();
      }
    } else {
      _stopAnimation();
    }
  }

  void _startAnimation() {
    _stopAnimation();
    if (_frameCount <= 1 || !AppPowerManager.instance.shouldAnimateIndicators) {
      return;
    }

    final intervalMs = (1000 / widget.fps).round();
    _timer = Timer.periodic(Duration(milliseconds: intervalMs), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_currentFrame + 1 >= _frameCount) {
          if (widget.loop) {
            _currentFrame = 0;
          } else {
            _stopAnimation();
          }
        } else {
          _currentFrame++;
        }
      });
    });
  }

  void _stopAnimation() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    AppPowerManager.instance.indicatorsAnimationNotifier.removeListener(
      _onPowerStateChanged,
    );
    _stopAnimation();
    if (_imageStream != null && _streamListener != null) {
      _imageStream!.removeListener(_streamListener!);
    }
    super.dispose();
    _image?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: Center(
          child: Icon(
            Icons.broken_image_rounded,
            size: widget.size * 0.4,
            color: Colors.white24,
          ),
        ),
      );
    }

    if (_isLoading || _image == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    Widget content = CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _SpriteSheetPainter(
        image: _image!,
        frameCount: _frameCount,
        currentFrame: _currentFrame,
      ),
    );

    if (widget.onTap != null) {
      content = GestureDetector(onTap: widget.onTap, child: content);
    }

    return MouseRegion(
      cursor: widget.onTap != null
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      onEnter: (_) {
        if (!widget.autoPlay && _frameCount > 1) {
          _startAnimation();
        }
      },
      onExit: (_) {
        if (!widget.autoPlay && _frameCount > 1) {
          _stopAnimation();
          setState(() => _currentFrame = 0);
        }
      },
      child: content,
    );
  }
}

class _SpriteSheetPainter extends CustomPainter {
  final ui.Image image;
  final int frameCount;
  final int currentFrame;

  _SpriteSheetPainter({
    required this.image,
    required this.frameCount,
    required this.currentFrame,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (frameCount <= 1) {
      // Ảnh tĩnh đơn lẻ
      final src = Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final dst = Rect.fromLTWH(0, 0, size.width, size.height);
      canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      return;
    }

    // Cắt khung hình tương ứng trên dải phim ngang (filmstrip)
    final frameWidth = image.width / frameCount;
    final frameHeight = image.height.toDouble();

    final srcX = currentFrame * frameWidth;
    final src = Rect.fromLTWH(srcX, 0, frameWidth, frameHeight);
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);

    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(covariant _SpriteSheetPainter oldDelegate) {
    return oldDelegate.currentFrame != currentFrame ||
        oldDelegate.image != image ||
        oldDelegate.frameCount != frameCount;
  }
}
