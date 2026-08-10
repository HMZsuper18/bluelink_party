import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A decoded datagram received on the UDP socket.
@immutable
class ReceivedPacket {
  const ReceivedPacket({
    required this.data,
    required this.address,
    required this.port,
  });

  final Uint8List data;
  final InternetAddress address;
  final int port;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReceivedPacket &&
          other.data == data &&
          other.address == address &&
          other.port == port;

  @override
  int get hashCode => Object.hash(data, address, port);
}

/// Owns the raw `RawDatagramSocket` lifecycle: bind, single receive loop,
/// broadcast sends, and orderly teardown. One instance per role (host/client).
class UdpSession {
  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  final StreamController<ReceivedPacket> _packets =
      StreamController<ReceivedPacket>.broadcast();

  bool _disposed = false;

  /// Stream of inbound datagrams. Broadcast so multiple listeners can attach
  /// (e.g. the role service and the latency probe).
  Stream<ReceivedPacket> get packets => _packets.stream;

  bool get isBound => _socket != null;

  /// Binds to [port] (use 0 for an ephemeral client port). IPv4 broadcast is
  /// enabled so outbound datagrams to the broadcast address work.
  Future<void> bind({int port = 0, bool broadcastEnabled = true}) async {
    if (isBound) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: false,
    );
    socket.broadcastEnabled = broadcastEnabled;
    _socket = socket;
    _subscription = socket.listen(
      _handleEvent,
      onError: (Object error, StackTrace stack) {
        debugPrint('UdpSession error: $error');
      },
      onDone: _socketClosed,
    );
  }

  void _handleEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _socket == null) return;
    while (true) {
      final datagram = _socket!.receive();
      if (datagram == null) break;
      if (_packets.hasListener) {
        _packets.add(ReceivedPacket(
          data: datagram.data,
          address: datagram.address,
          port: datagram.port,
        ));
      }
    }
  }

  void _socketClosed() {
    _socket = null;
  }

  /// Sends [data] to [address]:[port]. Unicast for peers, or use
  /// [NetConstants.broadcastAddress] to announce to the whole subnet.
  void send(Uint8List data, InternetAddress address, int port) {
    final socket = _socket;
    if (socket == null) return;
    socket.send(data, address, port);
  }

  /// The local bound port. Useful for a client to advertise where it listens.
  int? get localPort => _socket?.port;

  Future<void> close() async {
    if (_disposed) return;
    _disposed = true;

    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;

    if (subscription != null) {
      await subscription.cancel();
    }
    if (socket != null) {
      socket.close();
    }
    if (!_packets.isClosed) {
      await _packets.close();
    }
  }
}
