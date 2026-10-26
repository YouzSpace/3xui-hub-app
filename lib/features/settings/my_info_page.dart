import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/user_profile.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/copy_field.dart';

/// 我的信息（T8.1 账号分组）：邮箱 / 订阅 token 可复制。
///
/// 只读展示，不做编辑 —— 邮箱与订阅 token 都是后端生成或绑定的，
/// 改它们要回网站，App 里给个复制入口就够了。
class MyInfoPage extends ConsumerWidget {
  const MyInfoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('我的信息')),
      body: user.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 3),
        ),
        error: (e, _) => ErrorView(
          message: e is ApiException ? e.message : '加载失败，请检查网络',
          onRetry: () => ref.read(userProvider.notifier).refresh(),
        ),
        data: (profile) {
          if (profile == null) {
            return const EmptyView(
              icon: Icons.person_off_outlined,
              text: '未登录',
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(userProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(Sp.base),
              children: [
                CopyField(
                  value: profile.email,
                  label: '邮箱',
                  copiedHint: '邮箱已复制',
                ),
                const SizedBox(height: Sp.md),
                CopyField(
                  value: profile.token,
                  label: '订阅',
                  copiedHint: '订阅 token 已复制',
                ),
                const SizedBox(height: Sp.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Sp.xs),
                  child: Text(
                    '订阅 token 用于客户端导入订阅，等同于账号凭证，请勿分享给他人。',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: Sp.lg),
                _InfoRow(label: '当前套餐', value: _planLabel(profile)),
              ],
            ),
          );
        },
      ),
    );
  }

  /// 套餐展示：无套餐显示「未订阅」，纯第三方套餐标出来（流量不归本站统计）。
  String _planLabel(UserProfile profile) {
    if (profile.planId == 0 || profile.planName.isEmpty) return '未订阅';
    if (!profile.planIncludeLocal) return '${profile.planName}（第三方套餐）';
    return profile.planName;
  }
}

/// 只读信息行（label 左、value 右，value 支持多行）。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.xs, vertical: Sp.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
            ),
          ),
        ],
      ),
    );
  }
}
