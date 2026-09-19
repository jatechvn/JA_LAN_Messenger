import 'ime_types.dart';
import 'pinyin_dictionary.dart';

class ChinesePinyinEngine {
  String _buffer = '';
  List<String> _candidates = [];
  int _pageIndex = 0;
  static const int pageSize = 5;

  String get buffer => _buffer;
  bool get hasCandidates => _candidates.isNotEmpty;
  int get pageIndex => _pageIndex;
  int get totalPages => (_candidates.length + pageSize - 1) ~/ pageSize;

  /// Đưa thêm một ký tự (a-z) vào bộ đệm Pinyin và tính toán danh sách ứng viên
  bool addChar(String char) {
    if (char.length != 1) return false;
    final lower = char.toLowerCase();
    if (lower.codeUnitAt(0) < 97 || lower.codeUnitAt(0) > 122) return false;

    _buffer += lower;
    _pageIndex = 0;
    _updateCandidates();
    return true;
  }

  /// Xóa ký tự cuối cùng (khi nhấn Backspace)
  bool backspace() {
    if (_buffer.isEmpty) return false;
    _buffer = _buffer.substring(0, _buffer.length - 1);
    _pageIndex = 0;
    if (_buffer.isEmpty) {
      _candidates.clear();
    } else {
      _updateCandidates();
    }
    return true;
  }

  /// Xóa toàn bộ bộ đệm Pinyin (khi nhấn Escape hoặc chuyển ngữ cảnh)
  void clear() {
    _buffer = '';
    _candidates.clear();
    _pageIndex = 0;
  }

  /// Lấy danh sách ứng viên cho trang hiện tại (tối đa 5 ứng viên)
  List<PinyinCandidate> getCurrentPageCandidates() {
    if (_candidates.isEmpty) return const [];
    final start = _pageIndex * pageSize;
    if (start >= _candidates.length) return const [];
    final end = (start + pageSize).clamp(0, _candidates.length);

    final sublist = _candidates.sublist(start, end);
    return List.generate(sublist.length, (i) {
      return PinyinCandidate(
        text: sublist[i],
        pinyin: _getFormattedPinyin(),
        index: i + 1,
      );
    });
  }

  /// Chọn một ứng viên theo thứ tự (1-5) trên trang hiện tại
  String? selectCandidate(int oneBasedIndex) {
    final candidates = getCurrentPageCandidates();
    final zeroBased = oneBasedIndex - 1;
    if (zeroBased >= 0 && zeroBased < candidates.length) {
      final selectedText = candidates[zeroBased].text;
      clear();
      return selectedText;
    }
    return null;
  }

  /// Lật sang trang ứng viên kế tiếp
  bool nextPage() {
    if (_pageIndex + 1 < totalPages) {
      _pageIndex++;
      return true;
    }
    return false;
  }

  /// Quay lại trang ứng viên trước đó
  bool prevPage() {
    if (_pageIndex > 0) {
      _pageIndex--;
      return true;
    }
    return false;
  }

  /// Cập nhật danh sách ứng viên dựa trên `_buffer`
  void _updateCandidates() {
    if (_buffer.isEmpty) {
      _candidates = [];
      return;
    }

    final results = <String>[];
    final seen = <String>{};

    void addCandidate(String word) {
      if (!seen.contains(word)) {
        seen.add(word);
        results.add(word);
      }
    }

    // 1. Kiểm tra từ ghép chính xác (Exact match trong phrases)
    final phraseMatches = PinyinDictionary.phrases[_buffer];
    if (phraseMatches != null) {
      for (final p in phraseMatches) {
        addCandidate(p);
      }
    }

    // 2. Tách âm tiết Pinyin theo nguyên tắc greedy longest match
    final syllables = segmentPinyin(_buffer);

    // 3. Nếu là từ đơn âm tiết: lấy danh sách Hán tự theo tần suất
    final singleMatches = PinyinDictionary.characters[_buffer];
    if (singleMatches != null) {
      for (final c in singleMatches) {
        addCandidate(c);
      }
    }

    // 4. Nếu có nhiều âm tiết (ví dụ: 'ni' + 'hao'):
    if (syllables.length >= 2) {
      // Ghép âm tiết đầu và các âm tiết sau
      final firstSyl = syllables[0];
      final secondSyl = syllables[1];
      final firstChars = PinyinDictionary.characters[firstSyl] ?? [];
      final secondChars = PinyinDictionary.characters[secondSyl] ?? [];

      for (int i = 0; i < firstChars.length.clamp(0, 3); i++) {
        for (int j = 0; j < secondChars.length.clamp(0, 3); j++) {
          addCandidate('${firstChars[i]}${secondChars[j]}');
        }
      }
    }

    // 5. Nếu âm tiết đầu tiên có chữ Hán (để người dùng gõ từng chữ một)
    if (syllables.isNotEmpty) {
      final leadingChars = PinyinDictionary.characters[syllables.first];
      if (leadingChars != null) {
        for (final c in leadingChars) {
          addCandidate(c);
        }
      }
    }

    _candidates = results;
  }

  /// Phân đoạn chuỗi pinyin thành các âm tiết hợp lệ
  static List<String> segmentPinyin(String text) {
    if (text.isEmpty) return const [];
    final syllables = <String>[];
    int start = 0;

    while (start < text.length) {
      int matchedLen = 0;
      // Tìm âm tiết dài nhất có trong từ điển (tối đa 6 ký tự như zhuang, shuang)
      for (int len = (text.length - start).clamp(0, 6); len >= 1; len--) {
        final sub = text.substring(start, start + len);
        if (PinyinDictionary.characters.containsKey(sub)) {
          matchedLen = len;
          syllables.add(sub);
          break;
        }
      }
      if (matchedLen > 0) {
        start += matchedLen;
      } else {
        // Ký tự không khớp âm tiết chuẩn -> coi như một ký tự đơn
        syllables.add(text[start]);
        start++;
      }
    }
    return syllables;
  }

  /// Hiển thị chuỗi pinyin có phân cách âm tiết (ví dụ: ni'hao)
  String _getFormattedPinyin() {
    final segs = segmentPinyin(_buffer);
    return segs.join("'");
  }
}
