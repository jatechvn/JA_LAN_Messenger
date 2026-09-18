import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/network_preferences.dart';

void main() {
  test(
    'defaults all enabled and persists disabled cards across restarts',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'network_preferences_test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/settings.json');
      final first = NetworkPreferences(file: file);
      await first.load();
      expect(first.disabledNames, isEmpty);
      await first.save({'Ethernet', 'Tailscale'});
      final restarted = NetworkPreferences(file: file);
      await restarted.load();
      expect(restarted.disabledNames, {'Ethernet', 'Tailscale'});
      expect(restarted.disabledNames.contains('Ethernet 2'), false);
      await restarted.save({});
      await first.load();
      expect(first.disabledNames, isEmpty);
    },
  );
}
