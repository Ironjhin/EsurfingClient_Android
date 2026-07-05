package com.example.esurfing_client

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

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
