import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../providers/auth_providers.dart';

/// 首页（T2.5 最小实现）：
/// - userProvider 拉数据中 → 骨架屏
/// - 失败 → ErrorView + 重试（refresh）
/// - 有数据 → 简版欢迎卡；M5 再美化
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('首页')),
      body: user.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 3),
        ),
        error: (e, _) => ErrorView(
          message: '加载失败，请检查网络',
          onRetry: () => ref.read(userProvider.notifier).refresh(),
        ),
        data: (profile) {
          if (profile == null) {
            // 理论上到不了（401 已清 token 跳登录）。
            return const EmptyView(icon: Icons.person_off_outlined, text: '未登录');
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(userProvider.notifier).refresh(),
            child: ListView(
              padding: const EdgeInsets.all(Sp.base),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Sp.base),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(profile.email,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: Sp.sm),
                        Text('套餐：${profile.planName}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
