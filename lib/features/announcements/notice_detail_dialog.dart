import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';

/// 公告详情弹窗（T7.5）。
///
/// 公告正文来自 site-config.announcement，是纯文本（后台多行输入），
/// 因此这里用 SelectableText 原样展示、保留换行，不做 Markdown/HTML 解析。
class NoticeDetailDialog extends StatelessWidget {
  final String content;

  const NoticeDetailDialog({super.key, required this.content});

  /// 统一入口：调用方不必自己管 context 与返回值。
  static Future<void> show(BuildContext context, String content) {
    return showDialog<void>(
      context: context,
      builder: (_) => NoticeDetailDialog(content: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = content.trim();
    return AlertDialog(
      title: const Text('公告'),
      content: ConstrainedBox(
        // 公告可能很长：限高 + 内部滚动，避免撑出屏幕。
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        child: SingleChildScrollView(
          child: SelectableText(
            text.isEmpty ? '暂无公告' : text,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.7),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    );
  }
}

/// 公告条目封装：仅在 [hasNotice] 时渲染（首页/设置页的接入点用它）。
///
/// M5 首页与 M8 设置页由各自 Agent 实现，这里提供可复用的横幅与入口，
/// 避免他们重复写「取 site-config → 判空 → 弹窗」。
class NoticeBanner extends StatelessWidget {
  final String announcement;
  final VoidCallback? onClose;

  const NoticeBanner({
    super.key,
    required this.announcement,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final firstLine = announcement.trim().split('\n').first;
    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => NoticeDetailDialog.show(context, announcement),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.base, Sp.md, Sp.sm, Sp.md),
          child: Row(
            children: [
              Icon(Icons.campaign_outlined,
                  size: 20, color: cs.onSecondaryContainer),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  firstLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: cs.onSecondaryContainer),
                ),
              ),
              if (onClose != null)
                SizedBox(
                  width: Sp.minTouch,
                  height: Sp.minTouch,
                  child: IconButton(
                    tooltip: '关闭公告',
                    onPressed: onClose,
                    icon: Icon(Icons.close,
                        size: 20, color: cs.onSecondaryContainer),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: Sp.sm),
                  child: Icon(Icons.chevron_right,
                      size: 20, color: cs.onSecondaryContainer),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
