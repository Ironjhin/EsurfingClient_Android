import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// ============================================================
//  FFI 类型定义 — 对应 ffi_bridge.h
// ============================================================

/// C 函数签名声明
typedef InitC = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef StartC = Int32 Function(Int32);
typedef StopC = Void Function();
typedef IsStoppedC = Int32 Function();
typedef DestroyC = Void Function();
typedef ClearLogC = Void Function();
typedef InitNativeEnvC = Void Function(Pointer<Utf8>);
typedef ForceAuthResetC = Void Function();
typedef GetAuthStateC = Int32 Function(Int32);

/// Dart 侧函数签名
typedef InitDart = int Function(Pointer<Utf8>, Pointer<Utf8>);
typedef StartDart = int Function(int);
typedef StopDart = void Function();
typedef IsStoppedDart = int Function();
typedef DestroyDart = void Function();
typedef ClearLogDart = void Function();
typedef InitNativeEnvDart = void Function(Pointer<Utf8>);
typedef ForceAuthResetDart = void Function();
typedef GetAuthStateDart = int Function(int);

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
  late final IsStoppedDart esurfingClientIsStopped;
  late final DestroyDart esurfingClientDestroy;
  late final ClearLogDart esurfingClientClearLog;
  late final InitNativeEnvDart initNativeEnv;
  late final ForceAuthResetDart esurfingClientForceAuthReset;
  late final GetAuthStateDart esurfingClientGetAuthState;

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
      const path = '/usr/local/lib/libesurfing_client.so';
      if (File(path).existsSync()) _lib = DynamicLibrary.open(path);
    }
  }

  void _bindFunctions() {
    final l = _lib!;
    esurfingClientInit = l
        .lookupFunction<InitC, InitDart>('esurfing_client_init');
    esurfingClientStart = l
        .lookupFunction<StartC, StartDart>('esurfing_client_start');
    esurfingClientStop = l
        .lookupFunction<StopC, StopDart>('esurfing_client_stop');
    esurfingClientIsStopped = l
        .lookupFunction<IsStoppedC, IsStoppedDart>('esurfing_client_is_stopped');
    esurfingClientDestroy = l
        .lookupFunction<DestroyC, DestroyDart>('esurfing_client_destroy');
    esurfingClientClearLog = l
        .lookupFunction<ClearLogC, ClearLogDart>('esurfing_client_clear_log');
    initNativeEnv = l
        .lookupFunction<InitNativeEnvC, InitNativeEnvDart>('init_native_env');
    esurfingClientForceAuthReset = l
        .lookupFunction<ForceAuthResetC, ForceAuthResetDart>('esurfing_client_force_auth_reset');
    esurfingClientGetAuthState = l
        .lookupFunction<GetAuthStateC, GetAuthStateDart>('esurfing_client_get_auth_state');
  }

  bool get isLoaded => _lib != null;

  void unload() {
    _lib = null;
    _instance = null;
  }
}
