import 'package:flutter/material.dart';
import '../services/log_reader.dart';
import '../i18n/app_localizations.dart';

/// 终端样式的实时日志面板
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
    if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final i18n = AppLocalizations.of(context);
    final theme = Theme.of(context);

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
                Icon(
                  Icons.terminal,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
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
                    '${widget.reader.content.split('\n').length} lines',
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
              border: Border(
                top: BorderSide(color: Colors.grey.shade800),
              ),
            ),
            child: Row(
              children: [
                _toolBtn(
                  icon: Icons.vertical_align_bottom,
                  label: i18n.logPanelAutoScroll,
                  active: _autoScroll,
                  onTap: () => setState(() => _autoScroll = !_autoScroll),
                ),
                const SizedBox(width: 4),
                _toolBtn(
                  icon: Icons.delete_outline,
                  label: i18n.logPanelClear,
                  active: false,
                  onTap: () => widget.reader.clear(),
                ),
                const Spacer(),
                Text(
                  '${_fontSize.toInt()}px',
                  style: const TextStyle(color: Colors.grey, fontSize: 11),
                ),
                IconButton(
                  icon: const Icon(Icons.text_decrease, size: 16),
                  color: Colors.grey,
                  onPressed: () => setState(() => _fontSize = (_fontSize - 1).clamp(8.0, 28.0)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Decrease font size',
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase, size: 16),
                  color: Colors.grey,
                  onPressed: () => setState(() => _fontSize = (_fontSize + 1).clamp(8.0, 28.0)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Increase font size',
                ),
              ],
            ),
          ),
          // 日志正文 — 黑色终端样式
          Container(
            width: double.infinity,
            height: 280,
            decoration: const BoxDecoration(
              color: Color(0xFF1E1E1E),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: widget.reader.content.isEmpty
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
                : GestureDetector(
                    onScaleUpdate: (details) {
                      setState(() {
                        _fontSize = (_fontSize * details.scale).clamp(8.0, 28.0);
                      });
                    },
                    child: Scrollbar(
                      controller: _scrollCtrl,
                      thumbVisibility: true,
                      child: ListView(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.all(8),
                        children: [
                          SelectableText(
                            widget.reader.content,
                            style: TextStyle(
                              color: const Color(0xFF00FF41),
                              fontFamily: 'monospace',
                              fontSize: _fontSize,
                              height: 1.4,
                            ),
                          ),
                        ],
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
