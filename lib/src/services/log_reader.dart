import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';

/// 实时日志读取器 — 每秒轮询沙盒中的 run.log
class LogReader extends ChangeNotifier {
  Timer? _timer;
  String _content = '';
  bool _paused = false;

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

  /// 清空当前缓存内容
  void clear() {
    _content = '';
    notifyListeners();
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
      // 只读末尾 512KB 避免 OOM
      final length = await file.length();
      final int offset = length > 524288 ? length - 524288 : 0;
      raf = await file.open(mode: FileMode.read);
      await raf.setPosition(offset);
      final bytes = await raf.read((length - offset).toInt());
      final newContent = utf8.decode(bytes, allowMalformed: true);
      if (newContent != _content) {
        _content = newContent;
        notifyListeners();
      }
    } catch (_) {
      // 文件可能被日志系统轮转锁定，静默忽略
    } finally {
      try {
        await raf?.close();
      } catch (_) {
        // 关闭文件句柄时的异常不影响下一轮轮询
      }
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
