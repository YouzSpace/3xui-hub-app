import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/spacing.dart';
import '../core/ui/motion.dart';
import '../core/ui/app_toast.dart';

/// 可复制字段（T1.7）：文本 + 复制按钮，复制成功 SnackBar 提示、
/// 图标短暂变勾后恢复（ui-glass-motion §3.2 #9：200ms morph，2s 后恢复）。
class CopyField extends StatefulWidget {
  final String value;
  final String? label;
  final String copiedHint;

  const CopyField({
    super.key,
    required this.value,
    this.label,
    this.copiedHint = '已复制',
  });

  @override
  State<CopyField> createState() => _CopyFieldState();
}

class _CopyFieldState extends State<CopyField> {
  bool _copied = false;

  Future<void> _copy() async {
    if (_copied) return;
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    showAppToast(context, widget.copiedHint);
    // 2s 后恢复复制图标（§3.2 #9，周期取 Motion.copyReset）。
    await Future<void>.delayed(Motion.copyReset);
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.base, vertical: Sp.md),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          if (widget.label != null) ...[
            Text(
              widget.label!,
              style: textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: Sp.md),
          ],
          Expanded(
            child: Text(
              widget.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium
                  ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          const SizedBox(width: Sp.sm),
          SizedBox(
            width: Sp.minTouch,
            height: Sp.minTouch,
            child: IconButton(
              // 复制变勾（图标切换 Motion.small，2s 恢复）。
              icon: AnimatedSwitcher(
                duration: Motion.small,
                child: Icon(
                  _copied ? Icons.check : Icons.copy_all_outlined,
                  key: ValueKey(_copied),
                  size: 20,
                  color: _copied ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
              onPressed: _copy,
              tooltip: '复制',
            ),
          ),
        ],
      ),
    );
  }
}
