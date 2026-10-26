import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../announcements/notice_detail_dialog.dart';

/// 首页公告条（T5.4）：最多 2 行、超出省略，点击看全文，可关闭。
///
/// 关闭状态由调用方持有（`noticeDismissedProvider`，只存内存），
/// 本次会话不再出现；弹窗复用 M7 的 [NoticeDetailDialog]。
class HomeNoticeBar extends StatelessWidget {
  const HomeNoticeBar({
    super.key,
    required this.announcement,
    required this.onDismiss,
  });

  final String announcement;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final body = announcement.trim();

    return Material(
      color: cs.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => NoticeDetailDialog.show(context, body),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Sp.base, Sp.md, Sp.xs, Sp.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.campaign_outlined,
                  size: 20, color: cs.onSecondaryContainer),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium?.copyWith(
                    color: cs.onSecondaryContainer,
                    height: 1.4,
                  ),
                ),
              ),
              SizedBox(
                width: Sp.minTouch,
                height: Sp.minTouch - Sp.md,
                child: IconButton(
                  tooltip: '关闭公告',
                  onPressed: onDismiss,
                  icon: Icon(Icons.close,
                      size: 20, color: cs.onSecondaryContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 更新提示条（T5.1 ④）：仅 `action == optional` 时出现，点击进更新弹窗。
class UpdateHintBar extends StatelessWidget {
  const UpdateHintBar({
    super.key,
    required this.versionName,
    required this.onTap,
  });

  final String versionName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.base, vertical: Sp.md),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, size: 20, color: cs.primary),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  '发现新版本 $versionName，点击查看',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
