import 'dart:convert';
import 'dart:typed_data';

/// Shared constants for the BlueLink Party UDP protocol.
abstract final class NetConstants {
  /// Well-known port the host binds to; clients may bind ephemeral ports.
  static const int hostPort = 45701;

  /// Limited retry window when the well-known host port is busy.
  static const int hostPortFallback = 45702;

  static const int protocolVersion = 1;
  static const int maxPacketBytes = 4096;
  static const String broadcastAddress = '255.255.255.255';

  /// How long a client collects OFFER responses during a discovery scan.
  static const Duration discoverWindow = Duration(milliseconds: 2500);

  /// How often the host pings peers to measure latency / detect timeouts.
  static const Duration pingInterval = Duration(seconds: 2);

  /// How often the host pushes full lobby state to connected clients.
  static const Duration syncInterval = Duration(milliseconds: 700);

  /// A peer is dropped after this long without a PONG.
  static const Duration peerTimeout = Duration(seconds: 8);

  /// Error surfaced to a client that has been kicked out of a lobby.
  static const String kickedMessage = 'You were removed from the lobby';
}

enum PacketType {
  discover,
  offer,
  join,
  joinAck,
  lobbyUpdate,
  ping,
  pong,
  leave,
  kick,
  rename,
  matchEvent,
  gameInput,
  gameReady,
  gameCommand,
  gameState,
}

/// A versioned JSON packet: `{v, t, p}` where `p` is the type-specific payload.
class WirePacket {
  const WirePacket({required this.type, this.payload = const {}});

  final PacketType type;
  final Map<String, dynamic> payload;

  static const _typeKey = 't';
  static const _versionKey = 'v';
  static const _payloadKey = 'p';

  Uint8List encode() {
    final map = <String, dynamic>{
      _versionKey: NetConstants.protocolVersion,
      _typeKey: type.name,
      _payloadKey: payload,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(map)));
  }

  /// Returns null for malformed, oversized, or future-version packets.
  static WirePacket? decode(Uint8List bytes) {
    if (bytes.lengthInBytes > NetConstants.maxPacketBytes) return null;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded[_versionKey] != NetConstants.protocolVersion) return null;

      final typeName = decoded[_typeKey];
      PacketType? matched;
      for (final t in PacketType.values) {
        if (t.name == typeName) {
          matched = t;
          break;
        }
      }
      if (matched == null) return null;

      final payload = decoded[_payloadKey];
      return WirePacket(
        type: matched,
        payload: payload is Map<String, dynamic> ? payload : <String, dynamic>{},
      );
    } catch (_) {
      return null;
    }
  }
}

/// Convenience payload builders shared by host and client services.
abstract final class PacketPayload {
  static Map<String, dynamic> ping({required int seq}) => {
        'seq': seq,
        'ts': DateTime.now().microsecondsSinceEpoch,
      };

  static Map<String, dynamic> discover({
    required String playerId,
    required String playerName,
  }) =>
      {'playerId': playerId, 'playerName': playerName};

  static Map<String, dynamic> join({
    required String playerId,
    required String playerName,
    String? requestedTeam,
  }) =>
      {
        'playerId': playerId,
        'playerName': playerName,
        'requestedTeam': ?requestedTeam,
      };

  static Map<String, dynamic> leave({required String playerId}) =>
      {'playerId': playerId};

  static Map<String, dynamic> rename({
    required String playerId,
    required String playerName,
  }) =>
      {'playerId': playerId, 'playerName': playerName};

  static Map<String, dynamic> kick({required String playerId}) =>
      {'playerId': playerId};

  /// Host-driven game state transition broadcast to every connected client.
  static Map<String, dynamic> matchEvent({
    required String phase,
    required Map<String, dynamic> config,
  }) =>
      {'phase': phase, 'config': config};

  /// Client -> host: the local player's current move/fire intent.
  static Map<String, dynamic> gameInput({
    required String playerId,
    required double moveX,
    required double moveY,
    required bool firing,
    required int seq,
  }) =>
      {
        'playerId': playerId,
        'moveX': moveX,
        'moveY': moveY,
        'firing': firing,
        'seq': seq,
      };

  /// Either side -> host: a single player's ready-to-continue toggle.
  static Map<String, dynamic> gameReady({
    required String playerId,
    required bool ready,
  }) =>
      {'playerId': playerId, 'ready': ready};

  /// Any device -> host: a global control request (pause / restart / quit).
  static Map<String, dynamic> gameCommand({
    required String requestingPlayerId,
    required String command,
  }) =>
      {'from': requestingPlayerId, 'command': command};

  /// Host -> all clients: the authoritative live game snapshot.
  static Map<String, dynamic> gameState({
    required Map<String, dynamic> snapshot,
  }) =>
      {'snapshot': snapshot};
}
