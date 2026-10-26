import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/user_profile.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/traffic_card.dart';
import '../announcements/notice_detail_dialog.dart';
import '../announcements/site_content_providers.dart';
import '../plans/plans_routes.dart';
import '../update/update_dialog.dart';
import '../update/update_providers.dart';
import 'connect_area.dart';
import 'home_providers.dart';
import 'home_stagger.dart';
import 'notice_bar.dart';

/// 首页（T5.1）：AppBar（logo + 站点名 + 公告红点）
/// → 公告条 → 连接区 → 流量卡片 → 更新提示条，整页下拉刷新。
///
/// 节点 / 套餐 / 邀请已经在底部导航里，这里不再重复放快捷入口。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 状态联动（T5.6）挂在首页存活期间：协议变更 / 节点失效都在这里收口。
    ref.watch(homeSyncProvider);

    // 联动产生的一次性提示 → SnackBar（读后即清，避免重复弹）。
    ref.listen<String?>(homeNoticeProvider, (_, next) {
      if (next == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        showHomeSnack(context, next);
        ref.read(homeNoticeProvider.notifier).state = null;
      });
    });

    final user = ref.watch(userProvider);
    final site = ref.watch(siteContentProvider).valueOrNull;
    final announcement = site?.announcement.trim() ?? '';

    return Scaffold(
      appBar: _HomeAppBar(
        siteTitle: site?.siteTitle ?? '',
        hasNotice: announcement.isNotEmpty,
        onNoticeTap: announcement.isEmpty
            ? null
            : () => NoticeDetailDialog.show(context, announcement),
      ),
      body: user.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 3),
        ),
        error: (_, _) => ErrorView(
          message: '加载失败，请检查网络',
          onRetry: () => ref.read(homeRefresherProvider)(),
        ),
        data: (profile) {
          if (profile == null) {
            // 401 已清 token，路由守卫会跳登录；这里只兜底一帧。
            return const EmptyView(
              icon: Icons.person_off_outlined,
              text: '未登录',
            );
          }
          return _HomeBody(profile: profile, announcement: announcement);
        },
      ),
    );
  }
}

/// AppBar：左站点 logo + 站点名，右公告图标（有公告时带小红点）。
class _HomeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _HomeAppBar({
    required this.siteTitle,
    required this.hasNotice,
    required this.onNoticeTap,
  });

  final String siteTitle;
  final bool hasNotice;
  final VoidCallback? onNoticeTap;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final title = siteTitle.isEmpty ? 'ControlHub' : siteTitle;
    return AppBar(
      titleSpacing: Sp.base,
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(Sp.sm),
            ),
            child: Icon(Icons.shield_moon_outlined,
                size: 20, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: Sp.md),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 20, color: cs.onSurface),
            ),
          ),
        ],
      ),
      actions: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              tooltip: '公告',
              onPressed: onNoticeTap,
              icon: Icon(
                hasNotice
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
                color: hasNotice ? cs.onSurface : cs.onSurfaceVariant,
              ),
            ),
            if (hasNotice)
              Positioned(
                right: Sp.md,
                top: Sp.md,
                child: Container(
                  width: Sp.sm,
                  height: Sp.sm,
                  decoration:
                      BoxDecoration(color: cs.error, shape: BoxShape.circle),
                ),
              ),
          ],
        ),
        const SizedBox(width: Sp.xs),
      ],
    );
  }
}

/// 滚动区：公告 → 连接区 → 流量卡 → 更新提示，整页下拉刷新。
class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.profile, required this.announcement});

  final UserProfile profile;
  final String announcement;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showNotice =
        announcement.isNotEmpty && !ref.watch(noticeDismissedProvider);
    final update = ref.watch(optionalUpdateProvider);

    return RefreshIndicator(
      onRefresh: () => ref.read(homeRefresherProvider)(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          Sp.base,
          Sp.sm,
          Sp.base,
          // 底栏浮在内容上（AppShell extendBody），给玻璃留出高度。
          Sp.xxl + Sp.base,
        ),
        children: [
          if (showNotice) ...[
            HomeStagger(
              index: 0,
              child: HomeNoticeBar(
                announcement: announcement,
                onDismiss: () =>
                    ref.read(noticeDismissedProvider.notifier).state = true,
              ),
            ),
            const SizedBox(height: Sp.base),
          ],
          HomeStagger(index: 1, child: ConnectArea(profile: profile)),
          const SizedBox(height: Sp.lg),
          HomeStagger(
            index: 2,
            child: TrafficCard(
              profile: profile,
              onBuyPlan: () => context.go(PlansRoutes.plans),
            ),
          ),
          if (update != null) ...[
            const SizedBox(height: Sp.md),
            HomeStagger(
              index: 3,
              child: UpdateHintBar(
                versionName: update.latestName ?? '',
                onTap: () => showUpdateDialog(
                  context,
                  update,
                  installer: ref.read(apkInstallerProvider),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
