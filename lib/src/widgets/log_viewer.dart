import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../services/log_reader.dart';
import '../i18n/app_localizations.dart';

/// 终端样式的实时日志面板
///
/// 修复"整段日志塞进一个 SelectableText 导致灰块"的老问题:
/// 不在 ListView.builder 里虚拟化(那会丢跨行选择),而是把 SelectableText
/// 当成纯文本显示,让外层 SingleChildScrollView 做滚动 — 文本量在几千行
/// 内依然流畅,同时保留了系统原生的"长按选词/拖拽选区"交互.
class LogViewer extends StatefulWidget {
  final LogReader reader;

  const LogViewer({super.key, required this.reader});

  @override
  State<LogViewer> createState() => _LogViewerState();
}

class _LogViewerState extends State<LogViewer> {
  final ScrollController _scrollCtrl = ScrollController();
  double _fontSize = 12.0;
  bool _autoScroll = true;
  bool _expanded = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    widget.reader.addListener(_onLogUpdate);
  }

  @override
  void dispose() {
    widget.reader.removeListener(_onLogUpdate);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onLogUpdate() {
    // 用户手动上滑查看时,不自动滚到底(避免阅读中被拽走).
    if (!mounted || _paused) {
      if (mounted) setState(() {});
      return;
    }
    setState(() {});
    _scrollToBottom();
  }

  void _scrollToBottom() {
    if (!_autoScroll || !_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _exportLog() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/run.log');
      if (!await file.exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context).logPanelEmpty)),
          );
        }
        return;
      }

      // 复制到临时文件,避免分享时被日志系统锁定
      final tmpDir = await getTemporaryDirectory();
      final tmpFile = File('${tmpDir.path}/esurfing_run_log.txt');
      await file.copy(tmpFile.path);

      await Share.shareXFiles(
        [XFile(tmpFile.path)],
        text: 'ESurfing Client Run Log',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context).errorPrefix}: $e')),
        );
      }
    }
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
    });
    if (!_paused) {
      // 恢复后立即追赶一次.
      _scrollToBottom();
    }
  }

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final content = widget.reader.content;

    // 行数:split 会在尾部多出一项""(最后一行以\n结尾时),但数量等价可视行.
    final lineCount =
        content.isEmpty ? 0 : '\n'.allMatches(content).length + 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 展开/收缩标题栏
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: _expanded
                  ? const BorderRadius.vertical(top: Radius.circular(12))
                  : BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  i18n.logPanelTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                if (!_expanded)
                  Text(
                    '$lineCount ${i18n.logPanelLinesSuffix}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        // 展开后的日志内容
        if (_expanded) ...[
          // 工具栏
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              border: Border(top: BorderSide(color: Colors.grey.shade800)),
            ),
            child: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _toolBtn(
                  icon: Icons.vertical_align_bottom,
                  label: i18n.logPanelAutoScroll,
                  active: _autoScroll,
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                ),
                _toolBtn(
                  icon: _paused ? Icons.play_arrow : Icons.pause,
                  label: i18n.logPanelPauseScroll,
                  active: _paused,
                  onTap: _togglePause,
                ),
                _toolBtn(
                  icon: Icons.delete_outline,
                  label: i18n.logPanelClear,
                  active: false,
                  onTap: () => widget.reader.clear(),
                ),
                _toolBtn(
                  icon: Icons.file_upload_outlined,
                  label: i18n.logPanelExport,
                  active: false,
                  onTap: _exportLog,
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_fontSize.toInt()}px',
                      style: const TextStyle(color: Colors.grey, fontSize: 11),
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_decrease, size: 16),
                      color: Colors.grey,
                      onPressed: () => setState(
                          () => _fontSize = (_fontSize - 1).clamp(8.0, 28.0)),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: i18n.logPanelFontDec,
                    ),
                    IconButton(
                      icon: const Icon(Icons.text_increase, size: 16),
                      color: Colors.grey,
                      onPressed: () => setState(
                          () => _fontSize = (_fontSize + 1).clamp(8.0, 28.0)),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 28, minHeight: 28),
                      tooltip: i18n.logPanelFontInc,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 日志正文 — 终端样式
          Container(
            width: double.infinity,
            height: 280,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: content.isEmpty
                ? Center(
                    child: Text(
                      i18n.logPanelEmpty,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontFamily: 'monospace',
                        fontSize: _fontSize,
                      ),
                    ),
                  )
                : ClipRect(
                    child: Scrollbar(
                      controller: _scrollCtrl,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(8),
                        child: SelectableText(
                          content,
                          style: TextStyle(
                            color: const Color(0xFF00FF41),
                            fontFamily: 'monospace',
                            fontSize: _fontSize,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ],
    );
  }

  Widget _toolBtn({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: active ? const Color(0xFF00FF41) : Colors.grey,
              ),
              const SizedBox(width: 3),
              Text(
                label,
                style: TextStyle(
                  color: active ? const Color(0xFF00FF41) : Colors.grey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
