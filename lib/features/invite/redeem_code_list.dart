import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/invite_info.dart';
import '../../widgets/app_card.dart';

/// 兑换码区（T7.1）：码（等宽）+ 折扣 badge + 备注 + 状态。
///
/// 后端 `redeem_codes` 只保证 `code` / `status`，discount 与 note 有则展示、
/// 无则整块省略（不留空占位）。
class RedeemCodeList extends StatelessWidget {
  final List<RedeemCode> codes;

  const RedeemCodeList({super.key, required this.codes});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('我的兑换码', style: textTheme.titleMedium),
        const SizedBox(height: Sp.md),
        if (codes.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Sp.lg),
              child: Center(
                child: Text(
                  '暂无兑换码',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
          )
        else
          for (var i = 0; i < codes.length; i++) ...[
            if (i > 0) const SizedBox(height: Sp.md),
            _RedeemCodeTile(item: codes[i]),
          ],
      ],
    );
  }
}

class _RedeemCodeTile extends StatelessWidget {
  final RedeemCode item;

  const _RedeemCodeTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final discount = item.discountLabel;
    final usable = item.status == 'active';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                    // 不可用的码压低对比，一眼分得出「这张还能不能用」。
                    color: usable ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: Sp.sm),
              if (discount != null) ...[
                _Badge(
                  text: discount,
                  background: cs.secondaryContainer,
                  foreground: cs.onSecondaryContainer,
                ),
                const SizedBox(width: Sp.sm),
              ],
              _Badge(
                text: item.statusLabel,
                background:
                    usable ? cs.primaryContainer : cs.surfaceContainerHighest,
                foreground:
                    usable ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ],
          ),
          if (item.note != null) ...[
            const SizedBox(height: Sp.sm),
            Text(
              item.note!,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          if (item.expiresAt != null) ...[
            const SizedBox(height: Sp.xs),
            Text(
              '有效期至 ${formatDate(item.expiresAt)}',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// 小徽标（折扣 / 状态）。胶囊形，labelSmall。
class _Badge extends StatelessWidget {
  final String text;
  final Color background;
  final Color foreground;

  const _Badge({
    required this.text,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Sp.sm,
        vertical: Sp.xs / 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}
