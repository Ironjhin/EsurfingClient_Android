package com.example.esurfing_client

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityEvent

/**
 * KeepAliveService — 仅作为保活锚点,不做任何 UI 操作。
 *
 * 系统对运行无障碍服务的应用默认放宽电池优化限制,进程不会在长熄屏后被回收。
 * onAccessibilityEvent 可以留空,这里只为挂个系统级"重要服务"的标记。
 */
class KeepAliveService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        // 连接成功 — 什么都不做
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // 完全不处理任何事件,不做任何 UI 操作
        // 此方法必须存在但是可以为空
    }

    override fun onInterrupt() {
        // 系统中断时的回调,什么都不做
    }

    override fun onUnbind(intent: Intent?): Boolean {
        return super.onUnbind(intent)
    }

    companion object {
        /**
         * 构造用于打开无障碍设置页的 Intent,Flutter 端调用。
         */
        fun buildOpenSettingsIntent(): Intent {
            return Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }
}
