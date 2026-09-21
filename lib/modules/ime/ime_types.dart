enum ImeMode {
  auto('auto'),
  telex('telex'),
  pinyin('pinyin'),
  off('off');

  final String id;
  const ImeMode(this.id);

  static ImeMode fromId(String? id) {
    if (id == null) return ImeMode.auto;
    for (final mode in ImeMode.values) {
      if (mode.id == id.toLowerCase()) return mode;
    }
    return ImeMode.auto;
  }
}

enum ImeEngineState { active, bypassedExternal, disabledManual }

class PinyinCandidate {
  final String text;
  final String pinyin;
  final int index;

  const PinyinCandidate({
    required this.text,
    required this.pinyin,
    required this.index,
  });

  @override
  String toString() => '$index. $text ($pinyin)';
}
