import 'dart:io' show Platform;
import 'package:flutter/services.dart';

/// 与原生 Android 端通信的通道 — 处理无障碍保活相关操作
class KeepAliveChannel {
  static const MethodChannel _channel =
      MethodChannel('com.example.esurfing_client/keepalive');

  /// 本 APP 的无障碍服务是否已开启
  ///
  /// 采用纯 Dart 返回 false 策略:
  /// Flutter 默认已有 MainActivity.kt(kotlin/ 目录),
  /// 手写 Kotlin MainActivity 会与它冲突(Redeclaration 编译错误)。
  /// 所以我们不依赖原生检测,始终返回 false 让 UI 显示引导按钮,
  /// 用户手动开启无障碍后下次再点"去开启"会进入同一设置页。
  static Future<bool> get isAccessibilityEnabled async {
    return false;
  }

  /// 跳转到无障碍设置页 — 纯 Dart 降级方案
  ///
  /// 依赖 flutter 默认的 MainActivity 不处理我们的 channel method,
  /// 所以 MISS 时直接 fallback 为 android.provider.settings.ACTION_SETTINGS Intent,
  /// 由用户手动进入无障碍 > ESurfing Client。
  static Future<void> openAccessibilitySettings() async {
    if (!Platform.isAndroid) return;
    try {
      // MainActivity 未自定义 → Method 'openAccessibilitySettings' not implemented
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } on PlatformException {
      // ignore — 用户通过提示手动打开设置
    } on MissingPluginException {
      // ignore — 不会到这里,PlatformException 优先
    }
  }
}
