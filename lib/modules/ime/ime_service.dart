import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';
import 'ime_types.dart';
import 'vietnamese_telex_engine.dart';
import 'chinese_pinyin_engine.dart';
import 'external_ime_detector.dart';

class ImeService extends ChangeNotifier {
  static final ImeService _instance = ImeService._internal();
  factory ImeService() => _instance;

  static ImeService of(BuildContext context, {bool listen = true}) {
    try {
      final ime = listen
          ? Provider.of<ImeService?>(context, listen: true)
          : Provider.of<ImeService?>(context, listen: false);
      return ime ?? _instance;
    } catch (_) {
      return _instance;
    }
  }

  ImeMode _mode = ImeMode.auto;
  String _currentLanguageCode = 'vi';
  bool _autoBypassExternal = true;
  DetectedImeInfo _detectedExternalIme = DetectedImeInfo.none;
  Timer? _detectionTimer;

  final ChinesePinyinEngine _pinyinEngine = ChinesePinyinEngine();
  late final SmartImeInputFormatter _inputFormatter;

  ImeService._internal() {
    _inputFormatter = SmartImeInputFormatter(this);
    _startPeriodicDetection();
  }

  ImeMode get mode => _mode;
  String get currentLanguageCode => _currentLanguageCode;
  bool get autoBypassExternal => _autoBypassExternal;
  DetectedImeInfo get detectedExternalIme => _detectedExternalIme;
  ChinesePinyinEngine get pinyinEngine => _pinyinEngine;
  SmartImeInputFormatter get inputFormatter => _inputFormatter;

  /// Chế độ thực thi hiệu lực (sau khi xem xét tự động thích ứng & ngắt do bộ gõ ngoài)
  ImeMode get effectiveMode {
    if (_mode == ImeMode.off) {
      return ImeMode.off;
    }

    if (_mode == ImeMode.telex) {
      if (_autoBypassExternal &&
          _detectedExternalIme.isDetected &&
          (_detectedExternalIme.imeType == 'vietnamese' ||
              _detectedExternalIme.imeType == 'detected')) {
        return ImeMode.off;
      }
      return ImeMode.telex;
    }

    if (_mode == ImeMode.pinyin) {
      if (_autoBypassExternal &&
          _detectedExternalIme.isDetected &&
          (_detectedExternalIme.imeType == 'chinese' ||
              _detectedExternalIme.imeType == 'detected')) {
        return ImeMode.off;
      }
      return ImeMode.pinyin;
    }

    // Chế độ Auto: Tự thích ứng theo ngôn ngữ giao diện
    final lang = _currentLanguageCode.toLowerCase();
    if (lang.startsWith('vi')) {
      if (_autoBypassExternal &&
          _detectedExternalIme.isDetected &&
          (_detectedExternalIme.imeType == 'vietnamese' ||
              _detectedExternalIme.imeType == 'detected')) {
        return ImeMode.off;
      }
      return ImeMode.telex;
    } else if (lang.startsWith('zh') || lang.startsWith('cn')) {
      if (_autoBypassExternal &&
          _detectedExternalIme.isDetected &&
          (_detectedExternalIme.imeType == 'chinese' ||
              _detectedExternalIme.imeType == 'detected')) {
        return ImeMode.off;
      }
      return ImeMode.pinyin;
    }

    return ImeMode.off;
  }

  /// Trạng thái hoạt động của bộ gõ
  ImeEngineState get engineState {
    if (_mode == ImeMode.off) {
      return ImeEngineState.disabledManual;
    }
    if (_autoBypassExternal && _detectedExternalIme.isDetected) {
      final isRelevantType =
          (_mode == ImeMode.telex &&
              (_detectedExternalIme.imeType == 'vietnamese' ||
                  _detectedExternalIme.imeType == 'detected')) ||
          (_mode == ImeMode.pinyin &&
              (_detectedExternalIme.imeType == 'chinese' ||
                  _detectedExternalIme.imeType == 'detected')) ||
          (_mode == ImeMode.auto);
      if (isRelevantType) {
        return ImeEngineState.bypassedExternal;
      }
    }
    return ImeEngineState.active;
  }

  /// Nhãn hiển thị ngắn gọn cho nút trạng thái trên giao diện
  String get shortStatusLabel {
    if (engineState == ImeEngineState.bypassedExternal) {
      return _detectedExternalIme.imeName ?? 'Auto';
    }
    switch (effectiveMode) {
      case ImeMode.telex:
        return 'TELEX';
      case ImeMode.pinyin:
        return '拼音';
      case ImeMode.off:
      case ImeMode.auto:
        return 'EN';
    }
  }

  /// Cập nhật chế độ gõ
  void setMode(ImeMode newMode) {
    if (_mode != newMode) {
      _mode = newMode;
      _pinyinEngine.clear();
      notifyListeners();
    }
  }

  /// Bật/Tắt chế độ tự ngắt khi có bộ gõ ngoài
  void setAutoBypassExternal(bool enabled) {
    if (_autoBypassExternal != enabled) {
      _autoBypassExternal = enabled;
      notifyListeners();
    }
  }

  /// Đồng bộ ngôn ngữ ứng dụng
  void updateAppLanguage(String langCode) {
    if (_currentLanguageCode != langCode) {
      _currentLanguageCode = langCode;
      _pinyinEngine.clear();
      notifyListeners();
    }
  }

  /// Chuyển đổi nhanh (Cycle Mode: Auto -> Telex -> Pinyin -> Off)
  void cycleMode() {
    switch (_mode) {
      case ImeMode.auto:
        setMode(ImeMode.telex);
        break;
      case ImeMode.telex:
        setMode(ImeMode.pinyin);
        break;
      case ImeMode.pinyin:
        setMode(ImeMode.off);
        break;
      case ImeMode.off:
        setMode(ImeMode.auto);
        break;
    }
  }

  /// Bật/Tắt nhanh giữa Chế độ hoạt động và Tắt
  void toggleOnOff() {
    if (_mode == ImeMode.off) {
      setMode(ImeMode.auto);
    } else {
      setMode(ImeMode.off);
    }
  }

  /// Bắt đầu kiểm tra tiến trình bộ gõ ngoài định kỳ
  void _startPeriodicDetection() {
    _detectionTimer?.cancel();
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    _checkExternalIme();
    _detectionTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkExternalIme();
    });
  }

  /// Kiểm tra bộ gõ ngoài bất đồng bộ
  Future<void> _checkExternalIme() async {
    final info = await ExternalImeDetector.checkExternalImeAsync();
    if (info.isDetected != _detectedExternalIme.isDetected ||
        info.imeName != _detectedExternalIme.imeName) {
      _detectedExternalIme = info;
      notifyListeners();
    }
  }

  /// Kiểm tra lại bộ gõ ngoài ngay lập tức (cho test hoặc khi focus cửa sổ)
  Future<void> checkExternalImeNow() => _checkExternalIme();

  /// Ghi nhận heuristic khi phát hiện ký tự có dấu do bộ gõ ngoài đưa vào
  void noteExternalImeInput(String insertedText) {
    if (!_detectedExternalIme.isDetected &&
        ExternalImeDetector.hasAccentedOrChineseChars(insertedText)) {
      _detectedExternalIme = const DetectedImeInfo(
        isDetected: true,
        imeName: 'External IME',
        imeType: 'detected',
      );
      notifyListeners();
    }
  }

  /// Xử lý phím cho Pinyin trong Focus widget (Enter, Esc, Space, 1-5, -, =)
  bool handlePinyinKeyEvent(KeyEvent event, TextEditingController controller) {
    if (effectiveMode != ImeMode.pinyin) return false;

    if (event is KeyDownEvent) {
      // 1. Phím chuyển đổi nhanh Ctrl + Shift
      final isCtrl = HardwareKeyboard.instance.isControlPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;
      if (isCtrl && isShift) {
        toggleOnOff();
        return true;
      }

      // 2. Nếu đang có bộ đệm hoặc danh sách ứng viên Pinyin:
      if (_pinyinEngine.hasCandidates || _pinyinEngine.buffer.isNotEmpty) {
        // Space hoặc Số 1: Chọn ứng viên đầu tiên
        if (event.logicalKey == LogicalKeyboardKey.space ||
            event.logicalKey == LogicalKeyboardKey.digit1 ||
            event.logicalKey == LogicalKeyboardKey.numpad1) {
          final committed = _pinyinEngine.selectCandidate(1);
          if (committed != null) {
            _insertTextIntoController(controller, committed);
            notifyListeners();
            return true;
          }
        }

        // Phím số 2 - 5: Chọn ứng viên tương ứng
        final digit = _getDigitFromKey(event.logicalKey);
        if (digit != null && digit >= 2 && digit <= 5) {
          final committed = _pinyinEngine.selectCandidate(digit);
          if (committed != null) {
            _insertTextIntoController(controller, committed);
            notifyListeners();
            return true;
          }
        }

        // Enter: Chèn trực tiếp chuỗi pinyin tiếng Anh (không đổi Hán tự)
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.numpadEnter) {
          final raw = _pinyinEngine.buffer;
          _pinyinEngine.clear();
          if (raw.isNotEmpty) {
            _insertTextIntoController(controller, raw);
          }
          notifyListeners();
          return true;
        }

        // Escape: Hủy bộ đệm pinyin
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _pinyinEngine.clear();
          notifyListeners();
          return true;
        }

        // Backspace: Xóa 1 chữ cái trong bộ đệm pinyin
        if (event.logicalKey == LogicalKeyboardKey.backspace) {
          final changed = _pinyinEngine.backspace();
          if (changed) {
            notifyListeners();
            return true;
          }
        }

        // Lật trang: - (trang trước) hoặc = (trang sau)
        if (event.logicalKey == LogicalKeyboardKey.minus ||
            event.logicalKey == LogicalKeyboardKey.bracketLeft) {
          if (_pinyinEngine.prevPage()) {
            notifyListeners();
            return true;
          }
        }
        if (event.logicalKey == LogicalKeyboardKey.equal ||
            event.logicalKey == LogicalKeyboardKey.bracketRight) {
          if (_pinyinEngine.nextPage()) {
            notifyListeners();
            return true;
          }
        }
      }
    }

    return false;
  }

  /// Chèn văn bản đã chọn vào vị trí con trỏ của controller
  void _insertTextIntoController(
    TextEditingController controller,
    String text,
  ) {
    final val = controller.value;
    final start = val.selection.start.clamp(0, val.text.length);
    final end = val.selection.end.clamp(0, val.text.length);

    final newText = val.text.replaceRange(start, end, text);
    final newOffset = start + text.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }

  int? _getDigitFromKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.digit1 || key == LogicalKeyboardKey.numpad1) {
      return 1;
    }
    if (key == LogicalKeyboardKey.digit2 || key == LogicalKeyboardKey.numpad2) {
      return 2;
    }
    if (key == LogicalKeyboardKey.digit3 || key == LogicalKeyboardKey.numpad3) {
      return 3;
    }
    if (key == LogicalKeyboardKey.digit4 || key == LogicalKeyboardKey.numpad4) {
      return 4;
    }
    if (key == LogicalKeyboardKey.digit5 || key == LogicalKeyboardKey.numpad5) {
      return 5;
    }
    return null;
  }

  void clearPinyin() {
    _pinyinEngine.clear();
    notifyListeners();
  }

  void pinyinNextPage() {
    if (_pinyinEngine.nextPage()) {
      notifyListeners();
    }
  }

  void pinyinPrevPage() {
    if (_pinyinEngine.prevPage()) {
      notifyListeners();
    }
  }

  String? selectPinyinCandidate(int index) {
    final committed = _pinyinEngine.selectCandidate(index);
    if (committed != null) {
      notifyListeners();
    }
    return committed;
  }

  void onPinyinBufferChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _detectionTimer?.cancel();
    super.dispose();
  }
}

/// Bộ định dạng TextInputFormatter can thiệp trực tiếp vào từng thao tác gõ
class SmartImeInputFormatter extends TextInputFormatter {
  final ImeService service;
  SmartImeInputFormatter(this.service);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final effective = service.effectiveMode;

    // 1. Nếu tắt bộ gõ nội bộ:
    if (effective == ImeMode.off) {
      // Ghi nhận nếu có dấu do bộ gõ ngoài đưa vào
      if (newValue.text.length > oldValue.text.length) {
        final inserted = newValue.text.substring(
          oldValue.selection.baseOffset.clamp(0, newValue.text.length),
          newValue.selection.baseOffset.clamp(0, newValue.text.length),
        );
        if (inserted.isNotEmpty) {
          service.noteExternalImeInput(inserted);
        }
      }
      return newValue;
    }

    // 2. Chế độ Tiếng Việt (Telex Engine):
    if (effective == ImeMode.telex) {
      if ((oldValue.composing.isValid && !oldValue.composing.isCollapsed) ||
          (newValue.composing.isValid && !newValue.composing.isCollapsed) ||
          !oldValue.selection.isValid ||
          !newValue.selection.isValid ||
          !oldValue.selection.isCollapsed ||
          !newValue.selection.isCollapsed) {
        return newValue;
      }
      final oldCursor = oldValue.selection.baseOffset;
      final cursor = newValue.selection.baseOffset;
      if (oldCursor > oldValue.text.length || cursor > newValue.text.length) {
        return newValue;
      }
      // Only an exact single-character backward deletion may reposition tone.
      if (oldCursor > 0 &&
          cursor == oldCursor - 1 &&
          VietnameseTelexEngine.extractWordAtCursor(
            oldValue.text,
            oldCursor,
          ).word.isNotEmpty &&
          newValue.text ==
              oldValue.text.replaceRange(oldCursor - 1, oldCursor, '')) {
        final segment = VietnameseTelexEngine.extractWordAtCursor(
          newValue.text,
          cursor,
        );
        final corrected = VietnameseTelexEngine.repositionAfterDeletion(
          segment.word,
        );
        return newValue.copyWith(
          text: newValue.text.replaceRange(
            segment.start,
            segment.end,
            corrected,
          ),
        );
      }
      // Chỉ can thiệp khi người dùng gõ thêm đúng 1 ký tự vào văn bản
      if (newValue.text.length == oldValue.text.length + 1 &&
          cursor == oldCursor + 1 &&
          newValue.text.substring(0, oldCursor) ==
              oldValue.text.substring(0, oldCursor) &&
          newValue.text.substring(cursor) ==
              oldValue.text.substring(oldCursor)) {
        final keyChar = newValue.text[cursor - 1];

        // Lấy từ đang gõ trong oldValue ngay trước khi gõ ký tự này
        final wordSegment = VietnameseTelexEngine.extractWordAtCursor(
          oldValue.text,
          oldValue.selection.baseOffset,
        );

        {
          final transformedWord = VietnameseTelexEngine.processWord(
            wordSegment.word,
            keyChar,
          );

          if (transformedWord != null) {
            // Thay thế từ cũ bằng từ đã được biến đổi
            final newText = oldValue.text.replaceRange(
              wordSegment.start,
              wordSegment.end,
              transformedWord,
            );
            final newCursor = wordSegment.start + transformedWord.length;
            return TextEditingValue(
              text: newText,
              selection: TextSelection.collapsed(offset: newCursor),
            );
          }
        }
      }
      return newValue;
    }

    // 3. Chế độ Tiếng Trung (Pinyin Engine):
    if (effective == ImeMode.pinyin) {
      // Nếu gõ 1 chữ cái a-z: gom vào bộ đệm pinyin
      if (newValue.text.length == oldValue.text.length + 1 &&
          newValue.selection.isCollapsed) {
        final cursor = newValue.selection.baseOffset;
        final keyChar = newValue.text[cursor - 1];
        final code = keyChar.toLowerCase().codeUnitAt(0);

        if (code >= 97 && code <= 122) {
          final added = service.pinyinEngine.addChar(keyChar);
          if (added) {
            service.onPinyinBufferChanged();
            // Không chèn trực tiếp chữ cái vào text field để chờ chọn ứng viên
            return oldValue;
          }
        }
      }
      return newValue;
    }

    return newValue;
  }
}
