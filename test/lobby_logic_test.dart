import 'package:flutter_test/flutter_test.dart';
import 'package:bluelink_party/data/models/game_mode.dart';
import 'package:bluelink_party/data/models/lobby_room.dart';
import 'package:bluelink_party/data/models/lobby_rules.dart';
import 'package:bluelink_party/data/models/player_slot.dart';
import 'package:bluelink_party/data/models/team.dart';

LobbyRoom _emptyRoom({GameMode mode = GameMode.battleSync}) {
  return LobbyRoom(
    hostIp: '192.168.1.10',
    lobbyName: 'Test Lobby',
    selectedMode: mode,
    teams: {
      for (final team in Team.all)
        team: [
          for (var seat = 0; seat < Team.capacity; seat++)
            PlayerSlot(team: team, seat: seat),
        ],
    },
  );
}

void main() {
  group('LobbyRules.assignSlot', () {
    test('assigns to the requested team when it has a free seat', () {
      final result = LobbyRules.assignSlot(
        room: _emptyRoom(),
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.red,
      );

      expect(result, isNotNull);
      expect(result!.team, Team.red);
      expect(result.room.slotAt(Team.red, result.seat)?.playerName, 'Neo');
    });

    test('fills seats within a team before overflowing', () {
      var room = _emptyRoom();
      for (final pid in ['p1', 'p2', 'p3']) {
        final res = LobbyRules.assignSlot(
          room: room,
          playerId: pid,
          playerName: 'Player $pid',
          requestedTeam: Team.red,
        );
        room = res!.room;
      }

      expect(room.filledSlots, 3);
      expect(room.slotsOf(Team.red).where((s) => s.isFilled).length, 2);
      expect(room.slotsOf(Team.blue).where((s) => s.isFilled).length, 1);
    });

    test('falls back to the other team when the request is full', () {
      var room = _emptyRoom();
      for (final pid in ['p1', 'p2']) {
        final res = LobbyRules.assignSlot(
          room: room,
          playerId: pid,
          playerName: 'Player $pid',
          requestedTeam: Team.blue,
        );
        room = res!.room;
      }

      final result = LobbyRules.assignSlot(
        room: room,
        playerId: 'p3',
        playerName: 'Trinity',
        requestedTeam: Team.blue,
      );

      expect(result, isNotNull);
      expect(result!.team, Team.red);
    });

    test('keeps a player to a single seat', () {
      final first = LobbyRules.assignSlot(
        room: _emptyRoom(),
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.red,
      );

      final second = LobbyRules.assignSlot(
        room: first!.room,
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.blue,
      );

      expect(second, isNotNull);
      expect(first.room.filledSlots, 1);
      expect(second!.room.filledSlots, 1);
      expect(
        second.room.teams.values.expand((s) => s).where((s) => s.isFilled).length,
        1,
      );
    });

    test('lets a seated player switch to a team with a free seat', () {
      var room = _emptyRoom();
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.red,
      )!.room;

      final result = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.blue,
      );

      expect(result, isNotNull);
      expect(result!.team, Team.blue);
      expect(result.room.teamOf('p1'), Team.blue);
      expect(result.room.filledSlots, 1);
    });

    test('keeps the current seat when the requested team is full', () {
      var room = _emptyRoom();
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.red,
      )!.room;
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p2',
        playerName: 'Trinity',
        requestedTeam: Team.red,
      )!.room;
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p3',
        playerName: 'Morpheus',
        requestedTeam: Team.blue,
      )!.room;
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p4',
        playerName: 'Cypher',
        requestedTeam: Team.blue,
      )!.room;

      final result = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.blue,
      );

      expect(result, isNull);
      expect(room.teamOf('p1'), Team.red);
    });

    test('returns null when the lobby is full', () {
      var room = _emptyRoom();
      for (final team in Team.all) {
        for (var seat = 0; seat < Team.capacity; seat++) {
          final res = LobbyRules.assignSlot(
            room: room,
            playerId: 'p$team$seat',
            playerName: 'Player $seat',
            requestedTeam: team,
          );
          room = res!.room;
        }
      }
      expect(room.filledSlots, 4);

      final full = LobbyRules.assignSlot(
        room: room,
        playerId: 'p5',
        playerName: 'Overflow',
      );
      expect(full, isNull);
    });
  });

  group('LobbyRules.releaseSlot', () {
    test('frees the seat owned by the player', () {
      final assigned = LobbyRules.assignSlot(
        room: _emptyRoom(),
        playerId: 'p1',
        playerName: 'Neo',
        requestedTeam: Team.red,
      );

      final updated = LobbyRules.releaseSlot(room: assigned!.room, playerId: 'p1');

      expect(updated, isNotNull);
      expect(updated!.filledSlots, 0);
      expect(updated.slotAt(Team.red, assigned.seat)?.isFilled, isFalse);
    });

    test('returns null when the player owns no seat', () {
      final updated = LobbyRules.releaseSlot(
        room: _emptyRoom(),
        playerId: 'ghost',
      );
      expect(updated, isNull);
    });
  });

  group('LobbyRules.canStart', () {
    test('Battle Sync starts with 2 players', () {
      var room = _emptyRoom();
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'A',
        requestedTeam: Team.red,
      )!.room;
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p2',
        playerName: 'B',
        requestedTeam: Team.blue,
      )!.room;

      expect(LobbyRules.canStart(room: room), isTrue);
    });

    test('Pixel Futbol requires 2 players', () {
      var room = _emptyRoom(mode: GameMode.pixelFutbol);
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'A',
        requestedTeam: Team.red,
      )!.room;
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p2',
        playerName: 'B',
        requestedTeam: Team.blue,
      )!.room;
      expect(LobbyRules.canStart(room: room), isTrue);
    });

    test('Pixel Futbol refuses to start with only 1 player', () {
      var room = _emptyRoom(mode: GameMode.pixelFutbol);
      room = LobbyRules.assignSlot(
        room: room,
        playerId: 'p1',
        playerName: 'A',
        requestedTeam: Team.red,
      )!.room;

      expect(LobbyRules.canStart(room: room), isFalse);
    });
  });
}
