import 'package:flutter/material.dart';

import '../core/theme/spacing.dart';
import '../core/ui/motion.dart';
import '../core/utils/formatters.dart';
import '../data/models/user_profile.dart';
import 'app_card.dart';
import 'rolling_number.dart';
import 'traffic_summary.dart';

export 'traffic_summary.dart';

/// 流量卡片（T5.3）：三种套餐状态 + 数字滚动过渡（400ms）。
///
/// 判定规则与纯数据投影在 [TrafficSummary]，本文件只负责呈现。
class TrafficCard extends StatelessWidget {
  const TrafficCard({super.key, required this.profile, required this.onBuyPlan});

  final UserProfile profile;

  /// 「去选购」：由首页决定跳哪个路由（卡片自己不依赖 go_router）。
  final VoidCallback onBuyPlan;

  @override
  Widget build(BuildContext context) {
    final summary = TrafficSummary.fromProfile(profile);
    return AppCard(
      child: switch (summary.state) {
        TrafficPlanState.noPlan => _NoPlan(onBuy: onBuyPlan),
        TrafficPlanState.thirdParty => _ThirdParty(summary: summary),
        TrafficPlanState.normal => _Normal(summary: summary),
      },
    );
  }
}

/// 未订阅：一句话 + 「去选购」。
class _NoPlan extends StatelessWidget {
  const _NoPlan({required this.onBuy});

  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.data_usage, size: 20, color: cs.onSurfaceVariant),
            const SizedBox(width: Sp.sm),
            Text('未订阅套餐',
                key: const ValueKey('no-plan'), style: text.titleMedium),
          ],
        ),
        const SizedBox(height: Sp.sm),
        Text('订阅后即可查看本月流量与到期时间',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Sp.base),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonal(onPressed: onBuy, child: const Text('去选购')),
        ),
      ],
    );
  }
}

/// 纯第三方套餐：只显示到期日期，不显示流量（后端语义）。
class _ThirdParty extends StatelessWidget {
  const _ThirdParty({required this.summary});

  final TrafficSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(summary.planName.isEmpty ? '已订阅套餐' : summary.planName,
            key: const ValueKey('third-party'), style: text.titleMedium),
        const SizedBox(height: Sp.xs),
        Text('本套餐为第三方套餐，流量在对应平台查看',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Sp.base),
        KeyValue(label: '到期时间', value: formatDate(summary.expiredAt)),
      ],
    );
  }
}

/// 本地套餐：本月已用 / 剩余 + 进度条 + 到期 / 距重置。
class _Normal extends StatelessWidget {
  const _Normal({required this.summary});

  final TrafficSummary summary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final progress = summary.progress;
    final barColor = summary.isNearLimit ? cs.error : cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(summary.isTotal ? '已用流量' : '本月已用',
                style: text.titleMedium),
            const Spacer(),
            if (summary.isUnlimited)
              Text('∞',
                  key: const ValueKey('unlimited'),
                  style: text.headlineMedium
                      ?.copyWith(color: cs.onSurfaceVariant))
            else
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('剩余 ', style: text.bodySmall),
                  RollingNumber(
                    text: formatBytes(summary.remaining, fractionDigits: 2),
                    style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: Sp.md),
        // 进度条：不限量时隐藏；>90% 转 error 色。
        if (progress != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: Motion.panel,
              curve: Motion.easeOut,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: Sp.sm,
                color: barColor,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: Sp.xs),
          RollingNumber(
            text: '${formatBytes(summary.used)} / ${formatBytes(summary.limit)}',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        if (summary.isNearLimit) ...[
          const SizedBox(height: Sp.sm),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
              const SizedBox(width: Sp.xs),
              Text('流量即将用完',
                  style: text.bodySmall?.copyWith(color: cs.error)),
            ],
          ),
        ],
        const SizedBox(height: Sp.base),
        Row(
          children: [
            Expanded(
              child: KeyValue(
                label: '到期时间',
                value: summary.isTotal
                    ? '长期有效'
                    : formatDate(summary.expiredAt),
              ),
            ),
            // total（一次性流量）套餐没有月度重置概念，不显示「距重置」。
            if (!summary.isTotal)
              Expanded(
                child: KeyValue(
                  label: '距重置',
                  value: summary.resetAt == null
                      ? '—'
                      : '${daysLeft(summary.resetAt)} 天',
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 两列键值（label 小字 + value 半粗）。
class KeyValue extends StatelessWidget {
  const KeyValue({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        const SizedBox(height: Sp.xs),
        Text(value,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}
