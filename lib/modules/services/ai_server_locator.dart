import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../network/network_utils.dart';

/// Only accepts the named machine, never the first open Ollama port on the LAN.
class AiServerLocator {
  static const machineName = 'jaai-HP-Pro-Tower-280-G9-E-PCI-Desktop-PC';
  final Future<List<String>> Function(String) resolve;
  final Future<List<String>> Function(String) multicastResolve;
  final Future<String> Function(String) reverse;
  final Future<bool> Function(Uri) probe;
  final Duration budget;

  AiServerLocator({
    Future<List<String>> Function(String)? resolve,
    Future<List<String>> Function(String)? multicastResolve,
    Future<String> Function(String)? reverse,
    Future<bool> Function(Uri)? probe,
    this.budget = const Duration(seconds: 35),
  }) : resolve = resolve ?? _resolve,
       multicastResolve = multicastResolve ?? _multicastResolve,
       reverse = reverse ?? _reverse,
       probe = probe ?? _probe;

  Future<Uri?> locate(
    Uri old,
    List<String> subnets, {
    bool Function()? cancelled,
  }) async {
    final clock = Stopwatch()..start();
    bool stop() => clock.elapsed >= budget || (cancelled?.call() ?? false);
    final checked = <String>{};
    Uri endpoint(String ip) => old.replace(host: ip);
    bool matches(String host) =>
        host
            .toLowerCase()
            .replaceFirst(RegExp(r'\.local\.?$', caseSensitive: false), '')
            .replaceFirst(RegExp(r'\.$'), '') ==
        machineName.toLowerCase();
    Future<bool> valid(String ip) async {
      if (stop() || !checked.add(ip)) return false;
      try {
        return await probe(endpoint(ip)).timeout(const Duration(seconds: 2)) &&
            !stop();
      } catch (_) {
        return false;
      }
    }

    // DNS and mDNS cover Linux machines without requiring a Messenger install.
    final answers = await Future.wait([
      for (final host in [machineName, '$machineName.local'])
        resolve(host)
            .timeout(const Duration(seconds: 2))
            .catchError((Object _) => <String>[]),
      multicastResolve('$machineName.local')
          .timeout(const Duration(seconds: 3))
          .catchError((Object _) => <String>[]),
    ]);
    for (final ip in answers.expand((a) => a)) {
      if (await valid(ip)) return endpoint(ip);
    }
    if (cancelled?.call() ?? false) return null;
    // Fallback: bounded IPv4 LAN sweep, requiring reverse hostname identity.
    final hosts = <String>{};
    for (final subnet in subnets.toSet()) {
      if (NetworkUtils.subnetHostCount(subnet) > 4096) {
        throw const FormatException('AI scan subnet exceeds 4096 hosts');
      }
      hosts.addAll(NetworkUtils.subnetHosts(subnet));
    }
    if (hosts.isEmpty) throw StateError('No enabled LAN adapter for AI scan');
    final iterator = hosts.iterator;
    Uri? found;
    Future<void> worker() async {
      while (!stop() && found == null && iterator.moveNext()) {
        final ip = iterator.current;
        if (!await valid(ip)) continue;
        try {
          final name = await reverse(ip).timeout(const Duration(seconds: 1));
          if (!stop() && matches(name)) found ??= endpoint(ip);
        } catch (_) {}
      }
    }

    await Future.wait(List.generate(64, (_) => worker()));
    if (found == null && clock.elapsed >= budget) {
      throw TimeoutException('AI discovery timed out');
    }
    return found;
  }

  static Future<List<String>> _resolve(String host) async =>
      (await InternetAddress.lookup(
        host,
        type: InternetAddressType.IPv4,
      )).map((a) => a.address).toList();
  static Future<String> _reverse(String ip) async =>
      (await InternetAddress(ip).reverse()).host;
  static Future<bool> _probe(Uri endpoint) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    // Future.timeout alone does not cancel a server trickling bytes forever.
    final deadline = Timer(
      const Duration(seconds: 2),
      () => client.close(force: true),
    );
    try {
      final request = await client.getUrl(
        Uri.parse(
          '${endpoint.toString().replaceAll(RegExp(r'/+$'), '')}/api/tags',
        ),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      if (response.statusCode != 200) return false;
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 1))) {
        bytes.addAll(chunk);
        if (bytes.length > 1024 * 1024) return false;
      }
      return (jsonDecode(utf8.decode(bytes)) as Map)['models'] is List;
    } catch (_) {
      return false;
    } finally {
      deadline.cancel();
      client.close(force: true);
    }
  }

  static Future<List<String>> _multicastResolve(String host) async {
    final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final result = <String>{};
    final query = <int>[0, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0];
    for (final label in host.split('.')) {
      query.addAll([label.length, ...ascii.encode(label)]);
    }
    query.addAll([
      0,
      0,
      1,
      0,
      1,
    ]); // Legacy mDNS A query; replies unicast to port.
    final subscription = socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      Datagram? packet;
      while ((packet = socket.receive()) != null) {
        result.addAll(parseMdnsAnswers(packet!.data, host));
      }
    });
    try {
      socket.send(query, InternetAddress('224.0.0.251'), 5353);
      await Future<void>.delayed(const Duration(seconds: 2));
      return result.toList();
    } finally {
      await subscription.cancel();
      socket.close();
    }
  }

  /// Reads compressed DNS names defensively; accepts A records for exact host.
  static List<String> parseMdnsAnswers(List<int> bytes, String host) {
    int u16(int p) => (bytes[p] << 8) | bytes[p + 1];
    (String, int) name(int start) {
      var p = start;
      int? end;
      final labels = <String>[];
      final visited = <int>{};
      while (visited.add(p)) {
        final length = bytes[p++];
        if (length == 0) return (labels.join('.'), end ?? p);
        if ((length & 0xc0) == 0xc0) {
          end ??= p + 1;
          p = ((length & 0x3f) << 8) | bytes[p];
        } else {
          if (length > 63) throw const FormatException('Invalid DNS label');
          labels.add(ascii.decode(bytes.sublist(p, p + length)));
          p += length;
        }
      }
      throw const FormatException('DNS compression loop');
    }

    try {
      if (bytes.length < 12 || (bytes[2] & 0x80) == 0) return [];
      var p = 12;
      for (var i = 0; i < u16(4); i++) {
        p = name(p).$2 + 4;
      }
      final ips = <String>[];
      final count = u16(6) + u16(8) + u16(10);
      for (var i = 0; i < count; i++) {
        final record = name(p);
        p = record.$2;
        final type = u16(p);
        final recordClass = u16(p + 2) & 0x7fff;
        final length = u16(p + 8);
        p += 10;
        if (type == 1 &&
            recordClass == 1 &&
            length == 4 &&
            record.$1.toLowerCase() == host.toLowerCase()) {
          ips.add(bytes.sublist(p, p + 4).join('.'));
        }
        p += length;
        if (p > bytes.length) return [];
      }
      return ips;
    } catch (_) {
      return [];
    }
  }
}
