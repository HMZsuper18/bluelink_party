import 'package:flutter/material.dart';

import 'features/matrix_arena/demo/matrix_demo_board.dart';

void main() {
  runApp(const MatrixDemoApp());
}

class MatrixDemoApp extends StatelessWidget {
  const MatrixDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'BlueLink Party Matrix Sandbox',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        useMaterial3: true,
      ),
      home: const MatrixDemoHome(),
    );
  }
}

class MatrixDemoHome extends StatefulWidget {
  const MatrixDemoHome({super.key});

  @override
  State<MatrixDemoHome> createState() => _MatrixDemoHomeState();
}

class _MatrixDemoHomeState extends State<MatrixDemoHome> {
  int _playerCount = 2;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    if (_running) {
      return MatrixDemoBoard(playerCount: _playerCount);
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'SCREENSHIFT',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'MULTI-DEVICE ARENA MATRIX',
              style: TextStyle(
                fontSize: 16,
                letterSpacing: 3,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 40),
            const Text('DEVICES', style: TextStyle(color: Colors.white54)),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final count in const [2, 3, 4])
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: ChoiceChip(
                      label: Text('$count'),
                      selected: _playerCount == count,
                      onSelected: (_) => setState(() => _playerCount = count),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 40),
            FilledButton(
              onPressed: () => setState(() => _running = true),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                child: Text(
                  'START MATRIX',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}