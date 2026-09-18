import 'dart:async';
import 'network_utils.dart';

/// Streams a CIDR without allocating a host list or depending on ARP entries.
class SubnetSweep {
  bool _cancelled = false;
  final _cancelSignal = Completer<bool>();
  void cancel() {
    _cancelled = true;
    if (!_cancelSignal.isCompleted) _cancelSignal.complete(false);
  }

  Future<({int attempted, int sent, bool cancelled})> run({
    required List<NetworkInterfaceDetails> adapters,
    required Set<String> localIps,
    required FutureOr<bool> Function(
      NetworkInterfaceDetails adapter,
      String target,
    )
    send,
    void Function(int attempted, int total, int sent)? onProgress,
    int batchSize = 32,
    Duration probeTimeout = const Duration(seconds: 16),
    Duration interval = const Duration(milliseconds: 40),
  }) async {
    if (batchSize <= 0 ||
        interval.isNegative ||
        probeTimeout <= Duration.zero) {
      throw ArgumentError('Invalid sweep pacing');
    }
    final total = adapters.fold<int>(
      0,
      (sum, a) => sum + NetworkUtils.subnetHostCount(a.subnet),
    );
    var attempted = 0, sent = 0;
    Iterable<(NetworkInterfaceDetails, String)> targets() sync* {
      for (final adapter in adapters) {
        for (final ip in NetworkUtils.subnetHosts(adapter.subnet)) {
          yield (adapter, ip);
        }
      }
    }

    final iterator = targets().iterator;
    Future<void> worker() async {
      while (!_cancelled && iterator.moveNext()) {
        final (adapter, ip) = iterator.current;
        if (!localIps.contains(ip)) {
          try {
            final result = await Future.any<bool>([
              Future<bool>.sync(
                () => send(adapter, ip),
              ).timeout(probeTimeout, onTimeout: () => false),
              _cancelSignal.future,
            ]);
            if (result) sent++;
          } catch (_) {}
        }
        attempted++;
        if (_cancelled) return;
        onProgress?.call(attempted, total, sent);
        await Future<void>.delayed(interval);
      }
    }

    onProgress?.call(0, total, 0);
    await Future.wait(List.generate(batchSize, (_) => worker()));
    return (attempted: attempted, sent: sent, cancelled: _cancelled);
  }
}
