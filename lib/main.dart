import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _requestPermissions();
  runApp(const ScreenShiftApp());
}

/// Location is required by Android to read the real Wi-Fi SSID (and, on
/// Android 13+, the nearby-wifi permission). Failure here only degrades the
/// network bar to "Unknown Wi-Fi" — the lobby itself never needs these.
Future<void> _requestPermissions() async {
  try {
    await Permission.location.request();
    await Permission.nearbyWifiDevices.request();
  } catch (_) {
    // Permissions are best-effort; networking still works without them.
  }
}
