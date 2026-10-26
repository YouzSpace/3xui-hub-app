import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/motion.dart';
import '../../core/ui/state_views.dart';
import '../../widgets/app_card.dart';
import 'invite_share.dart';

/// 邀请码信息卡（T7.1）：大号等宽邀请码 + 复制 + 已邀请人数 + 分享。
///
/// 邀请码为空（后端未生成）时整块换成「暂无邀请码」+ 重试，
/// 不给用户一个注定失效的分享按钮。
class InviteCodeCard extends StatefulWidget {
  final String code;
  final int invitedCount;
  final String siteTitle;
  final VoidCallback onRetry;

  const InviteCodeCard({
    super.key,
    required this.code,
    required this.invitedCount,
    required this.siteTitle,
    required this.onRetry,
  });

  @override
  State<InviteCodeCard> createState() => _InviteCodeCardState();
}

class _InviteCodeCardState extends State<InviteCodeCard> {
  bool _copied = false;

  Future<void> _copy() async {
    if (_copied) return;
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('邀请码已复制')));
    // 与 CopyField 同一节奏：图标变勾 2s 后恢复（ui-glass-motion §3.2 #9）。
    await Future<void>.delayed(Motion.copyReset);
    if (mounted) setState(() => _copied = false);
  }

  Future<void> _share() async {
    final text = inviteShareText(
      code: widget.code,
      siteTitle: widget.siteTitle,
    );
    try {
      await Share.share(text);
    } catch (_) {
      // 分享面板拉起失败（无可用 App / 平台异常）不能静默吞掉。
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('分享失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.code.isEmpty) {
      return AppCard(
        child: EmptyView(
          icon: Icons.confirmation_number_outlined,
          text: '暂无邀请码',
          actionLabel: '重试',
          onAction: widget.onRetry,
        ),
      );
    }

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '我的邀请码',
                  style: textTheme.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              SizedBox(
                width: Sp.minTouch,
                height: Sp.minTouch,
                child: IconButton(
                  tooltip: '复制邀请码',
                  onPressed: _copy,
                  icon: AnimatedSwitcher(
                    duration: Motion.small,
                    child: Icon(
                      _copied ? Icons.check : Icons.copy_all_outlined,
                      key: ValueKey(_copied),
                      color: _copied ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
          ),
          // 等宽大号：码要「看起来像码」，读起来也不串行。
          Text(
            widget.code,
            style: textTheme.displaySmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: Sp.md),
          Text(
            '已成功邀请 ${widget.invitedCount} 人',
            style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: Sp.base),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _share,
              icon: const Icon(Icons.ios_share),
              label: const Text('分享邀请'),
            ),
          ),
        ],
      ),
    );
  }
}
