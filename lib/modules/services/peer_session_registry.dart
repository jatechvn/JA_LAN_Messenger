import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/peer_model.dart';

/// A conversation owns transport sessions; an endpoint never owns history.
class PeerTransportSession {
  final String conversationId;
  final PeerModel remote;
  final String hash;
  bool available = true;
  PeerTransportSession(this.conversationId, this.remote, this.hash);
  String get endpoint => '${remote.ip}:${remote.port}';
}

class PeerSessionRegistry {
  final File file;
  final Map<String, String> identities = {};
  final Map<String, PeerTransportSession> sessions = {};
  PeerSessionRegistry(Directory historyDirectory)
    : file = File('${historyDirectory.path}/_peer_identity_index.json') {
    try {
      if (file.existsSync()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        identities.addAll((data['identities'] as Map).cast<String, String>());
      }
    } catch (e) {
      debugPrint('[PeerSessions] Cannot load identity index: ${e.runtimeType}');
    }
  }

  static String? identity(PeerModel peer) {
    final host = (peer.hostname ?? '').trim().toLowerCase();
    final account = (peer.accountName ?? '').trim().toLowerCase();
    if (host.isEmpty ||
        host == 'localhost' ||
        host == '???' ||
        account.isEmpty ||
        account == '???') {
      return null;
    }
    return '$account@$host';
  }

  void remember(String conversationId, String? identity) {
    if (identity == null || identities[conversationId] == identity) return;
    identities[conversationId] = identity;
    try {
      file.parent.createSync(recursive: true);
      final temporary = File('${file.path}.tmp');
      temporary.writeAsStringSync(
        jsonEncode({'identities': identities}),
        flush: true,
      );
      temporary.renameSync(file.path);
    } catch (e) {
      debugPrint('[PeerSessions] Cannot save identity index: ${e.runtimeType}');
    }
  }

  List<PeerTransportSession> forConversation(String id) =>
      sessions.values.where((s) => s.conversationId == id).toList()
        ..sort((a, b) {
          final type = (a.remote.isBeebeep ? 1 : 0).compareTo(
            b.remote.isBeebeep ? 1 : 0,
          );
          return type != 0 ? type : a.endpoint.compareTo(b.endpoint);
        });
}
