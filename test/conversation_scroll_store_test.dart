import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/conversation_scroll_store.dart';

void main() {
  test('fresh instances reload bottom and history state from disk', () {
    final dir = Directory.systemTemp.createTempSync('scroll_store_test_');
    final file = File('${dir.path}/scroll.json');
    final first = ConversationScrollStore(file);
    first.save('alice@pc', (offset: 1200, atBottom: true, separator: null));
    first.save('bob@pc', (offset: 400, atBottom: false, separator: '42'));
    final restarted = ConversationScrollStore(file);
    expect(restarted.read('alice@pc')?.atBottom, true);
    expect(restarted.read('bob@pc')?.offset, 400);
    restarted.save('alice@pc', (offset: 250, atBottom: false, separator: null));
    expect(ConversationScrollStore(file).read('alice@pc')?.atBottom, false);
    expect(ConversationScrollStore(file).read('bob@pc')?.separator, '42');
  });

  test('missing/corrupt/invalid state leaves first-visit behavior intact', () {
    final dir = Directory.systemTemp.createTempSync('scroll_store_invalid_');
    final file = File('${dir.path}/scroll.json');
    expect(ConversationScrollStore(file).read('a'), isNull);
    file.writeAsStringSync('{invalid');
    expect(ConversationScrollStore(file).read('a'), isNull);
    file.writeAsStringSync(
      '{"a":{"offset":-1,"atBottom":true},'
      '"b":{"offset":10,"atBottom":"true"}}',
    );
    final store = ConversationScrollStore(file);
    expect(store.read('a'), isNull);
    expect(store.read('b'), isNull);
  });
}
