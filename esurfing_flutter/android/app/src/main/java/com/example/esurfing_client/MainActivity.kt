package com.example.esurfing_client

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.text.TextUtils.SimpleStringSplitter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.esurfing_client/keepalive"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAccessibilityEnabled" -> result.success(isAccessibilityServiceEnabled())
                "openAccessibilitySettings" -> {
                    startActivity(KeepAliveService.buildOpenSettingsIntent())
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * 检测本 APP 的无障碍服务是否已开启
     */
    private fun isAccessibilityServiceEnabled(): Boolean {
        val expectedComponentName = ComponentName(this, KeepAliveService::class.java)
        val enabledServicesSetting = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        val splitter = SimpleStringSplitter(':')
        splitter.setString(enabledServicesSetting)
        while (splitter.hasNext()) {
            val accessibilityService = splitter.next()
            if (accessibilityService.equals(expectedComponentName.flattenToString(), ignoreCase = true)) {
                return true
            }
        }
        return false
    }
}
