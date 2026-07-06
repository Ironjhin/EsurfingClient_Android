import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'bindings.dart';

/// 认证控制器 — 负责管理 C 层认证线程的生命周期
///
/// 由于 C 层的 dialer_app() / work() 是同步阻塞的，
/// 本控制器将其放在后台 [Isolate] 中运行，确保 UI 线程不被阻塞。
///
/// 用户点击「停止」时，主 Isolate 通过 FFI 调用 [esurfing_client_stop]，
/// 设置 [g_need_exit] 让后台线程安全退出。
class AuthController {
  static AuthController? _instance;

  bool _initialized = false;
  bool _running = false;
  Isolate? _workerIsolate;
  SendPort? _workerSendPort;
  ReceivePort? _mainReceivePort;

  /// 回调 — 状态变更通知 UI
  void Function(bool isRunning, String status)? onStatusChanged;

  AuthController._();

  static AuthController get instance {
    _instance ??= AuthController._();
    return _instance!;
  }

  bool get isInitialized => _initialized;
  bool get isRunning => _running;

  /// ================================================================
  ///  注入 Android 沙盒路径到 C 层（应在 initialize 前调用）
  /// ================================================================
  void initNativeEnv(String sandboxPath) {
    final bindings = NativeBindings.instance;
    if (!bindings.isLoaded) return;

    final pathPtr = sandboxPath.toNativeUtf8();
    try {
      bindings.initNativeEnv(pathPtr);
    } finally {
      calloc.free(pathPtr);
    }
  }

  /// ================================================================
  ///  初始化 C 层：传入 Android 沙盒路径与 JSON 配置
  /// ================================================================
  Future<bool> initialize(String dataDir, String configJson) async {
    if (_initialized) return true;

    final bindings = NativeBindings.instance;
    if (!bindings.isLoaded) return false;

    final dataDirPtr = dataDir.toNativeUtf8();
    final configPtr = configJson.toNativeUtf8();
    try {
      final ret = bindings.esurfingClientInit(dataDirPtr, configPtr);
      _initialized = (ret == 0);
      return _initialized;
    } catch (e) {
      _initialized = false;
      return false;
    } finally {
      calloc.free(dataDirPtr);
      calloc.free(configPtr);
    }
  }

  /// ================================================================
  ///  启动认证 Isolate
  /// ================================================================
  Future<bool> start({int accountCount = 1}) async {
    if (_initialized == false) return false;
    if (_running) return true;

    try {
      _mainReceivePort = ReceivePort();

      // 启动 Isolate 作为 C 层认证线程的宿主容器。
      // Isolate 内部不直接调用 C 函数（C 层已自行创建 pthread），
      // 这里 Isolate 仅用于监控与生命周期管理。
      _workerIsolate = await Isolate.spawn(
        _workerEntryPoint,
        _mainReceivePort!.sendPort,
      );

      // 等待 worker 发回确认
      _workerSendPort = await _mainReceivePort!.first as SendPort;

      // 通知 worker 开始认证
      _workerSendPort!.send(_StartCommand(accountCount));
      _running = true;
      onStatusChanged?.call(true, 'Running — authentication active');
      return true;
    } catch (e) {
      _running = false;
      onStatusChanged?.call(false, 'Failed to start: $e');
      return false;
    }
  }

  /// ================================================================
  ///  安全停止 — 调用 C 层 stop_dialer / esurfing_client_stop
  /// ================================================================
  Future<void> stop({bool waitForExit = true}) async {
    if (!_running) return;

    // 1. 通知 C 层设置退出标志
    final bindings = NativeBindings.instance;
    if (bindings.isLoaded) {
      try {
        bindings.esurfingClientStop();
        onStatusChanged?.call(false, 'Stopping...');

        // 轮询等待 C 层线程退出（最多 5 秒）
        if (waitForExit) {
          for (int i = 0; i < 50; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            if (bindings.esurfingClientIsStopped() == 1) break;
          }
        }
      } catch (_) {}
    }

    // 2. 通知 Isolate 退出
    _workerSendPort?.send(_StopCommand());
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    _workerSendPort = null;
    _mainReceivePort?.close();
    _mainReceivePort = null;
    _running = false;
    onStatusChanged?.call(false, 'Stopped');
  }

  /// ================================================================
  ///  彻底销毁 C 层资源
  /// ================================================================
  void destroy() {
    stop(waitForExit: false);
    final bindings = NativeBindings.instance;
    if (bindings.isLoaded) {
      try {
        bindings.esurfingClientDestroy();
      } catch (_) {}
    }
    _initialized = false;
  }

  /// ================================================================
  ///  强制重新认证 — 设置 is_need_reset, 后台工作循环立即重建拨号线程
  /// ================================================================
  Future<void> forceAuthReset() async {
    if (!_running) return;
    final bindings = NativeBindings.instance;
    if (!bindings.isLoaded) return;
    try {
      bindings.esurfingClientForceAuthReset();
      onStatusChanged?.call(true, '正在强制重新认证...');
    } catch (_) {}
  }

  /// ================================================================
  ///  Isolate 入口 — 在此调用 FFI 启动 C 层认证线程
  /// ================================================================
  static void _workerEntryPoint(SendPort mainSendPort) {
    final receivePort = ReceivePort();
    mainSendPort.send(receivePort.sendPort);

    receivePort.listen((message) {
      if (message is _StartCommand) {
        final bindings = NativeBindings.instance;
        if (bindings.isLoaded) {
          for (int i = 0; i < message.accountCount; i++) {
            bindings.esurfingClientStart(i);
          }
        }
      } else if (message is _StopCommand) {
        receivePort.close();
        Isolate.exit();
      }
    });
  }
}

/// Isolate 内部消息
class _StartCommand {
  final int accountCount;
  _StartCommand(this.accountCount);
}
class _StopCommand {}
