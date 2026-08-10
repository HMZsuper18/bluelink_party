import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';

import '../data/models/game_mode.dart';
import '../data/models/lobby_room.dart';
import '../data/models/lobby_rules.dart';
import '../data/models/match_event.dart';
import '../data/models/player_slot.dart';
import '../data/models/team.dart';
import '../data/repositories/wifi_info_repository.dart';
import 'latency_probe.dart';
import 'protocol.dart';
import 'udp_session.dart';

class _Peer {
  _Peer({
    required this.addr,
    required this.port,
    required this.name,
  });

  final InternetAddress addr;
  final int port;
  String name;
  int lastPong = DateTime.now().microsecondsSinceEpoch;
}

/// Snapshot of host-side state pushed to the UI layer.
class HostSnapshot {
  const HostSnapshot({required this.room, required this.rttMsByPlayerId});

  final LobbyRoom room;
  final Map<String, int> rttMsByPlayerId;
}

/// Host side of the UDP protocol: owns the well-known port, answers discovery,
/// accepts joins, arbitrates slot claims, measures peer latency, and keeps all
/// connected clients in sync with the authoritative lobby state.
class HostService {
  HostService({required this.bridge, required this.playerId, required this.playerName});

  final PlatformBridge bridge;
  final String playerId;
  String playerName;

  late final UdpSession _session = UdpSession();
  late final LatencyProbe _probe = LatencyProbe(session: _session);
  StreamSubscription<ReceivedPacket>? _packetSub;
  StreamSubscription<void>? _sampleSub;
  Timer? _syncTimer;

  final Map<String, _Peer> _peers = {};
  late LobbyRoom _room;
  String _localIp = '0.0.0.0';
  bool _multicastHeld = false;
  bool _disposed = false;

  final StreamController<HostSnapshot> _snapshots =
      StreamController<HostSnapshot>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  final StreamController<MatchEvent> _matchEvents =
      StreamController<MatchEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _gameInputPackets =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _gameReadyPackets =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _gameCommandPackets =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<HostSnapshot> get snapshots => _snapshots.stream;
  Stream<String> get errors => _errors.stream;
  Stream<MatchEvent> get matchEvents => _matchEvents.stream;

  /// In-game move/fire intents received from connected clients.
  Stream<Map<String, dynamic>> get gameInputPackets => _gameInputPackets.stream;

  /// In-game ready-to-continue toggles received from connected clients.
  Stream<Map<String, dynamic>> get gameReadyPackets => _gameReadyPackets.stream;

  /// In-game control requests (pause / restart) received from connected clients.
  Stream<Map<String, dynamic>> get gameCommandPackets =>
      _gameCommandPackets.stream;

  bool get isHosting => _session.isBound;

  Future<void> startHosting({String? lobbyName}) async {
    _localIp = await _resolveLocalIp();

    try {
      await _session.bind(port: NetConstants.hostPort);
    } on SocketException {
      await _session.bind(port: NetConstants.hostPortFallback);
    }

    final roomCode = _generateRoomCode();
    _room = LobbyRoom(
      hostIp: _localIp,
      lobbyName: lobbyName ?? roomCode,
      roomCode: roomCode,
      selectedMode: GameMode.battleSync,
      teams: {
        for (final team in Team.all)
          team: [
            for (var seat = 0; seat < Team.capacity; seat++)
              PlayerSlot(team: team, seat: seat),
          ],
      },
    );

    final hostAssignment = LobbyRules.assignSlot(
      room: _room,
      playerId: playerId,
      playerName: playerName,
      isHost: true,
      requestedTeam: Team.red,
    );
    if (hostAssignment != null) {
      _room = hostAssignment.room;
    }

    _packetSub = _session.packets.listen(_handlePacket);
    _sampleSub = _probe.onSample.listen((_) => _emit());

    _multicastHeld = await bridge.acquireMulticastLock();
    _probe.start();
    _syncTimer = Timer.periodic(NetConstants.syncInterval, (_) => _syncTick());

    _emit();
  }

  Future<void> _handlePacket(ReceivedPacket packet) async {
    final wire = WirePacket.decode(packet.data);
    if (wire == null) return;

    switch (wire.type) {
      case PacketType.discover:
        _handleDiscover(packet);
      case PacketType.join:
        _handleJoin(packet, wire.payload);
      case PacketType.leave:
        _handleLeave(wire.payload);
      case PacketType.rename:
        _handleRename(wire.payload);
      case PacketType.ping:
        _session.send(LatencyProbe.pongFor(wire), packet.address, packet.port);
      case PacketType.pong:
        final rtt = _probe.recordPong(
          pong: wire,
          from: packet.address,
          port: packet.port,
        );
        if (rtt != null) {
          final peer = _peerFor(packet.address, packet.port);
          if (peer != null) peer.lastPong = DateTime.now().microsecondsSinceEpoch;
        }
      case PacketType.offer:
      case PacketType.joinAck:
      case PacketType.lobbyUpdate:
      case PacketType.matchEvent:
        break;
      case PacketType.gameInput:
        if (_gameInputPackets.hasListener) {
          _gameInputPackets.add(wire.payload);
          debugPrint('[SYNC] host RX gameInput '
              'id=${wire.payload['playerId']} '
              'moveX=${wire.payload['moveX']} '
              'moveY=${wire.payload['moveY']} '
              'fire=${wire.payload['firing']}');
        }
      case PacketType.gameReady:
        if (_gameReadyPackets.hasListener) _gameReadyPackets.add(wire.payload);
      case PacketType.gameCommand:
        if (_gameCommandPackets.hasListener) {
          _gameCommandPackets.add(wire.payload);
        }
      case PacketType.gameState:
        break;
      case PacketType.kick:
        _handleKick(wire.payload);
    }
  }

  _Peer? _peerFor(InternetAddress addr, int port) {
    for (final peer in _peers.values) {
      if (peer.addr.address == addr.address && peer.port == port) return peer;
    }
    return null;
  }

  void _handleDiscover(ReceivedPacket packet) {
    final offer = WirePacket(
      type: PacketType.offer,
      payload: {
        'hostIp': _room.hostIp,
        'hostPort': _session.localPort ?? NetConstants.hostPort,
        'lobbyName': _room.lobbyName,
        'roomCode': _room.roomCode,
        'hostName': playerName,
        'mode': _room.selectedMode.key,
        'filledSlots': _room.filledSlots,
        'revision': _room.revision,
      },
    );
    _session.send(offer.encode(), packet.address, packet.port);
  }

  Future<void> _handleJoin(
    ReceivedPacket packet,
    Map<String, dynamic> payload,
  ) async {
    final joinerId = payload['playerId'] as String?;
    final joinerName = payload['playerName'] as String?;
    if (joinerId == null || joinerId == playerId || joinerName == null) return;

    final requestedTag = payload['requestedTeam'] as String?;
    final requested = requestedTag == null ? null : Team.fromTag(requestedTag);

    LobbyRoom? result;

    if (_peers.containsKey(joinerId)) {
      final rejoining = _room.copyWith();
      final released = LobbyRules.releaseSlot(
        room: rejoining,
        playerId: joinerId,
      );
      if (released != null) {
        result = _assignOrNull(
          room: released,
          joinerId: joinerId,
          joinerName: joinerName,
          requested: requested,
        );
      }
    } else {
      result = _assignOrNull(
        room: _room,
        joinerId: joinerId,
        joinerName: joinerName,
        requested: requested,
      );
    }

    if (result != null) {
      _room = result;
      _peers[joinerId] = _Peer(
        addr: packet.address,
        port: packet.port,
        name: joinerName,
      );
      _probe.trackPeer(packet.address, packet.port);

      final assigned = _seatOf(joinerId)!;
      _sendJoinAck(packet.address, packet.port, assigned.team, assigned.seat);
      _emit();
      _pushSync();
    } else {
      _sendJoinAckError(packet.address, packet.port, 'Lobby is full');
    }
  }

  LobbyRoom? _assignOrNull({
    required LobbyRoom room,
    required String joinerId,
    required String joinerName,
    Team? requested,
  }) {
    final res = LobbyRules.assignSlot(
      room: room,
      playerId: joinerId,
      playerName: joinerName,
      requestedTeam: requested,
    );
    return res?.room;
  }

  ({Team team, int seat})? _seatOf(String pid) {
    for (final team in Team.all) {
      final slots = _room.slotsOf(team);
      for (final slot in slots) {
        if (slot.playerId == pid) return (team: team, seat: slot.seat);
      }
    }
    return null;
  }

  void _sendJoinAck(InternetAddress addr, int port, Team team, int seat) {
    final ack = WirePacket(
      type: PacketType.joinAck,
      payload: {
        'assignedTeam': team.key,
        'assignedSeat': seat,
        'lobby': _room.toJson(),
      },
    );
    _session.send(ack.encode(), addr, port);
  }

  void _sendJoinAckError(InternetAddress addr, int port, String error) {
    final ack = WirePacket(
      type: PacketType.joinAck,
      payload: {'error': error},
    );
    _session.send(ack.encode(), addr, port);
  }

  void _handleLeave(Map<String, dynamic> payload) {
    final leaving = payload['playerId'] as String?;
    if (leaving == null || leaving == playerId) return;

    final peer = _peers.remove(leaving);
    if (peer != null) {
      _probe.untrackPeer(peer.addr, peer.port);
    }
    final updated = LobbyRules.releaseSlot(room: _room, playerId: leaving);
    if (updated != null) {
      _room = updated;
      _emit();
      _pushSync();
    }
  }

  void _handleRename(Map<String, dynamic> payload) {
    final id = payload['playerId'] as String?;
    final name = (payload['playerName'] as String?)?.trim();
    if (id == null || name == null || name.isEmpty) return;

    final peer = _peers[id];
    if (peer != null) peer.name = name;

    final renamed = _renameSlot(id, name);
    if (renamed != null) {
      _room = renamed;
      _emit();
      _pushSync();
    }
  }

  LobbyRoom? _renameSlot(String id, String name) {
    for (final team in Team.all) {
      final slots = _room.slotsOf(team);
      for (final slot in slots) {
        if (slot.playerId != id) continue;
        final teams = {
          for (final t in Team.all)
            t: [
              for (final s in _room.slotsOf(t))
                s.playerId == id ? s.copyWith(playerName: name) : s,
            ],
        };
        return _room.copyWith(teams: teams);
      }
    }
    return null;
  }

  void _handleKick(Map<String, dynamic> payload) {
    final target = payload['playerId'] as String?;
    if (target == null || target == playerId) return;
    _kickPlayer(target);
  }

  /// Host-initiated kick of [targetId]; returns an error string or null.
  String? kick(String targetId) {
    if (targetId == playerId) return 'You cannot kick yourself';
    if (!_peers.containsKey(targetId)) return 'No such member';
    _kickPlayer(targetId);
    return null;
  }

  void _kickPlayer(String target) {
    final peer = _peers[target];
    if (peer != null) {
      final kick = WirePacket(
        type: PacketType.kick,
        payload: PacketPayload.kick(playerId: target),
      );
      _session.send(kick.encode(), peer.addr, peer.port);
    }
    _peers.remove(target);
    if (peer != null) _probe.untrackPeer(peer.addr, peer.port);
    final updated = LobbyRules.releaseSlot(room: _room, playerId: target);
    if (updated != null) _room = updated;
    _emit();
    _pushSync();
  }

  void _syncTick() {
    _dropStalePeers();
    if (_peers.isNotEmpty) _pushSync();
  }

  void _dropStalePeers() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final stale = <String>[];
    _peers.forEach((id, peer) {
      if (now - peer.lastPong > NetConstants.peerTimeout.inMicroseconds) {
        stale.add(id);
      }
    });
    for (final id in stale) {
      final peer = _peers.remove(id);
      if (peer != null) _probe.untrackPeer(peer.addr, peer.port);
      final updated = LobbyRules.releaseSlot(room: _room, playerId: id);
      if (updated != null) _room = updated;
    }
    if (stale.isNotEmpty) {
      _emit();
      _pushSync();
    }
  }

  void _pushSync() {
    if (!_session.isBound) return;
    final payload = WirePacket(
      type: PacketType.lobbyUpdate,
      payload: {'lobby': _room.toJson()},
    );
    final bytes = payload.encode();
    for (final peer in _peers.values) {
      _session.send(bytes, peer.addr, peer.port);
    }
  }

  /// Host-only actions applied locally and pushed to every client.
  String? setMode(GameMode mode) {    if (mode == _room.selectedMode) return null;
    _room = _room.copyWith(selectedMode: mode);
    _emit();
    _pushSync();
    return null;
  }

  String? claimSlot(Team team) {
    final res = LobbyRules.assignSlot(
      room: _room,
      playerId: playerId,
      playerName: playerName,
      isHost: true,
      requestedTeam: team,
    );
    if (res == null) return 'Team is full';
    _room = res.room;
    _emit();
    _pushSync();
    return null;
  }

  String? releaseSlot() {
    final updated = LobbyRules.releaseSlot(room: _room, playerId: playerId);
    if (updated == null) return 'No seat to release';
    _room = updated;
    _emit();
    _pushSync();
    return null;
  }

  String? rename(String newName) {
    final cleaned = newName.trim();
    if (cleaned.isEmpty) return 'Name cannot be empty';
    playerName = cleaned;
    final renamed = _renameSlot(playerId, cleaned);
    if (renamed != null) {
      _room = renamed;
      _emit();
      _pushSync();
    }
    return null;
  }

  /// Immediately re-pings every peer and pushes the latest state. Used by the
  /// manual refresh control.
  void refresh() {
    for (final peer in _peers.values) {
      _probe.sendPingNow(peer.addr, peer.port);
    }
    _pushSync();
  }

  /// Host-triggered game transition, broadcast to every connected peer.
  void pushMatchEvent(MatchEvent event) {
    if (_matchEvents.hasListener) _matchEvents.add(event);
    final wire = WirePacket(
      type: PacketType.matchEvent,
      payload: PacketPayload.matchEvent(
        phase: event.phase.key,
        config: event.config.toJson(),
      ),
    );
    final bytes = wire.encode();
    for (final peer in _peers.values) {
      _session.send(bytes, peer.addr, peer.port);
    }
  }

  /// Host-authoritative live game snapshot, pushed to every connected client.
  void broadcastGameState(Map<String, dynamic> snapshot) {
    if (!_session.isBound) return;
    final wire = WirePacket(
      type: PacketType.gameState,
      payload: PacketPayload.gameState(snapshot: snapshot),
    );
    final bytes = wire.encode();
    final players = snapshot['players'] as List<dynamic>? ?? const [];
    debugPrint('[SYNC] host TX gameState '
        'phase=${snapshot['phase']} '
        'players=${players.map((p) => '${p['id']}@${(p['x'] as num).toStringAsFixed(1)},${(p['y'] as num).toStringAsFixed(1)}').join(' ')}');
    for (final peer in _peers.values) {
      _session.send(bytes, peer.addr, peer.port);
    }
  }

  void _emit() {
    final rtts = <String, int>{};
    _peers.forEach((id, peer) {
      final avg = _probe.averageFor(peer.addr, peer.port);
      if (avg != null) rtts[id] = avg;
    });
    if (_snapshots.hasListener) {
      _snapshots.add(HostSnapshot(room: _room, rttMsByPlayerId: rtts));
    }
  }

  static Future<String> _resolveLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.isLoopback) continue;
          if (addr.address.startsWith('127.')) continue;
          return addr.address;
        }
      }
    } catch (_) {}
    return '0.0.0.0';
  }

  static String _generateRoomCode() {
    final random = Random();
    return '${1000 + random.nextInt(9000)}';
  }

  Future<void> pause() async {
    _probe.stop();
    if (_multicastHeld) {
      await bridge.releaseMulticastLock();
      _multicastHeld = false;
    }
  }

  Future<void> resume() async {
    if (_multicastHeld) return;
    _multicastHeld = await bridge.acquireMulticastLock();
    _probe.start();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _syncTimer?.cancel();
    _syncTimer = null;
    await _packetSub?.cancel();
    await _sampleSub?.cancel();
    _probe.dispose();

    if (_multicastHeld) {
      await bridge.releaseMulticastLock();
      _multicastHeld = false;
    }
    _peers.clear();
    await _session.close();
    if (!_snapshots.isClosed) await _snapshots.close();
    if (!_errors.isClosed) await _errors.close();
    if (!_matchEvents.isClosed) await _matchEvents.close();
    if (!_gameInputPackets.isClosed) await _gameInputPackets.close();
    if (!_gameReadyPackets.isClosed) await _gameReadyPackets.close();
    if (!_gameCommandPackets.isClosed) await _gameCommandPackets.close();
  }
}
