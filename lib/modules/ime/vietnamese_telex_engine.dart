class VietnameseTelexEngine {
  // Bảng ánh xạ nguyên âm có dấu thanh
  static const Map<String, List<String>> _vowelToneMap = {
    // raw: [none, sac, huyen, hoi, nga, nang]
    'a': ['a', 'á', 'à', 'ả', 'ã', 'ạ'],
    'ă': ['ă', 'ắ', 'ằ', 'ẳ', 'ẵ', 'ặ'],
    'â': ['â', 'ấ', 'ầ', 'ẩ', 'ẫ', 'ậ'],
    'e': ['e', 'é', 'è', 'ẻ', 'ẽ', 'ẹ'],
    'ê': ['ê', 'ế', 'ề', 'ể', 'ễ', 'ệ'],
    'i': ['i', 'í', 'ì', 'ỉ', 'ĩ', 'ị'],
    'o': ['o', 'ó', 'ò', 'ỏ', 'õ', 'ọ'],
    'ô': ['ô', 'ố', 'ồ', 'ổ', 'ỗ', 'ộ'],
    'ơ': ['ơ', 'ớ', 'ờ', 'ở', 'ỡ', 'ợ'],
    'u': ['u', 'ú', 'ù', 'ủ', 'ũ', 'ụ'],
    'ư': ['ư', 'ứ', 'ừ', 'ử', 'ữ', 'ự'],
    'y': ['y', 'ý', 'ỳ', 'ỷ', 'ỹ', 'ỵ'],
  };

  // Tra cứu ngược ký tự có dấu về [nguyên âm gốc, chỉ số dấu (0-5)]
  static final Map<String, _CharToneInfo> _charToToneInfo = _buildCharToneMap();

  static Map<String, _CharToneInfo> _buildCharToneMap() {
    final map = <String, _CharToneInfo>{};
    _vowelToneMap.forEach((base, forms) {
      for (int tone = 0; tone < forms.length; tone++) {
        final lower = forms[tone];
        final upper = lower.toUpperCase();
        map[lower] = _CharToneInfo(base, tone, isUpper: false);
        map[upper] = _CharToneInfo(base, tone, isUpper: true);
      }
    });
    return map;
  }

  /// Xử lý một từ (word) khi người dùng gõ thêm một ký tự mới `keyChar`.
  /// Trả về từ sau biến đổi, hoặc null nếu không có biến đổi nào.
  static String? processWord(String word, String keyChar) {
    if (keyChar.length != 1) return null;
    final lowerKey = keyChar.toLowerCase();

    // 1. Kiểm tra xem ký tự mới có phải là phím dấu Telex không:
    // s = sắc (1), f = huyền (2), r = hỏi (3), x = ngã (4), j = nặng (5), z = xóa dấu (0)
    final toneIndex = _getToneFromKey(lowerKey);
    if (toneIndex != null) {
      return _applyTone(word, toneIndex, keyChar);
    }

    // 2. Kiểm tra xem có phải là phím biến âm (aa, aw, ee, oo, ow, uw, w, dd):
    final vowelMod = _applyVowelModification(word, keyChar);
    if (vowelMod != null) {
      return _repositionTone(vowelMod);
    }

    if (_isWordChar(keyChar)) {
      final appended = '$word$keyChar';
      final corrected = _repositionTone(appended);
      if (corrected != appended) return corrected;
    }
    return null;
  }

  static String _repositionTone(String word) {
    for (final ch in word.split('')) {
      final tone = _charToToneInfo[ch]?.tone ?? 0;
      if (tone > 0) {
        return _applyTone(_removeAllTones(word), tone, '') ?? word;
      }
    }
    return word;
  }

  /// Trả về tone index (0..5) từ phím gõ, hoặc null nếu không phải phím dấu
  static int? _getToneFromKey(String key) {
    switch (key) {
      case 'z':
        return 0; // xóa dấu
      case 's':
        return 1; // sắc
      case 'f':
        return 2; // huyền
      case 'r':
        return 3; // hỏi
      case 'x':
        return 4; // ngã
      case 'j':
        return 5; // nặng
      default:
        return null;
    }
  }

  /// Áp dụng dấu thanh lên từ
  static String? _applyTone(String word, int newTone, String keyChar) {
    if (word.isEmpty) return null;

    // Tìm tất cả các vị trí nguyên âm trong từ
    final vowelIndices = <int>[];
    int currentTone = 0;

    for (int i = 0; i < word.length; i++) {
      final ch = word[i];
      final info = _charToToneInfo[ch];
      if (info != null) {
        vowelIndices.add(i);
        if (info.tone > 0) {
          currentTone = info.tone;
        }
      }
    }

    if (vowelIndices.isEmpty) {
      return null; // Không có nguyên âm thì không bỏ dấu
    }

    // Nếu gõ lại đúng dấu đang có -> UNDO: Gỡ dấu và chèn lại phím dấu raw (ví dụ: toán + s -> toans)
    if (newTone > 0 && currentTone == newTone) {
      final stripped = _removeAllTones(word);
      return '$stripped$keyChar';
    }

    // Gỡ toàn bộ dấu cũ trên các nguyên âm
    final strippedWord = _removeAllTones(word);

    if (newTone == 0) {
      // Phím 'z' chỉ để xóa dấu
      return currentTone == 0 ? null : strippedWord;
    }

    // Xác định vị trí nguyên âm chính cần đặt dấu (EVKey standard)
    final targetIndex = _determineAccentPosition(strippedWord, vowelIndices);
    if (targetIndex < 0 || targetIndex >= word.length) return null;

    // Đặt dấu mới vào vị trí đó
    final sb = StringBuffer();
    for (int i = 0; i < strippedWord.length; i++) {
      if (i == targetIndex) {
        final ch = strippedWord[i];
        final info = _charToToneInfo[ch];
        if (info != null) {
          final baseVowel = info.baseVowel;
          final toneForms = _vowelToneMap[baseVowel];
          if (toneForms != null && newTone < toneForms.length) {
            final markedChar = toneForms[newTone];
            sb.write(info.isUpper ? markedChar.toUpperCase() : markedChar);
            continue;
          }
        }
      }
      sb.write(strippedWord[i]);
    }

    return sb.toString();
  }

  /// Bỏ tất cả các dấu thanh (sắc, huyền, hỏi, ngã, nặng) nhưng giữ nguyên mũ/móc (â, ă, ê, ô, ơ, ư, đ)
  static String _removeAllTones(String word) {
    final sb = StringBuffer();
    for (int i = 0; i < word.length; i++) {
      final ch = word[i];
      final info = _charToToneInfo[ch];
      if (info != null) {
        final base = info.baseVowel;
        sb.write(info.isUpper ? base.toUpperCase() : base);
      } else {
        sb.write(ch);
      }
    }
    return sb.toString();
  }

  /// Xác định vị trí nguyên âm nhận dấu theo chuẩn chính tả tiếng Việt mới (EVKey)
  static int _determineAccentPosition(
    String strippedWord,
    List<int> vowelIndices,
  ) {
    if (vowelIndices.isEmpty) return -1;
    if (vowelIndices.length == 1) return vowelIndices.first;

    final lower = strippedWord.toLowerCase();
    vowelIndices = _nucleus(strippedWord);
    // ê and ơ carry the tone even before the final consonant is typed.
    for (final index in vowelIndices.reversed) {
      if (lower[index] == 'ê' || lower[index] == 'ơ') return index;
    }
    final lastVowelIndex = vowelIndices.last;

    // Kiểm tra xem sau nguyên âm cuối có phụ âm cuối hay không
    final hasFinalConsonant = lastVowelIndex < strippedWord.length - 1;

    // Trường hợp 1: Có phụ âm cuối (ví dụ: toán, hoàng, tiếng, nghiệp, quyên, quất)
    if (hasFinalConsonant) {
      // Dấu luôn đặt trên nguyên âm đứng ngay sát phụ âm cuối
      // Trừ trường hợp các nguyên âm đôi đặc biệt:
      // Trong 'ươ' + phụ âm (ví dụ: trường, mượn) -> đặt ở 'ơ'
      // Trong 'iê' + phụ âm (ví dụ: tiếng) -> đặt ở 'ê'
      // Trong 'uô' + phụ âm (ví dụ: muốn) -> đặt ở 'ô'
      return lastVowelIndex;
    }

    // Trường hợp 2: Từ kết thúc bằng nguyên âm mở (không có phụ âm cuối)
    final vowelCluster = vowelIndices.map((i) => lower[i]).join();

    if (vowelCluster.length == 2) {
      // oa, oe, uy: chuẩn EVKey đặt ở âm đầu (hòa, khóe, thủy, thúy)
      if (vowelCluster == 'oa' ||
          vowelCluster == 'oe' ||
          vowelCluster == 'uy') {
        return vowelIndices[0];
      }
      // ia, ya, ua, ưa -> đặt ở âm thứ nhất: mía, tía, múa, lửa, chứa
      if (vowelCluster == 'ia' ||
          vowelCluster == 'ya' ||
          vowelCluster == 'ua' ||
          vowelCluster == 'ưa') {
        return vowelIndices[0];
      }
      // ươ (ví dụ: hươu -> có phụ âm u, nhưng nếu chỉ là ưa/ươ mở)
      if (vowelCluster == 'ươ') {
        return vowelIndices[1];
      }
      // Mặc định cho 2 nguyên âm mở khác (ai, ao, au, ay, âu, ây, eo, êu, oi, ôi, ơi, ui, ưi): đặt âm đầu
      return vowelIndices[0];
    }

    if (vowelCluster.length == 3) {
      // uôi, ươi, oai, oay, uya: đặt ở âm giữa
      return vowelIndices[1];
    }

    return lastVowelIndex;
  }

  /// Biến đổi mũ và móc: aa, aw, ee, oo, ow, uw, w, dd
  /// Recalculate the remaining syllable, without reconstructing raw keys.
  static String repositionAfterDeletion(String word) => _repositionTone(word);

  static List<int> _nucleus(String word) {
    final indices = <int>[];
    for (var i = 0; i < word.length; i++) {
      if (_charToToneInfo.containsKey(word[i])) indices.add(i);
    }
    final lower = word.toLowerCase();
    if (indices.length > 1 &&
        indices.first == 1 &&
        (lower.startsWith('qu') || lower.startsWith('gi'))) {
      indices.removeAt(0);
    }
    return indices;
  }

  static bool _validTail(String word, int lastVowel) {
    final tail = word.substring(lastVowel + 1).toLowerCase();
    return tail.isEmpty ||
        const {'c', 'ch', 'm', 'n', 'ng', 'nh', 'p', 't'}.contains(tail);
  }

  static String _replaceBase(String word, int index, String base) {
    final info = _charToToneInfo[word[index]]!;
    final marked = _vowelToneMap[base]![info.tone];
    return word.replaceRange(
      index,
      index + 1,
      info.isUpper ? marked.toUpperCase() : marked,
    );
  }

  static String? _applyVowelModification(String word, String keyChar) {
    final key = keyChar.toLowerCase();
    if (word.isEmpty) {
      return key == 'w' ? (keyChar == 'W' ? 'Ư' : 'ư') : null;
    }
    if (key == 'd') {
      final last = word[word.length - 1];
      if (last.toLowerCase() == 'd') {
        return word.substring(0, word.length - 1) + (last == 'D' ? 'Đ' : 'đ');
      }
      if (last.toLowerCase() == 'đ') {
        return word.substring(0, word.length - 1) +
            (last == 'Đ' ? 'D' : 'd') +
            keyChar;
      }
      return null;
    }
    final vowels = _nucleus(word);
    if (vowels.isEmpty) {
      return key == 'w' ? word + (keyChar == 'W' ? 'Ư' : 'ư') : null;
    }
    if (!_validTail(word, vowels.last)) return null;
    final index = vowels.last;
    final base = _charToToneInfo[word[index]]!.baseVowel;
    const roofs = {'a': 'â', 'e': 'ê', 'o': 'ô'};
    final roof = roofs[key];
    if (roof != null) {
      if (base == key) return _replaceBase(word, index, roof);
      if (base == roof) {
        return _replaceBase(_removeAllTones(word), index, key) + keyChar;
      }
      return null;
    }
    if (key != 'w') return null;
    // uo/uô/uơ/ươ are transitions of a vowel pair, independent of tone.
    if (vowels.length >= 2) {
      final u = vowels[vowels.length - 2];
      final o = vowels.last;
      final uBase = _charToToneInfo[word[u]]!.baseVowel;
      if (o == u + 1 &&
          (uBase == 'u' || uBase == 'ư') &&
          const {'o', 'ô', 'ơ'}.contains(base)) {
        if (uBase == 'ư' && base == 'ơ') {
          var result = _removeAllTones(word);
          result = _replaceBase(result, u, 'u');
          return _replaceBase(result, o, 'o') + keyChar;
        }
        return _replaceBase(_replaceBase(word, u, 'ư'), o, 'ơ');
      }
    }
    const hooks = {'a': 'ă', 'o': 'ơ', 'u': 'ư'};
    final hooked = hooks[base];
    if (hooked != null) return _replaceBase(word, index, hooked);
    for (final entry in hooks.entries) {
      if (base == entry.value) {
        return _replaceBase(_removeAllTones(word), index, entry.key) + keyChar;
      }
    }
    return null;
  }

  /// Tách vị trí ranh giới từ (word boundary) kết thúc tại cursor
  static WordSegment extractWordAtCursor(String text, int cursor) {
    if (cursor <= 0 || text.isEmpty) {
      return const WordSegment('', 0, 0);
    }
    int start = cursor - 1;
    while (start >= 0) {
      final ch = text[start];
      if (_isWordChar(ch)) {
        start--;
      } else {
        break;
      }
    }
    start++; // Đưa về vị trí ký tự đầu tiên của từ
    final word = text.substring(start, cursor);
    return WordSegment(word, start, cursor);
  }

  static bool _isWordChar(String ch) {
    final code = ch.codeUnitAt(0);
    // Ký tự chữ cái thông thường
    if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return true;
    // Ký tự tiếng Việt có dấu trong bảng Unicode Latin mở rộng
    if (_charToToneInfo.containsKey(ch)) return true;
    if (ch == 'đ' || ch == 'Đ') return true;
    return false;
  }
}

class _CharToneInfo {
  final String baseVowel;
  final int tone; // 0=none, 1=sac, 2=huyen, 3=hoi, 4=nga, 5=nang
  final bool isUpper;
  const _CharToneInfo(this.baseVowel, this.tone, {required this.isUpper});
}

class WordSegment {
  final String word;
  final int start;
  final int end;
  const WordSegment(this.word, this.start, this.end);
}
