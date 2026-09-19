import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/ime/chinese_pinyin_engine.dart';

void main() {
  group('Chinese Pinyin Engine Tests', () {
    late ChinesePinyinEngine engine;

    setUp(() {
      engine = ChinesePinyinEngine();
    });

    test('Pinyin Syllable Segmentation', () {
      final segs1 = ChinesePinyinEngine.segmentPinyin('nihao');
      expect(segs1, equals(['ni', 'hao']));

      final segs2 = ChinesePinyinEngine.segmentPinyin('xiexie');
      expect(segs2, equals(['xie', 'xie']));

      final segs3 = ChinesePinyinEngine.segmentPinyin('zhongguo');
      expect(segs3, equals(['zhong', 'guo']));
    });

    test('Candidates Generation for common words', () {
      // Gõ 'n' 'i' 'h' 'a' 'o'
      for (final ch in 'nihao'.split('')) {
        engine.addChar(ch);
      }
      expect(engine.buffer, equals('nihao'));
      expect(engine.hasCandidates, isTrue);

      final candidates = engine.getCurrentPageCandidates();
      expect(candidates.isNotEmpty, isTrue);
      // Ứng cử viên số 1 phải là '你好'
      expect(candidates.first.text, equals('你好'));

      // Chọn ứng cử viên 1
      final committed = engine.selectCandidate(1);
      expect(committed, equals('你好'));
      expect(engine.buffer, isEmpty);
      expect(engine.hasCandidates, isFalse);
    });

    test('Candidates Generation for xiexie', () {
      for (final ch in 'xiexie'.split('')) {
        engine.addChar(ch);
      }
      expect(engine.getCurrentPageCandidates().first.text, equals('谢谢'));
    });

    test('Backspace removes last letter', () {
      for (final ch in 'nih'.split('')) {
        engine.addChar(ch);
      }
      expect(engine.buffer, equals('nih'));

      engine.backspace();
      expect(engine.buffer, equals('ni'));
      expect(engine.hasCandidates, isTrue);
      expect(engine.getCurrentPageCandidates().any((c) => c.text == '你'), isTrue);
    });

    test('Pagination Next and Prev Page', () {
      // 'shi' có nhiều ứng viên
      for (final ch in 'shi'.split('')) {
        engine.addChar(ch);
      }
      expect(engine.totalPages, greaterThan(1));
      expect(engine.pageIndex, equals(0));

      final page0First = engine.getCurrentPageCandidates().first.text;
      final movedNext = engine.nextPage();
      expect(movedNext, isTrue);
      expect(engine.pageIndex, equals(1));

      final page1First = engine.getCurrentPageCandidates().first.text;
      expect(page1First, isNot(equals(page0First)));

      final movedPrev = engine.prevPage();
      expect(movedPrev, isTrue);
      expect(engine.pageIndex, equals(0));
    });

    test('Clear resets buffer and candidates', () {
      for (final ch in 'test'.split('')) {
        engine.addChar(ch);
      }
      expect(engine.buffer, equals('test'));
      engine.clear();
      expect(engine.buffer, isEmpty);
      expect(engine.hasCandidates, isFalse);
    });
  });
}
