import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import '../native/bindings.dart';

/// 实时日志读取器 — 基于字节偏移量的增量轮询
class LogReader extends ChangeNotifier {
  Timer? _timer;
  String _content = '';
  bool _paused = false;

  /// 上次清除时文件末尾的字节偏移，下次轮询只读取此偏移之后的新数据
  int _clearByteOffset = 0;

  String get content => _content;
  bool get isRunning => _timer != null;

  /// 启动轮询
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  /// 暂停轮询
  void pause() {
    _paused = true;
  }

  /// 恢复轮询
  void resume() {
    _paused = false;
  }

  /// 停止轮询并释放资源
  void stop() {
    _timer?.cancel();
    _timer = null;
    _paused = false;
  }

  /// 清空日志：C 层同源物理截断 + 偏移量重置
  void clear() {
    _content = '';

    // 1. C 层同源进程内截断（持有文件句柄，100% 成功）
    final bindings = NativeBindings.instance;
    if (bindings.isLoaded) {
      try {
        bindings.esurfingClientClearLog();
      } catch (_) {}
    }

    // 2. 截断后文件应为 0 字节，偏移归零
    _clearByteOffset = 0;

    // 3. 异步确认实际文件长度（兜底，防止 C 层未加载时偏移不准）
    _syncClearOffset();

    notifyListeners();
  }

  /// 行数超限触发的内部重置 — 不调用 notifyListeners(调用方自己决定)
  /// 复用 clear() 的 C 端物理截断 + 偏移重置,仅内存 _content 一并清空。
  void _clearLogAndReset() {
    _content = '';
    final bindings = NativeBindings.instance;
    if (bindings.isLoaded) {
      try {
        bindings.esurfingClientClearLog();
      } catch (_) {}
    }
    _clearByteOffset = 0;
  }

  Future<void> _syncClearOffset() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/run.log');
      if (await file.exists()) {
        _clearByteOffset = await file.length();
      }
    } catch (_) {}
  }

  Future<void> _poll() async {
    if (_paused) return;
    RandomAccessFile? raf;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/run.log');
      if (!await file.exists()) {
        if (_content != '(log file not available yet)') {
          _content = '(log file not available yet)';
          notifyListeners();
        }
        return;
      }

      final length = await file.length();

      // 文件被轮转/重建（新文件小于记录的偏移），从头开始
      if (length < _clearByteOffset) {
        _clearByteOffset = 0;
      }

      // 无新数据，跳过
      if (length <= _clearByteOffset) {
        return;
      }

      // 只读偏移之后的增量字节
      raf = await file.open();
      await raf.setPosition(_clearByteOffset);
      final bytes = await raf.read((length - _clearByteOffset).toInt());
      final chunk = utf8.decode(bytes, allowMalformed: true);

      _content += chunk;

      // ── 行数上限:超过 1000 行即截断,清掉前面的内容 ──
      if (_content.isNotEmpty) {
        final lines = '\n'.allMatches(_content).length + 1;
        if (lines > 1000) {
          // 磁盘 + 内存 同步清空,C 端下一次写又从零开始,规模可控
          _clearLogAndReset();
          notifyListeners();
          return;
        }
      }

      // 内存上限保护：只保留尾部 524288 字符
      if (_content.length > 524288) {
        _content = _content.substring(_content.length - 524288);
        // 丢弃对应字节数，下次从头读以防止截断行被重复拼接
        _clearByteOffset = 0;
      } else {
        // 正常前进偏移
        _clearByteOffset = length;
      }

      notifyListeners();
    } catch (_) {
      // 文件可能被日志系统轮转锁定，静默忽略
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
