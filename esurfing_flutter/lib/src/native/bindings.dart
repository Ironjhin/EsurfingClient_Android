import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ============================================================
//  FFI 类型定义 — 对应 ffi_bridge.h
// ============================================================

/// C 函数签名声明
typedef init_c = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef start_c = Int32 Function(Int32);
typedef stop_c = Void Function();
typedef force_auth_reset_c = Void Function();
typedef is_stopped_c = Int32 Function();
typedef destroy_c = Void Function();

/// Dart 侧函数签名
typedef InitDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef StartDart = int Function(int);
typedef StopDart = void Function();
typedef ForceAuthResetDart = void Function();
typedef IsStoppedDart = int Function();
typedef DestroyDart = void Function();

// ============================================================
//  Native 库加载与符号绑定
// ============================================================

class NativeBindings {
  static DynamicLibrary? _lib;
  static NativeBindings? _instance;

  // ---------- 绑定的 C 函数 ----------
  late final InitDart esurfingClientInit;
  late final StartDart esurfingClientStart;
  late final StopDart esurfingClientStop;
  late final ForceAuthResetDart esurfingClientForceAuthReset;
  late final IsStoppedDart esurfingClientIsStopped;
  late final DestroyDart esurfingClientDestroy;

  static NativeBindings get instance {
    _instance ??= NativeBindings._();
    return _instance!;
  }

  NativeBindings._() {
    _loadLibrary();
    if (_lib != null) _bindFunctions();
  }

  void _loadLibrary() {
    if (Platform.isAndroid) {
      // Android NDK 编译出的 so 文件
      _lib = DynamicLibrary.open('libesurfing_client.so');
    } else if (Platform.isLinux) {
      final path = '/usr/local/lib/libesurfing_client.so';
      if (File(path).existsSync()) _lib = DynamicLibrary.open(path);
    }
  }

  void _bindFunctions() {
    final l = _lib!;
    esurfingClientInit = l
        .lookupFunction<init_c, InitDart>('esurfing_client_init');
    esurfingClientStart = l
        .lookupFunction<start_c, StartDart>('esurfing_client_start');
    esurfingClientStop = l
        .lookupFunction<stop_c, StopDart>('esurfing_client_stop');
    esurfingClientForceAuthReset = l
        .lookupFunction<force_auth_reset_c, ForceAuthResetDart>('esurfing_client_force_auth_reset');
    esurfingClientIsStopped = l
        .lookupFunction<is_stopped_c, IsStoppedDart>('esurfing_client_is_stopped');
    esurfingClientDestroy = l
        .lookupFunction<destroy_c, DestroyDart>('esurfing_client_destroy');
  }

  bool get isLoaded => _lib != null;

  void unload() {
    _lib = null;
    _instance = null;
  }
}
