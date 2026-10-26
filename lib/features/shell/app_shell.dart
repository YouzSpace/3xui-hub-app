import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/glass_surface.dart';
import '../../core/ui/motion.dart';

/// 主壳（T1.10）：5 tab 底部导航，StatefulShellRoute.indexedStack
/// 保留各 tab 状态（切回来不重建、不丢滚动位置）。
///
/// 底栏用 GlassSurface（玻璃白名单唯一常驻位置），
/// 选中态 secondaryContainer 胶囊。
class AppShell extends StatelessWidget {
  final StatefulNavigationShell shell;

  const AppShell({super.key, required this.shell});

  static const _tabs = [
    ('首页', Icons.home_outlined, '/home'),
    ('节点', Icons.dns_outlined, '/nodes'),
    ('套餐', Icons.storefront_outlined, '/plans'),
    ('邀请', Icons.card_giftcard, '/invite'),
    ('我的', Icons.person_outline, '/settings'),
  ];

  void _onTap(int index) {
    shell.goBranch(
      index,
      // 再点当前 tab 回到该分支根部；其他分支保留栈。
      initialLocation: index == shell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      // 底栏浮在内容上（body 不加 bottom padding，让内容从玻璃下穿过）。
      extendBody: true,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Sp.sm, vertical: Sp.sm),
          child: GlassSurface(
            radius: BorderRadius.circular(Sp.xl),
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: _NavTab(
                        tab: _tabs[i],
                        selected: i == shell.currentIndex,
                        onTap: () => _onTap(i),
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
  final (String, IconData, String) tab;
  final bool selected;
  final VoidCallback onTap;

  const _NavTab({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (label, icon, _) = tab;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: SizedBox(
          height: Sp.minTouch,
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
