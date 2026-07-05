package com.example.esurfing_client

import android.accessibilityservice.AccessibilityService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import android.view.accessibility.AccessibilityEvent
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MainActivity — 自定义入口,注册 MethodChannel 处理 Dart 侧的保活相关请求。
 *
 * 注意:这里只添加了处理 keepalive channel 的代码,其他 FlutterActivity 默认行为全部保留。
 */
class MainActivity : FlutterActivity() {

    private val channelName = "com.example.esurfing_client/keepalive"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAccessibilityEnabled" -> {
                        result.success(isAccessibilityEnabled())
                    }
                    "openAccessibilitySettings" -> {
                        openAccessibilitySettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 检测本 APP 的无障碍服务是否已在系统设置中开启。
     *
     * Android 没有"直接查询某 package 无障碍 service 是否启用"的公开 API,
     * 需要通过读取 Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES 解析 ComponentName 列表。
     */
    private fun isAccessibilityEnabled(): Boolean {
        val expected = ComponentName(this, KeepAliveService::class.java).flattenToString()
        val enabled = try {
            Settings.Secure.getString(
                contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            )
        } catch (_: Exception) {
            null
        }
        if (enabled.isNullOrEmpty()) return false
        val splitter = TextUtils.SimpleStringSplitter(':')
        splitter.setString(enabled)
        while (splitter.hasNext()) {
            if (splitter.next() == expected) return true
        }
        return false
    }

    /** 跳转到无障碍系统页 — 供 Dart 侧"去开启"按钮调用。 */
    private fun openAccessibilitySettings() {
        try {
            startActivity(KeepAliveService.buildOpenSettingsIntent())
        } catch (_: Exception) {
            // 兜底:打开发者选项页,再让用户自行找无障碍
            try {
                startActivity(Intent(Settings.ACTION_SETTINGS)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            } catch (_: Exception) { }
        }
    }
}

/**
 * KeepAliveService — 仅作为保活锚点,不做任何 UI 操作。
 *
 * 系统对运行无障碍服务的应用默认放宽电池优化限制,进程不会在长熄屏后被回收。
 * onAccessibilityEvent 空实现,这里只为挂个系统级"重要服务"的标记。
 */
class KeepAliveService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 空实现 — 不处理任何事件,不做任何 UI 操作
    }

    override fun onInterrupt() { }

    companion object {
        fun buildOpenSettingsIntent(): Intent =
            Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}
