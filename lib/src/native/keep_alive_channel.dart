import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// 与原生 Android 端通信的通道 — 处理无障碍保活相关操作
class KeepAliveChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.esurfing_client/keepalive');

  /// 本 APP 的无障碍服务是否已开启 — 调用原生查询。
  static Future<bool> get isAccessibilityEnabled async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isAccessibilityEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // MainActivity 未覆盖旧的默认实现或纯 Dart 构建时降级 — 返回 false 让 UI 显示引导按钮
      return false;
    }
  }

  /// 跳转到无障碍系统页 — 由 MainActivity 直接调 Settings.ACTION_ACCESSIBILITY_SETTINGS.
  static Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException {
      // 即使原生侧 start Activity 失败也忽略 — 用户会停留在当前页面,不会闪退
    } on MissingPluginException {
      // ignore
    }
  }
}
