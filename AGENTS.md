# AGENTS.md

Guidance for AI agents working on ScreenShift.

## What this project is

A Flutter local-multiplayer party game. Devices on the same Wi-Fi network play one shared match: the host runs the simulation, clients send input, and every screen renders its own slice. There is no internet backend.

Modes: **Battle Sync** (1v1/2v2 arena), **Pixel Futbol** (2v2 football), **Screen Shift** (each device sees only its own slice of the arena).

## Commands

```sh
flutter pub get                          # install dependencies
flutter analyze                          # lint + static analysis (run before finishing any change)
flutter test                             # all tests, incl. loopback UDP e2e tests (bind real sockets; may be slow)
dart run tool/generate_sfx.dart           # regenerate assets/audio/*.wav (procedural)
```

Always run `flutter analyze` and the relevant `flutter test` suite after touching code.

## Architecture & conventions

- **Feature-first layout** (`lib/features/<feature>/`) with `domain` / `bloc` / `presentation` / `game` / `sync` subfolders. Add new features there, not in `lib/core`.
- **`data/models`** are wire-safe: everything serializable has `toJson` / `fromJson`. Don't break the wire protocol (`lib/network/protocol.dart`) without updating the protocol tests.
- **State management is `flutter_bloc`** (`equatable` events/states). Follow existing patterns in `lib/features/lobby/bloc/` and `lib/features/game/bloc/`.
- **Host-authoritative networking.** Host services (lib/network/host_service.dart) simulate the match and stream snapshots; `client_service.dart` receives and sends input. Tests stub `PlatformBridge.acquireMulticastLock()`.
- **Virtual resolution rendering.** Screens paint against `VirtualResolution`/`screen_scaler.dart` and never assume physical pixels. Keep painters resolution-independent.
- **Audio** is procedurally generated; play through `SfxService`. Never add third-party audio binaries.
- **Permissions** are requested best-effort in `main.dart`; networking must work without them.
- Dev entry points (never shipped; separate `main()` files): `lib/dev_matrix_main.dart` and `lib/dev_matrix_lab_main.dart` (matrix lab; don't touch unless working on the matrix lab), `lib/dev_futbol_lab_main.dart` (bot-vs-bot futbol wall), and `lib/dev_app_lab_main.dart` (whole-app mirror: the real lobby over loopback with real-client bots that join your room, play any mode, and are watchable via the floating DEVICES wall). Editing the real app automatically changes the dev labs since they reuse the same screens/controllers/painters.
- Bot transports live in the feature: `lib/features/matrix_futbol/game/futbol_sync_adapter.dart` mirrors `matrix_transport_sync.dart`. The bot swarm (`lib/dev/lab/app_bot_lab.dart`) takes an optional `requiredLobbyName` so loopback tests never intrude into other concurrent e2e lobbies.

## Testing

- Tests live in `test/`, mirror module names. Pure logic tests use `test()`, e2e tests use `flutter_test` with real UDP loopback pairs and a `_FakeBridge` stub.
- E2e tests open real sockets and expect discovery/join/movement over the wire — the loopback suite is only stable under `flutter test --concurrency=1`; the broadcast-socket tests conflict when parallelized.
- When adding networking or sync logic, add a loopback e2e test following `test/udp_e2e_test.dart`, `test/matrix_udp_e2e_test.dart`, or `test/app_bot_lab_test.dart` rather than mocking the socket. For swarms set `requiredLobbyName` so the bots only join the intended room.

## Gotchas

- `SharedPreferences.setMockInitialValues({})` is required in tests that touch profile persistence.
- Android SSID reading is platform-version dependent; code in `wifi_info_repository.dart` must degrade to "Unknown Wi-Fi" on failure.
- Don't rename files under `assets/audio/` without updating `tool/generate_sfx.dart` and the `pubspec.yaml` asset list.

## License

GPLv3 — see `LICENSE`. New files should keep the project's copyright conventions; do not add per-file license banners unless asked.