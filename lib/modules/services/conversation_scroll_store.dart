import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

typedef ConversationScrollPosition = ({
  double offset,
  bool atBottom,
  String? separator,
});

/// Small UI-state sidecar; never writes chat history or read receipts.
class ConversationScrollStore {
  ConversationScrollStore(this.file) {
    try {
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync());
      if (data is! Map) return;
      for (final entry in data.entries) {
        final value = entry.value;
        if (entry.key is! String || value is! Map) continue;
        final offset = value['offset'];
        if (offset is! num ||
            !offset.isFinite ||
            offset < 0 ||
            value['atBottom'] is! bool) {
          continue;
        }
        _positions[entry.key as String] = (
          offset: offset.toDouble(),
          atBottom: value['atBottom'] as bool,
          separator: value['separator'] is String
              ? value['separator'] as String
              : null,
        );
      }
    } catch (error) {
      debugPrint('[ScrollStore] Load: $error');
    }
  }

  final File file;
  final _positions = <String, ConversationScrollPosition>{};

  ConversationScrollPosition? read(String key) => _positions[key];

  void save(String key, ConversationScrollPosition position) {
    if (_positions[key] == position) return;
    _positions[key] = position;
    try {
      file.parent.createSync(recursive: true);
      final temporary = File('${file.path}.tmp');
      temporary.writeAsStringSync(
        jsonEncode(
          _positions.map(
            (key, value) => MapEntry(key, {
              'offset': value.offset,
              'atBottom': value.atBottom,
              'separator': value.separator,
            }),
          ),
        ),
        flush: true,
      );
      temporary.renameSync(file.path);
    } catch (error) {
      debugPrint('[ScrollStore] Save: $error');
    }
  }
}
