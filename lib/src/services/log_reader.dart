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
  bool _polling = false; // 防重入:上一次 _poll 没跑完就跳过下一次
  bool _isExpanded = false; // 是否展开查看: 折叠时跳过磁盘轮询节省能耗

  /// 上次清除时文件末尾的字节偏移，下次轮询只读取此偏移之后的新数据
  int _clearByteOffset = 0;

  String get content => _content;
  bool get isRunning => _timer != null;
  bool get isExpanded => _isExpanded;

  /// 启动轮询
  void start() {
    _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => _poll());
    // 启动时主动轻量读一次初始状态
    _poll(force: true);
  }

  /// 展开/折叠状态切换
  void setExpanded(bool expanded) {
    if (_isExpanded == expanded) return;
    _isExpanded = expanded;
    if (_isExpanded) {
      // 展开时立即拉取一次最新增量
      _poll(force: true);
    }
  }

  /// 暂停轮询
  void pause() {
    _paused = true;
  }

  /// 恢复轮询
  void resume() {
    _paused = false;
    if (_isExpanded) {
      _poll(force: true);
    }
  }

  /// 停止轮询并释放资源
  void stop() {
    _timer?.cancel();
    _timer = null;
    _paused = false;
    _isExpanded = false;
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

  Future<void> _poll({bool force = false}) async {
    if (!force && !_isExpanded) return;
    if (_paused || _polling) return;
    _polling = true;
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

      // ── 行数上限:超过 1000 行即在前端内存中平滑截断，保留最新 800 行，绝不清空底层文件 ──
      if (_content.isNotEmpty) {
        final newlineMatches = '\n'.allMatches(_content).toList();
        if (newlineMatches.length >= 1000) {
          final cutIndex = newlineMatches[newlineMatches.length - 800].end;
          _content = _content.substring(cutIndex);
        }
      }

      // 内存上限保护：只保留尾部 524288 字符
      if (_content.length > 524288) {
        _content = _content.substring(_content.length - 524288);
      }
      // 偏移量始终前进到当前文件末尾:内存里截断 _content 只是缩小显示窗口,
      // 不改变"文件已读到哪"。若在此清零,下次轮询会从头整段重读并追加,导致日志重复。
      _clearByteOffset = length;

      notifyListeners();
    } catch (_) {
      // 文件可能被日志系统轮转锁定，静默忽略
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
      _polling = false;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
