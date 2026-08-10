import 'package:flutter/material.dart';

import '../domain/matrix_grid.dart';
import '../game/matrix_arena_controller.dart';
import '../presentation/matrix_arena_screen.dart';
import 'matrix_memory_bus.dart';

class MatrixDemoSetup {
  MatrixDemoSetup({
    required this.playerCount,
    required this.layout,
    required this.controllers,
    required this.bus,
    required this.hostController,
  });

  final int playerCount;
  final MatrixLayoutManager layout;
  final List<MatrixArenaController> controllers;
  final MatrixMemoryBus bus;
  final MatrixArenaController hostController;
}

MatrixDemoSetup buildMatrixDemo({required int playerCount}) {
  const layout = MatrixLayoutManager();
  final matrix = layout.matrixForPlayerCount(playerCount);

  final clients = <MatrixArenaController>[];
  for (var i = 1; i < playerCount; i++) {
    clients.add(MatrixArenaController(
      matrix: matrix,
      deviceCount: playerCount,
      isHost: false,
      deviceIndex: i,
    ));
  }

  final bus = MatrixMemoryBus(hostController: null, clients: clients);
  final host = MatrixArenaController(
    matrix: matrix,
    deviceCount: playerCount,
    isHost: true,
    deviceIndex: 0,
    adapter: bus,
  );
  bus.attachHost(host);

  return MatrixDemoSetup(
    playerCount: playerCount,
    layout: layout,
    controllers: [host, ...clients],
    bus: bus,
    hostController: host,
  );
}

class MatrixDemoBoard extends StatefulWidget {
  const MatrixDemoBoard({super.key, required this.playerCount});

  final int playerCount;

  @override
  State<MatrixDemoBoard> createState() => _MatrixDemoBoardState();
}

class _MatrixDemoBoardState extends State<MatrixDemoBoard> {
  late MatrixDemoSetup _setup;

  @override
  void initState() {
    super.initState();
    _setup = buildMatrixDemo(playerCount: widget.playerCount);
  }

  @override
  void dispose() {
    _setup.bus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grid = _setup.layout.gridForPlayerCount(widget.playerCount);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              color: const Color(0xFF141621),
              child: Text(
                'SCREENSHIFT MATRIX SANDBOX — $widget.playerCount DEVICES '
                '(${grid.columns}x${grid.rows})',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  for (final controller in _setup.controllers)
                    Expanded(
                      flex: 1,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.white24,
                            width: 1,
                          ),
                        ),
                        child: MatrixArenaScreen(
                          controller: controller,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}