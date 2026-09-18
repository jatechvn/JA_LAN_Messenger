import 'dart:convert';
import 'dart:io';

/// Disabled names survive DHCP changes; newly added adapters default to enabled.
class NetworkPreferences {
  final File file;
  Set<String> disabledNames = {};
  NetworkPreferences({File? file})
    : file =
          file ??
          File(
            '${Platform.environment['APPDATA'] ?? Directory.current.path}/JA_LAN_Messenger/network_preferences.json',
          );
  Future<void> load() async {
    if (!await file.exists()) return;
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    disabledNames = (data['disabledAdapters'] as List).cast<String>().toSet();
  }

  Future<void> save(Set<String> names) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'disabledAdapters': names.toList()}),
      flush: true,
    );
    disabledNames = Set.of(names);
  }
}
