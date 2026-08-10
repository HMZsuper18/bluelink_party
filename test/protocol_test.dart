import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/data/models/game_mode.dart';
import 'package:bluelink_party/data/models/lobby_room.dart';
import 'package:bluelink_party/data/models/player_slot.dart';
import 'package:bluelink_party/data/models/team.dart';
import 'package:bluelink_party/network/protocol.dart';

Uint8List _bytes(String source) => Uint8List.fromList(utf8.encode(source));

void main() {
  group('WirePacket codec', () {
    test('round-trips a packet with a payload', () {
      final packet = WirePacket(
        type: PacketType.join,
        payload: const {
          'playerId': 'abc123',
          'playerName': 'Neo',
          'requestedTeam': 'RED',
        },
      );

      final decoded = WirePacket.decode(packet.encode());

      expect(decoded, isNotNull);
      expect(decoded!.type, PacketType.join);
      expect(decoded.payload['playerId'], 'abc123');
      expect(decoded.payload['requestedTeam'], 'RED');
    });

    test('rejects garbage input', () {
      expect(WirePacket.decode(_bytes('not-json{')), isNull);
    });

    test('rejects packets above the size cap', () {
      final packet = WirePacket(
        type: PacketType.lobbyUpdate,
        payload: {'blob': 'x' * 5000},
      );
      expect(WirePacket.decode(packet.encode()), isNull);
    });

    test('rejects future protocol versions', () {
      final raw = jsonEncode({'v': 99, 't': 'ping', 'p': <String, dynamic>{}});
      expect(WirePacket.decode(_bytes(raw)), isNull);
    });
  });

  group('LobbyRoom serialization', () {
    test('round-trips a full lobby', () {
      final room = LobbyRoom(
        hostIp: '192.168.1.10',
        lobbyName: 'Neo\'s Lobby',
        roomCode: '4821',
        selectedMode: GameMode.battleSync,
        teams: {
          Team.red: [
            const PlayerSlot(
              team: Team.red,
              seat: 0,
              playerId: 'host01',
              playerName: 'Neo',
              isHost: true,
            ),
            const PlayerSlot(team: Team.red, seat: 1),
          ],
          Team.blue: [
            const PlayerSlot(team: Team.blue, seat: 0),
            const PlayerSlot(team: Team.blue, seat: 1),
          ],
        },
        revision: 7,
      );

      final decoded = LobbyRoom.fromJson(room.toJson());

      expect(decoded, room);
      expect(decoded.filledSlots, 1);
      expect(decoded.hostIp, '192.168.1.10');
      expect(decoded.roomCode, '4821');
      expect(decoded.selectedMode, GameMode.battleSync);
      expect(decoded.slotAt(Team.red, 0)?.playerName, 'Neo');
      expect(decoded.slotAt(Team.red, 1)?.isFilled, isFalse);
      expect(decoded.teamOf('host01'), Team.red);
    });
  });
}
