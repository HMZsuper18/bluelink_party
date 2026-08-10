import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../data/models/game_mode.dart';
import '../data/models/lobby_room.dart';
import '../data/models/match_event.dart';
import '../data/models/team.dart';
import 'latency_probe.dart';
import 'protocol.dart';
import 'udp_session.dart';

/// Snapshot of client-side state pushed to the UI layer.
class ClientSnapshot {
  const ClientSnapshot({
    required this.room,
    required this.rttMsByPlayerId,
    required this.myTeam,
  });

  final LobbyRoom room;
  final Map<String, int> rttMsByPlayerId;
  final Team? myTeam;
}

/// Client side of the UDP protocol: broadcasts discovery, joins a host's
/// lobby, claims slots, and mirrors the authoritative host state.
class ClientService {
  ClientService({required this.playerId, required this.playerName});

  final String playerId;
  String playerName;

  final UdpSession _session = UdpSession();
  late final LatencyProbe _probe = LatencyProbe(session: _session);
  StreamSubscription<ReceivedPacket>? _packetSub;
  StreamSubscription<void>? _sampleSub;

  InternetAddress? _hostAddr;
  int _hostPort = NetConstants.hostPort;
  LobbyRoom? _room;
  Team? _myTeam;
  Completer<Map<String, dynamic>>? _pendingJoin;
  bool _bound = false;
  bool _disposed = false;

  final StreamController<ClientSnapshot> _snapshots =
      StreamController<ClientSnapshot>.broadcast();
  final StreamController<String> _errors =
      StreamController<String>.broadcast();
  final StreamController<MatchEvent> _matchEvents =
      StreamController<MatchEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _gameStates =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<ClientSnapshot> get snapshots => _snapshots.stream;
  Stream<String> get errors => _errors.stream;
  Stream<MatchEvent> get matchEvents => _matchEvents.stream;

  /// Authoritative in-game snapshots received from the host.
  Stream<Map<String, dynamic>> get gameStates => _gameStates.stream;

  bool get isConnected => _room != null && _hostAddr != null;

  Future<void> _ensureBound() async {
    if (_bound) return;
    await _session.bind(port: 0);
    _bound = true;
    _packetSub = _session.packets.listen(_handlePacket);
    _sampleSub = _probe.onSample.listen((_) => _emit());
  }

  Future<void> _handlePacket(ReceivedPacket packet) async {
    final wire = WirePacket.decode(packet.data);
    if (wire == null) return;

    switch (wire.type) {
      case PacketType.joinAck:
        _pendingJoin?.complete(wire.payload);
        _pendingJoin = null;
      case PacketType.lobbyUpdate:
        final raw = wire.payload['lobby'];
        if (raw is Map<String, dynamic>) {
          _room = LobbyRoom.fromJson(raw);
          if (_myTeam != null && _room!.teamOf(playerId) == null) {
            _myTeam = null;
          }
          _emit();
        }
      case PacketType.ping:
        _session.send(LatencyProbe.pongFor(wire), packet.address, packet.port);
      case PacketType.pong:
        _probe.recordPong(
          pong: wire,
          from: packet.address,
          port: packet.port,
        );
      case PacketType.kick:
        _errors.add(NetConstants.kickedMessage);
      case PacketType.matchEvent:
        final event = MatchEvent.fromJson(wire.payload);
        if (_matchEvents.hasListener) _matchEvents.add(event);
      case PacketType.gameState:
        final raw = wire.payload['snapshot'];
        if (raw is Map<String, dynamic> && _gameStates.hasListener) {
          _gameStates.add(raw);
          final players = raw['players'] as List<dynamic>? ?? const [];
          debugPrint('[SYNC] client RX gameState '
              'phase=${raw['phase']} '
              'players=${players.map((p) => '${p['id']}@${(p['x'] as num).toStringAsFixed(1)},${(p['y'] as num).toStringAsFixed(1)}').join(' ')}');
        }
      case PacketType.offer:
      case PacketType.discover:
      case PacketType.join:
      case PacketType.leave:
      case PacketType.rename:
      case PacketType.gameInput:
      case PacketType.gameReady:
      case PacketType.gameCommand:
        break;
    }
  }

  /// Scans the subnet for hosts and returns their current lobbies.
  Future<List<DiscoveredLobby>> discover() async {
    await _ensureBound();

    final found = <String, DiscoveredLobby>{};
    final completer = Completer<List<DiscoveredLobby>>();

    final sub = _session.packets.listen((packet) {
      final wire = WirePacket.decode(packet.data);
      if (wire == null || wire.type != PacketType.offer) return;
      final lobby = DiscoveredLobby(
        hostIp: (wire.payload['hostIp'] as String?) ?? packet.address.address,
        hostPort: (wire.payload['hostPort'] as int?) ?? NetConstants.hostPort,
        lobbyName: (wire.payload['lobbyName'] as String?) ?? 'BlueLink Party Lobby',
        roomCode: (wire.payload['roomCode'] as String?) ?? '----',
        mode: GameMode.fromKey(wire.payload['mode'] as String? ?? ''),
        filledSlots: (wire.payload['filledSlots'] as int?) ?? 0,
        hostName: (wire.payload['hostName'] as String?) ?? 'Host',
      );
      found[lobby.hostIp] = lobby;
    });

    final discover = WirePacket(
      type: PacketType.discover,
      payload: PacketPayload.discover(playerId: playerId, playerName: playerName),
    );
    _session.send(
      discover.encode(),
      InternetAddress(NetConstants.broadcastAddress),
      NetConstants.hostPort,
    );

    Timer(NetConstants.discoverWindow, () {
      if (!completer.isCompleted) completer.complete(found.values.toList());
    });

    final result = await completer.future;
    await sub.cancel();
    return result;
  }

  /// Joins [lobby]. Returns null on success or a human-readable error string.
  Future<String?> join(DiscoveredLobby lobby) async {
    await _ensureBound();
    _hostAddr = InternetAddress.tryParse(lobby.hostIp);
    if (_hostAddr == null) return 'Invalid host address';
    _hostPort = lobby.hostPort;

    return _sendJoinAndWait(requestedTeam: null);
  }

  /// Requests a specific team. The host picks the free seat within it.
  Future<String?> claimSlot(Team team) async {
    if (!isConnected) return 'Not connected to a lobby';
    return _sendJoinAndWait(requestedTeam: team);
  }

  Future<String?> _sendJoinAndWait({Team? requestedTeam}) async {
    final join = WirePacket(
      type: PacketType.join,
      payload: PacketPayload.join(
        playerId: playerId,
        playerName: playerName,
        requestedTeam: requestedTeam?.key,
      ),
    );
    _session.send(join.encode(), _hostAddr!, _hostPort);

    final completer = Completer<Map<String, dynamic>>();
    _pendingJoin = completer;

    try {
      final ack = await completer.future.timeout(
        const Duration(seconds: 3),
        onTimeout: () {
          _pendingJoin = null;
          return const {'error': 'No response from host'};
        },
      );
      final error = ack['error'] as String?;
      if (error != null) return error;

      final raw = ack['lobby'];
      if (raw is! Map<String, dynamic>) return 'Malformed host response';

      _room = LobbyRoom.fromJson(raw);
      _myTeam = Team.fromTag(ack['assignedTeam'] as String?);

      if (_hostAddr != null) {
        _probe.trackPeer(_hostAddr!, _hostPort);
        _probe.start();
      }
      _emit();
      return null;
    } catch (_) {
      _pendingJoin = null;
      return 'Join timed out';
    }
  }

  /// Drops the client's seat without leaving the lobby.
  String? releaseSlot() {
    if (_room == null || _hostAddr == null) return 'Not connected';
    final leave = WirePacket(
      type: PacketType.leave,
      payload: PacketPayload.leave(playerId: playerId),
    );
    _session.send(leave.encode(), _hostAddr!, _hostPort);
    _room = null;
    _myTeam = null;
    _emit();
    return null;
  }

  /// Leaves the lobby entirely.
  void leave() {
    if (_hostAddr != null) {
      final leave = WirePacket(
        type: PacketType.leave,
        payload: PacketPayload.leave(playerId: playerId),
      );
      _session.send(leave.encode(), _hostAddr!, _hostPort);
    }
    _room = null;
    _myTeam = null;
  }

  /// Renames this player and asks the host to apply it to the lobby seats.
  void rename(String newName) {
    final cleaned = newName.trim();
    if (cleaned.isEmpty || _hostAddr == null) return;
    playerName = cleaned;
    _session.send(
      WirePacket(
        type: PacketType.rename,
        payload: PacketPayload.rename(
          playerId: playerId,
          playerName: cleaned,
        ),
      ).encode(),
      _hostAddr!,
      _hostPort,
    );
    final updated = _renameSlot(cleaned);
    if (updated != null) {
      _room = updated;
      _emit();
    }
  }

  LobbyRoom? _renameSlot(String name) {
    final room = _room;
    if (room == null) return null;
    for (final team in Team.all) {
      for (final slot in room.slotsOf(team)) {
        if (slot.playerId != playerId) continue;
        return room.copyWith(teams: {
          for (final t in Team.all)
            t: [
              for (final s in room.slotsOf(t))
                s.playerId == playerId ? s.copyWith(playerName: name) : s,
            ],
        });
      }
    }
    return null;
  }

  /// Asks the host to remove [targetId] from the lobby.
  void kick(String targetId) {
    if (_hostAddr == null) return;
    _session.send(
      WirePacket(
        type: PacketType.kick,
        payload: PacketPayload.kick(playerId: targetId),
      ).encode(),
      _hostAddr!,
      _hostPort,
    );
  }

  void _emit() {
    if (_room == null || !_snapshots.hasListener) return;
    final rtts = <String, int>{};
    if (_hostAddr != null) {
      final avg = _probe.averageFor(_hostAddr!, _hostPort);
      if (avg != null && _myTeam != null) rtts['host'] = avg;
    }
    _snapshots.add(ClientSnapshot(
      room: _room!,
      rttMsByPlayerId: rtts,
      myTeam: _myTeam,
    ));
  }

  /// Immediately pings the host and re-reads its latest state.
  void refresh() {
    if (_hostAddr != null) {
      _probe.sendPingNow(_hostAddr!, _hostPort);
    }
  }

  /// Sends the local player's current move/fire intent to the host.
  void sendGameInput({
    required String playerId,
    required double moveX,
    required double moveY,
    required bool firing,
    required int seq,
  }) {
    _sendPayload(
      PacketType.gameInput,
      PacketPayload.gameInput(
        playerId: playerId,
        moveX: moveX,
        moveY: moveY,
        firing: firing,
        seq: seq,
      ),
    );
  }

  /// Informs the host this device's player readied to continue (or unreadied).
  void sendGameReady({required String playerId, required bool ready}) {
    _sendPayload(
      PacketType.gameReady,
      PacketPayload.gameReady(playerId: playerId, ready: ready),
    );
  }

  /// Requests a global control action from the host.
  void sendGameCommand({required String from, required String command}) {
    _sendPayload(
      PacketType.gameCommand,
      PacketPayload.gameCommand(requestingPlayerId: from, command: command),
    );
  }

  void _sendPayload(PacketType type, Map<String, dynamic> payload) {
    if (_hostAddr == null) return;
    _session.send(
      WirePacket(type: type, payload: payload).encode(),
      _hostAddr!,
      _hostPort,
    );
  }

  void pause() {
    _probe.stop();
  }

  void resume() {
    _probe.start();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    leave();
    await _packetSub?.cancel();
    await _sampleSub?.cancel();
    _probe.dispose();
    await _session.close();
    if (!_snapshots.isClosed) await _snapshots.close();
    if (!_errors.isClosed) await _errors.close();
    if (!_matchEvents.isClosed) await _matchEvents.close();
    if (!_gameStates.isClosed) await _gameStates.close();
  }
}
