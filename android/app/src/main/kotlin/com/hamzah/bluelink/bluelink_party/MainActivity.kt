package com.hamzah.bluelink.bluelink_party

import android.annotation.SuppressLint
import android.content.Context
import android.net.wifi.WifiManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "bluelink_party/platform"
    }

    private var multicastLock: WifiManager.MulticastLock? = null

    @SuppressLint("WifiManagerLeak")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val wifiManager =
            applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        acquireMulticastLock(wifiManager)
                        result.success(true)
                    }
                    "releaseMulticastLock" -> {
                        releaseMulticastLock()
                        result.success(true)
                    }
                    "getWifiInfo" -> result.success(readWifiInfo(wifiManager))
                    else -> result.notImplemented()
                }
            }
    }

    private fun acquireMulticastLock(wifiManager: WifiManager) {
        if (multicastLock == null) {
            multicastLock = wifiManager.createMulticastLock("bluelink_party").apply {
                setReferenceCounted(false)
                acquire()
            }
        }
    }

    private fun releaseMulticastLock() {
        multicastLock?.let { lock ->
            if (lock.isHeld) lock.release()
        }
        multicastLock = null
    }

    @Suppress("DEPRECATION")
    private fun readWifiInfo(wifiManager: WifiManager): Map<String, Any> {
        val info = wifiManager.connectionInfo
        val ssid = info?.ssid?.removeSurrounding("\"").orEmpty()
        return mapOf(
            "ssid" to ssid,
            // A non-empty SSID indicates an active Wi-Fi connection.
            "isWifi" to (ssid.isNotEmpty()),
            "rssi" to (info?.rssi ?: -127),
        )
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }
}
