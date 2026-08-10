import 'dart:async';

import 'package:flutter/services.dart';

/// Snapshot of the current Wi-Fi state, pulled from the native Android layer
/// (WifiManager.connectionInfo) so no third-party connectivity plugin is needed.
class WifiStatus {
  const WifiStatus({
    required this.ssid,
    required this.isWifi,
    required this.rssi,
  });

  const WifiStatus.unknown()
      : ssid = '',
        isWifi = false,
        rssi = -127;

  final String ssid;
  final bool isWifi;
  final int rssi;

  String get displayName {
    if (!isWifi) return 'No Wi-Fi';
    if (ssid.isEmpty) return 'Unknown Wi-Fi';
    return ssid;
  }

  WifiStatus copyWith({String? ssid, bool? isWifi, int? rssi}) {
    return WifiStatus(
      ssid: ssid ?? this.ssid,
      isWifi: isWifi ?? this.isWifi,
      rssi: rssi ?? this.rssi,
    );
  }
}

/// Thin wrapper over the `bluelink_party/platform` MethodChannel. Owns the
/// Wi-Fi info polling and the Android multicast lock that lets the host
/// receive broadcast discovery packets.
class PlatformBridge {
  PlatformBridge({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('bluelink_party/platform');

  final MethodChannel _channel;

  Timer? _wifiPollTimer;
  WifiStatus _lastStatus = const WifiStatus.unknown();
  final StreamController<WifiStatus> _statusController =
      StreamController<WifiStatus>.broadcast();

  WifiStatus get current => _lastStatus;

  Stream<WifiStatus> get statusStream => _statusController.stream;

  /// Starts polling Wi-Fi status every [interval].
  void startPolling({Duration interval = const Duration(seconds: 3)}) {
    if (_wifiPollTimer != null) return;
    refresh();
    _wifiPollTimer = Timer.periodic(interval, (_) => refresh());
  }

  Future<void> refresh() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>('getWifiInfo');
      if (raw == null) {
        _emit(const WifiStatus.unknown());
        return;
      }
      final status = WifiStatus(
        ssid: (raw['ssid'] as String?) ?? '',
        isWifi: (raw['isWifi'] as bool?) ?? false,
        rssi: (raw['rssi'] as int?) ?? -127,
      );
      if (status != _lastStatus) {
        _lastStatus = status;
        _emit(status);
      }
    } catch (_) {
      _emit(_lastStatus);
    }
  }

  void _emit(WifiStatus status) {
    _lastStatus = status;
    if (_statusController.hasListener) {
      _statusController.add(status);
    }
  }

  /// Acquires the Android WifiManager multicast lock. Required for the host to
  /// receive UDP broadcasts on the local subnet.
  Future<bool> acquireMulticastLock() async {
    try {
      return await _channel.invokeMethod<bool>('acquireMulticastLock') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> releaseMulticastLock() async {
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
    } catch (_) {}
  }

  void dispose() {
    _wifiPollTimer?.cancel();
    _wifiPollTimer = null;
    if (!_statusController.isClosed) {
      _statusController.close();
    }
  }
}
