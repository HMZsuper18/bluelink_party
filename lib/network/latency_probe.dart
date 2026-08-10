import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'protocol.dart';
import 'udp_session.dart';

/// Windowed RTT tracking for the PING/PONG echo protocol. Because the PONG
/// echoes the original timestamp, no in-flight bookkeeping is required: the
/// receiver simply computes `now - ts`.
class LatencyProbe {
  LatencyProbe({required this.session});

  final UdpSession session;
  final Map<String, _LatencyWindow> _windows = {};
  final Map<String, int> _sequenceNumbers = {};
  Timer? _timer;
  bool _running = false;

  final StreamController<void> _samples =
      StreamController<void>.broadcast();

  /// Emits a tick whenever a fresh RTT sample is recorded for any peer.
  Stream<void> get onSample => _samples.stream;

  String _key(InternetAddress address, int port) => '${address.address}:$port';

  bool hasPeer(InternetAddress address, int port) =>
      _windows.containsKey(_key(address, port));

  void trackPeer(InternetAddress address, int port) {
    _windows.putIfAbsent(_key(address, port), _LatencyWindow.new);
  }

  void untrackPeer(InternetAddress address, int port) {
    _windows.remove(_key(address, port));
  }

  int? averageFor(InternetAddress address, int port) {
    final window = _windows[_key(address, port)];
    if (window == null || window.isEmpty) return null;
    return window.average;
  }

  void start({Duration interval = NetConstants.pingInterval}) {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(interval, (_) => _pingAll());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void _pingAll() {
    for (final entry in _windows.entries) {
      final parts = entry.key.split(':');
      final port = int.tryParse(parts.last) ?? 0;
      final addr = InternetAddress.tryParse(parts.first);
      if (addr == null) continue;
      _sendPing(addr, port);
    }
  }

  void sendPingNow(InternetAddress address, int port) {
    if (!hasPeer(address, port)) return;
    _sendPing(address, port);
  }

  void _sendPing(InternetAddress address, int port) {
    final seq = (_sequenceNumbers[address.address] ?? 0) + 1;
    _sequenceNumbers[address.address] = seq;
    final packet = WirePacket(
      type: PacketType.ping,
      payload: PacketPayload.ping(seq: seq),
    );
    session.send(packet.encode(), address, port);
  }

  /// Builds the PONG echo for an incoming PING.
  static Uint8List pongFor(WirePacket ping) {
    return WirePacket(type: PacketType.pong, payload: ping.payload).encode();
  }

  /// Records an incoming PONG. Returns the freshly measured RTT in ms, or null
  /// when the sample is stale/unknown.
  int? recordPong({
    required WirePacket pong,
    required InternetAddress from,
    required int port,
  }) {
    final ts = pong.payload['ts'];
    if (ts is! int) return null;

    final key = _key(from, port);
    if (!_windows.containsKey(key)) return null;

    final now = DateTime.now().microsecondsSinceEpoch;
    final rtt = ((now - ts) / 1000).round();
    if (rtt < 0 || rtt > 3000) return null;

    _windows[key]!.add(rtt);
    if (_samples.hasListener) {
      _samples.add(null);
    }
    return rtt;
  }

  bool get isRunning => _running;

  void dispose() {
    stop();
    _windows.clear();
    _sequenceNumbers.clear();
    if (!_samples.isClosed) {
      _samples.close();
    }
  }
}

class _LatencyWindow {
  static const int _maxSamples = 5;

  final List<int> _samples = [];
  int latest = -1;

  bool get isEmpty => _samples.isEmpty;

  int get average {
    if (_samples.isEmpty) return -1;
    var sum = 0;
    for (final s in _samples) {
      sum += s;
    }
    return (sum / _samples.length).round();
  }

  void add(int rttMs) {
    latest = rttMs;
    _samples.add(rttMs);
    if (_samples.length > _maxSamples) {
      _samples.removeAt(0);
    }
  }
}
