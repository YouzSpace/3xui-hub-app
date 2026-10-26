import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/plan.dart';
import '../../widgets/app_card.dart';

/// 套餐卡片（T6.3）。
///
/// 布局：名称 titleMedium + 类型 chip / 价格 displaySmall + 单位 /
/// 流量一行 / 立即购买按钮。
///
/// **纯第三方套餐**（`plan_include_local == false` 且挂了第三方线路）不显示流量，
/// 显示「流量随用随充」—— 第三方线路只管时间不管流量，后端也把流量字段清零了。
class PlanCard extends StatelessWidget {
  final Plan plan;
  final VoidCallback onBuy;

  const PlanCard({super.key, required this.plan, required this.onBuy});

  @override
  Widget build(BuildContext context) {
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
                  plan.name,
                  style: textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: Sp.sm),
              _TypeChip(label: plan.typeChipLabel),
            ],
          ),
          const SizedBox(height: Sp.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                plan.price.isZero ? '免费' : plan.price.display,
                style: textTheme.displaySmall?.copyWith(
                  // 金额用等宽数字，切换价格时不抖动。
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (!plan.price.isZero && plan.priceUnitLabel.isNotEmpty) ...[
                const SizedBox(width: Sp.xs),
                Text(
                  plan.priceUnitLabel,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ],
          ),
          // 多月周期套餐补一行「折合每月」，便于横向比价（Shop.vue 同款）。
          if (plan.isPeriod && plan.months > 1 && !plan.price.isZero) ...[
            const SizedBox(height: Sp.xs),
            Text(
              '${formatMoney(plan.monthlyEquivalent.yuan)}/月',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: Sp.md),
          _TrafficLine(plan: plan),
          const SizedBox(height: Sp.md),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onBuy,
              child: const Text('立即购买'),
            ),
          ),
        ],
      ),
    );
  }
}

/// 流量行：纯第三方 → 固定文案；周期 → 每月；总量 → 总量。
class _TrafficLine extends StatelessWidget {
  final Plan plan;

  const _TrafficLine({required this.plan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final String label;
    final String value;
    if (plan.isPureThirdParty) {
      // 第三方套餐不含本地节点：第三方只管时间，流量随用随充。
      label = '流量';
      value = '流量随用随充';
    } else if (plan.isPeriod) {
      final traffic = plan.monthlyTraffic ?? 0;
      label = '每月';
      value = traffic > 0 ? formatBytes(traffic) : '不限量';
    } else {
      final traffic = plan.totalTraffic ?? 0;
      label = '总量';
      value = traffic > 0 ? formatBytes(traffic) : '不限量';
    }
    return Row(
      children: [
        Icon(Icons.bolt_outlined, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: Sp.xs),
        Text(
          label,
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(width: Sp.sm),
        Expanded(
          child: Text(
            value,
            style: textTheme.bodyMedium
                ?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        if (plan.isPeriod && plan.months > 0)
          Text(
            '${plan.months} 个月',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// 类型 chip：labelSmall + secondaryContainer 圆角胶囊（不占 M3 角色）。
class _TypeChip extends StatelessWidget {
  final String label;

  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: 2),
      decoration: BoxDecoration(
        color: cs.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSecondaryContainer,
              fontWeight: FontWeight.w500,
            ),
      ),
    );
  }
}
