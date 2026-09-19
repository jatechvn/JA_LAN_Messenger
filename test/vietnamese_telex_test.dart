import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/ime/vietnamese_telex_engine.dart';

void main() {
  group('Vietnamese Telex Engine Tests', () {
    test('Repositions tones while typing actual key sequences', () {
      const cases = {
        'tieesng': 'tiếng',
        'tieengs': 'tiếng',
        'tiseeng': 'tiếng',
        'TIEESNG': 'TIẾNG',
        'vieejt': 'việt',
        'hoafn': 'hoàn',
        'quas': 'quá',
        'quys': 'quý',
        'gias': 'giá',
        'gif': 'gì',
        'thuyr': 'thủy',
      };
      for (final entry in cases.entries) {
        var word = '';
        for (final key in entry.key.split('')) {
          word = VietnameseTelexEngine.processWord(word, key) ?? '$word$key';
        }
        expect(word, entry.value, reason: entry.key);
      }
      var sentence = '';
      for (final key in 'gox thuwr tieesng vieejt'.split('')) {
        final segment = VietnameseTelexEngine.extractWordAtCursor(
          sentence,
          sentence.length,
        );
        final transformed = VietnameseTelexEngine.processWord(
          segment.word,
          key,
        );
        sentence = transformed == null
            ? '$sentence$key'
            : sentence.replaceRange(segment.start, segment.end, transformed);
      }
      expect(sentence, 'gõ thử tiếng việt');
    });
    test('Vowel and Consonant Modifications', () {
      // d + d -> đ
      expect(VietnameseTelexEngine.processWord('d', 'd'), equals('đ'));
      expect(VietnameseTelexEngine.processWord('D', 'd'), equals('Đ'));
      // a + a -> â
      expect(VietnameseTelexEngine.processWord('a', 'a'), equals('â'));
      // a + w -> ă
      expect(VietnameseTelexEngine.processWord('a', 'w'), equals('ă'));
      // e + e -> ê
      expect(VietnameseTelexEngine.processWord('e', 'e'), equals('ê'));
      // o + o -> ô
      expect(VietnameseTelexEngine.processWord('o', 'o'), equals('ô'));
      // o + w -> ơ
      expect(VietnameseTelexEngine.processWord('o', 'w'), equals('ơ'));
      // u + w -> ư
      expect(VietnameseTelexEngine.processWord('u', 'w'), equals('ư'));
      // uo + w -> ươ
      expect(VietnameseTelexEngine.processWord('uo', 'w'), equals('ươ'));
      expect(VietnameseTelexEngine.processWord('duong', 'w'), equals('dương'));
      expect(VietnameseTelexEngine.processWord('đuong', 'w'), equals('đương'));
    });

    test('Tone Placement and Rules (EVKey Standard)', () {
      // Sắc (s), Huyền (f), Hỏi (r), Ngã (x), Nặng (j)
      // tiêng + s -> tiếng (tieng + s -> tiéng)
      expect(VietnameseTelexEngine.processWord('tiêng', 's'), equals('tiếng'));
      expect(VietnameseTelexEngine.processWord('tieng', 's'), equals('tiéng'));
      // viêt + j -> việt (viet + j -> viẹt)
      expect(VietnameseTelexEngine.processWord('viêt', 'j'), equals('việt'));
      expect(VietnameseTelexEngine.processWord('viet', 'j'), equals('viẹt'));
      // hoang + f -> hoàng
      expect(VietnameseTelexEngine.processWord('hoang', 'f'), equals('hoàng'));
      // thuy + r -> thủy
      expect(VietnameseTelexEngine.processWord('thuy', 'r'), equals('thủy'));
      // hoa + f -> hòa
      expect(VietnameseTelexEngine.processWord('hoa', 'f'), equals('hòa'));
      // khoe + r -> khỏe
      expect(VietnameseTelexEngine.processWord('khoe', 'r'), equals('khỏe'));
      // mia + s -> mía
      expect(VietnameseTelexEngine.processWord('mia', 's'), equals('mía'));
      // lưa + r -> lửa, lua + r -> lủa
      expect(VietnameseTelexEngine.processWord('lưa', 'r'), equals('lửa'));
      expect(VietnameseTelexEngine.processWord('lua', 'r'), equals('lủa'));
      // nguoi + f -> người
      expect(VietnameseTelexEngine.processWord('ngươi', 'f'), equals('người'));
    });

    test('Tone Repositioning when Consonant is Appended', () {
      // hoa + f -> hoà / hòa
      final hoaWithTone = VietnameseTelexEngine.processWord('hoa', 'f')!;
      expect(hoaWithTone, equals('hòa'));
      // Khi gõ thêm 'n': hoan + f -> hoàn
      final hoanWithTone = VietnameseTelexEngine.processWord('hoan', 'f')!;
      expect(hoanWithTone, equals('hoàn'));
    });

    test('Undo / Revert on repeated key', () {
      // toán + s -> toans
      expect(VietnameseTelexEngine.processWord('toán', 's'), equals('toans'));
      // đ + d -> dd
      expect(VietnameseTelexEngine.processWord('đ', 'd'), equals('dd'));
      // â + a -> aa
      expect(VietnameseTelexEngine.processWord('â', 'a'), equals('aa'));
      // ă + w -> aw
      expect(VietnameseTelexEngine.processWord('ă', 'w'), equals('aw'));
      // ê + e -> ee
      expect(VietnameseTelexEngine.processWord('ê', 'e'), equals('ee'));
      // ô + o -> oo
      expect(VietnameseTelexEngine.processWord('ô', 'o'), equals('oo'));
      // ơ + w -> ow
      expect(VietnameseTelexEngine.processWord('ơ', 'w'), equals('ow'));
      // ư + w -> uw
      expect(VietnameseTelexEngine.processWord('ư', 'w'), equals('uw'));
      // ươ + w -> uow
      expect(VietnameseTelexEngine.processWord('ươ', 'w'), equals('uow'));
    });

    test('Case Preservation', () {
      expect(VietnameseTelexEngine.processWord('VIÊT', 'j'), equals('VIỆT'));
      expect(VietnameseTelexEngine.processWord('Viêt', 'j'), equals('Việt'));
      expect(VietnameseTelexEngine.processWord('DUONG', 'w'), equals('DƯƠNG'));
      expect(VietnameseTelexEngine.processWord('ĐUONG', 'w'), equals('ĐƯƠNG'));
    });

    test('Word Boundary Extraction at Cursor', () {
      const text = 'Xin chào các bạn đang online!';
      // Cursor ở cuối chữ 'chào' (offset 8)
      final seg1 = VietnameseTelexEngine.extractWordAtCursor(text, 8);
      expect(seg1.word, equals('chào'));
      expect(seg1.start, equals(4));
      expect(seg1.end, equals(8));

      // Cursor ở cuối 'bạn' (offset 16)
      final seg2 = VietnameseTelexEngine.extractWordAtCursor(text, 16);
      expect(seg2.word, equals('bạn'));
    });
  });
}
