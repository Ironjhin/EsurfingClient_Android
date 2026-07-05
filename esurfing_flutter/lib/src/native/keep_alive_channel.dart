import 'package:flutter/services.dart';

/// 与原生 Android 端通信的通道 — 处理无障碍保活相关操作
class KeepAliveChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.esurfing_client/keepalive');

  /// 本 APP 的无障碍服务是否已开启
  static Future<bool> get isAccessibilityEnabled async {
    try {
      final result = await _channel.invokeMethod<bool>('isAccessibilityEnabled');
      return result ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 跳转到无障碍设置页
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException {
      // ignore — 已在 Activity 内部处理
    } on MissingPluginException {
      // ignore — desktop 场景不存在此通道
    }
  }
}
