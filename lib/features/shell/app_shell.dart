import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/motion.dart';
import '../../providers/auth_providers.dart';

/// 主壳（T1.10）：底部导航，StatefulShellRoute.indexedStack
/// 保留各 tab 状态（切回来不重建、不丢滚动位置）。
///
/// 底栏用实心圆角容器（非玻璃材质），选中态 secondaryContainer 胶囊。
///
/// branch 顺序固定：0=home、1=nodes、2=settings；
/// 无套餐（planId==0）时不显示「节点」tab，只留首页 / 我的。
/// 底栏内区高度（胶囊 32 + 间距 2 + label ≈ 50，取 72 给系统字体缩放留余量）。
const double _bottomBarInnerHeight = 72;

/// 底栏视觉总高度 = 内区 72 + 上下 padding 2*Sp.sm = 88。
/// tab 页面（extendBody）ListView 底部 padding 用它 + 系统底部安全区，
/// 避免最后一个元素被悬浮底栏挡住。
const double appBottomBarHeight = _bottomBarInnerHeight + Sp.sm * 2;

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell shell;

  const AppShell({super.key, required this.shell});

  /// 每个 tab 带它对应的 branch index（tab 可能被套餐状态裁剪，
  /// 不能用列表下标当 branch index）。
  static List<(String, IconData, String, int)> _tabs(bool hasPlan) => [
        ('首页', Icons.home_outlined, '/home', 0),
        if (hasPlan) ('节点', Icons.dns_outlined, '/nodes', 1),
        ('我的', Icons.person_outline, '/settings', 2),
      ];

  void _onTap(int branchIndex) {
    shell.goBranch(
      branchIndex,
      // 再点当前 tab 回到该分支根部；其他分支保留栈。
      initialLocation: branchIndex == shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).valueOrNull;
    final hasPlan = user != null && user.planId > 0;
    final tabs = _tabs(hasPlan);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: shell,
      // 底栏浮在内容上（body 不加 bottom padding，让内容从玻璃下穿过）。
      extendBody: true,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          child: Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainer,
              borderRadius: BorderRadius.circular(Sp.xl),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: SizedBox(
              height: _bottomBarInnerHeight,
              child: Row(
                children: [
                  for (final (label, icon, _, branchIndex) in tabs)
                    Expanded(
                      child: _NavTab(
                        label: label,
                        icon: icon,
                        selected: branchIndex == shell.currentIndex,
                        onTap: () => _onTap(branchIndex),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 单个 tab：选中态 secondaryContainer 胶囊（64×32，design-tokens §4）。
class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          // 胶囊 32 + 间距 2 + labelSmall 文字 ≈ 50+，minTouch(48) 放不下会溢出
          // （实测底部红色 OVERFLOW BOTTOM）；抬高到 60 给系统字体缩放留余量。
          height: Sp.minTouch + Sp.md,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 胶囊指示器：切换时 200ms 缩放过渡（流动感的 M1 基线实现，
              // 完整「前缘快后缘慢」弹性指示器随 M5 首页联调加强）。
              AnimatedContainer(
                duration: Motion.small,
                curve: Motion.emphasized,
                width: selected ? 64 : 48,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? cs.secondaryContainer : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: selected
                      ? cs.onSecondaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected
                          ? cs.onSurface
                          : cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
