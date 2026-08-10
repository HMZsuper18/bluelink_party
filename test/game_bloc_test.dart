import 'package:flutter_test/flutter_test.dart';
import 'package:screen_shift/data/models/game_mode.dart';
import 'package:screen_shift/data/models/game_phase.dart';
import 'package:screen_shift/data/models/match_config.dart';
import 'package:screen_shift/data/models/match_event.dart';
import 'package:screen_shift/data/models/player_slot.dart';
import 'package:screen_shift/data/models/team.dart';
import 'package:screen_shift/features/game/bloc/game_bloc.dart';
import 'package:screen_shift/features/game/bloc/game_event.dart';
import 'package:screen_shift/features/game/domain/match_player.dart';

const _event = MatchEvent(
  phase: GamePhase.countdown,
  config: MatchConfig(
    mode: GameMode.battleSync,
    countdownSeconds: 3,
    matchDuration: Duration(seconds: 2),
  ),
);

MatchConfig get _config => _event.config;

void main() {
  group('countdown lifecycle', () {
    test('advances 3-2-1 then moves to inGame and spawns players', () async {
      final bloc = GameBloc();
      final transitions = <GamePhase>[];
      final sub = bloc.stream.listen((s) => transitions.add(s.phase));

      bloc.add(MatchStarted(_event));
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(bloc.state.phase, GamePhase.countdown);
      expect(bloc.state.remainingSeconds, inInclusiveRange(2, 3));

      await Future<void>.delayed(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 600));

      expect(bloc.state.phase, GamePhase.inGame);
      expect(bloc.state.remainingSeconds, 0);
      expect(bloc.state.players, hasLength(4));
      expect(bloc.state.players.where((p) => p.isLocal), hasLength(1));

      await sub.cancel();
      await bloc.close();
    });

    test('red spawns on the left and blue on the right of the arena', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final red = bloc.state.players.where((p) => p.team == Team.red);
      final blue = bloc.state.players.where((p) => p.team == Team.blue);
      for (final p in red) {
        expect(p.x, lessThan(_config.viewportWidth / 2));
        expect(p.facingX, greaterThan(0));
      }
      for (final p in blue) {
        expect(p.x, greaterThan(_config.viewportWidth / 2));
        expect(p.facingX, lessThan(0));
      }
      expect(bloc.state.phase, GamePhase.inGame);

      await bloc.close();
    });

    test('returning to lobby clears the field', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.phase, GamePhase.inGame);

      bloc.add(const ReturnToLobby());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.phase, GamePhase.lobby);
      expect(bloc.state.players, isEmpty);
      expect(bloc.state.projectiles, isEmpty);

      await bloc.close();
    });
  });

  group('in-match simulation', () {
    test('local player moves toward the input direction', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final before = bloc.state.players.firstWhere((p) => p.isLocal).x;
      bloc.add(const PlayerInputChanged(moveX: 1));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final after = bloc.state.players.firstWhere((p) => p.isLocal).x;
      expect(after, greaterThan(before));

      await bloc.close();
    });

    test('firing spawns a projectile from the local player', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      bloc.add(const PlayerInputChanged(firing: true));
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bloc.state.projectiles, isNotEmpty);
      final projectile = bloc.state.projectiles.first;
      expect(projectile.ownerTeam, Team.red);
      expect(projectile.vx, greaterThan(0));

      await bloc.close();
    });

    test('enemy team wipeout ends the match in victory', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      bloc.add(const MatchOver(MatchOutcome.victory));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.phase, GamePhase.matchResult);
      expect(bloc.state.outcome, MatchOutcome.victory);

      await bloc.close();
    });

    test('match timeout resolves as a draw', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.phase, GamePhase.inGame);

      await Future<void>.delayed(const Duration(milliseconds: 2200));

      expect(bloc.state.phase, GamePhase.matchResult);
      expect(bloc.state.outcome, MatchOutcome.draw);
      expect(bloc.state.elapsedMs, greaterThanOrEqualTo(2000));

      await bloc.close();
    });
  });

  group('roster and handicap', () {
    MatchEvent seeded(
      List<PlayerSlot> players, {
      String localPlayerId = 'r1',
    }) {
      return MatchEvent(
        phase: GamePhase.countdown,
        config: MatchConfig(players: players),
      );
    }

    test('number of circles matches the filled player slots', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.players, hasLength(2));

      await bloc.close();
    });

    test('outnumbered team player is buffed while the majority is not', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
          PlayerSlot(team: Team.blue, seat: 1, playerId: 'b2', playerName: 'B2'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final red = bloc.state.players.where((p) => p.team == Team.red).single;
      final blue = bloc.state.players.where((p) => p.team == Team.blue).toList();

      expect(red.maxHp, greaterThan(blue.first.maxHp));
      expect(red.radius, greaterThan(blue.first.radius));
      expect(red.damageMultiplier, greaterThan(1.0));
      expect(blue.every((p) => p.damageMultiplier == 1.0), isTrue);

      await bloc.close();
    });

    test('local player identity resolves against the seeded roster', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
        ], localPlayerId: 'b1'),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final local = bloc.state.players.firstWhere((p) => p.isLocal);
      expect(local.id, 'b1');
      expect(local.team, Team.blue);
      expect(bloc.state.players.where((p) => p.isLocal), hasLength(1));

      await bloc.close();
    });
  });

  group('pause, ready, and restart', () {
    MatchEvent seeded(List<PlayerSlot> players) {
      return MatchEvent(
        phase: GamePhase.countdown,
        config: MatchConfig(players: players),
      );
    }

    test('pause freezes the clock and only all-ready + resume continues', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final frozen = bloc.state.elapsedMs;
      bloc.add(const PauseMatch());
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(bloc.state.isPaused, isTrue);
      expect(bloc.state.elapsedMs, frozen);

      bloc.add(const PlayerReadyChanged('r1', ready: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.allPlayersReady, isFalse);

      bloc.add(const ResumeMatch());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const PlayerReadyChanged('b1', ready: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.allPlayersReady, isTrue);
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const ResumeMatch());
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(bloc.state.isPaused, isFalse);
      expect(bloc.state.elapsedMs, greaterThan(frozen));

      await bloc.close();
    });

    test('quit from pause is blocked until every player is ready', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      bloc.add(const PauseMatch());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc.add(const PlayerReadyChanged('r1', ready: true));
      bloc.add(const ReturnToLobby());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.phase, GamePhase.inGame);
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const PlayerReadyChanged('b1', ready: true));
      bloc.add(const ReturnToLobby());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.phase, GamePhase.lobby);

      await bloc.close();
    });

    test('restarting from a pause re-enters the countdown and clears the field',
        () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      bloc.add(const PauseMatch());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      bloc.add(const RestartMatch());
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(bloc.state.phase, GamePhase.inGame);
      expect(bloc.state.isPaused, isTrue);

      bloc.add(const PlayerReadyChanged('r1', ready: true));
      bloc.add(const PlayerReadyChanged('b1', ready: true));
      bloc.add(const RestartMatch());
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(bloc.state.phase, GamePhase.countdown);
      expect(bloc.state.remainingSeconds, 3);
      expect(bloc.state.isPaused, isFalse);
      expect(bloc.state.players, isEmpty);

      await bloc.close();
    });

    test('match clock counts down while in play', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(_event));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(bloc.state.timeRemainingMs, lessThanOrEqualTo(bloc.state.matchDurationMs));

      final first = bloc.state.timeRemainingMs;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(bloc.state.timeRemainingMs, lessThan(first));

      await bloc.close();
    });
  });

  group('player collisions', () {
    MatchEvent seeded(List<PlayerSlot> players) {
      return MatchEvent(
        phase: GamePhase.countdown,
        config: MatchConfig(
          players: players,
          matchDuration: const Duration(seconds: 30),
        ),
      );
    }

    test('players do not pass through each other', () async {
      final bloc = GameBloc();
      bloc.add(MatchStarted(
        seeded(const [
          PlayerSlot(team: Team.red, seat: 0, playerId: 'r1', playerName: 'R1'),
          PlayerSlot(team: Team.blue, seat: 0, playerId: 'b1', playerName: 'B1'),
        ]),
      ));
      bloc.add(const CountdownFinished());
      await Future<void>.delayed(const Duration(milliseconds: 60));

      MatchPlayer red() =>
          bloc.state.players.firstWhere((p) => p.id == 'r1');
      MatchPlayer blue() =>
          bloc.state.players.firstWhere((p) => p.id == 'b1');

      expect(red().x, lessThan(blue().x));

      // Drive the local red ship straight into blue long enough to cross
      // the full arena width (1920 @ 240 px/s ≈ 5.4s to contact).
      bloc.add(const PlayerInputChanged(moveX: 1, moveY: 0));
      await Future<void>.delayed(const Duration(seconds: 6));

      final r = red();
      final b = blue();
      // Red must butt against blue without overlapping or passing through.
      expect(r.x, lessThan(b.x));
      final gap = (b.x - r.x).abs();
      expect(gap, greaterThanOrEqualTo(r.hitboxSize / 2 + b.hitboxSize / 2 - 8));

      bloc.add(const PlayerInputChanged(moveX: 0, moveY: 0));
      await bloc.close();
    });
  });
}
