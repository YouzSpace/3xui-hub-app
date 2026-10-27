import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/spacing.dart';
import '../../providers/auth_providers.dart';
import '../../providers/theme_mode_provider.dart';
import '../../vpn/bypass_china.dart';
import '../../vpn/vpn_controller.dart';
// 反馈外链的打开方式复用 M7 的实现：它做了 scheme 白名单校验
// （只放行 http/https），避免后台配置项变成任意 scheme 的跳板。
import '../feedback/feedback_launcher.dart';
import '../plans/plans_routes.dart';
import '../shell/app_shell.dart';
import '../update/update_dialog.dart';
import '../update/update_providers.dart';
import '../update/version_reporter.dart';
import 'hidden_api_base_sheet.dart';
import 'logout_service.dart';
import 'settings_providers.dart';
import 'settings_routes.dart';
import 'settings_tiles.dart';
import 'site_config.dart';
import 'theme_mode_sheet.dart';
import 'version_tap_trigger.dart';
import '../../core/ui/app_toast.dart';

/// 设置页（T8.1）：通用 / 账号 / 关于 三个分组 + 红色退出登录。
///
/// 分组与条目顺序严格按 tasks/08_settings.md T8.1 的布局表。
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    final site = ref.watch(siteConfigProvider).value ?? SiteConfig.empty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        actionsPadding: const EdgeInsets.only(right: Sp.sm),
        actions: [
          IconButton(
            tooltip: '退出登录',
            icon: const Icon(Icons.logout),
            onPressed: () => _confirmAndLogout(context, ref),
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          Sp.base,
          0,
          Sp.base,
          // 底栏浮在内容上（AppShell extendBody），底部留出底栏视觉高度 + 系统安全区，
          // 避免退出登录按钮被悬浮底栏挡住。
          appBottomBarHeight + MediaQuery.of(context).padding.bottom + Sp.base,
        ),
        children: [
          const SettingsSectionHeader('通用'),
          SettingsGroup(children: const [_ThemeModeTile(), _BypassChinaTile()]),
          const SettingsSectionHeader('账号'),
          SettingsGroup(
            children: [
              _MyInfoTile(email: user?.email ?? ''),
              const _PlansTile(),
            ],
          ),
          const SettingsSectionHeader('关于'),
          SettingsGroup(
            children: [
              if (site.feedbackLink.isNotEmpty)
                SettingsTile(
                  title: '意见反馈',
                  icon: Icons.feedback_outlined,
                  onTap: () => _openFeedback(context, site.feedbackLink),
                ),
              const _DisclaimerTile(),
              const _CheckUpdateTile(),
              const _VersionTile(),
            ],
          ),
        ],
      ),
    );
  }

  /// 反馈外链：外部浏览器/对应 App 打开（T7.4），打不开只提示不崩。
  Future<void> _openFeedback(BuildContext context, String link) async {
    final ok = await openFeedbackLink(link);
    if (!ok && context.mounted) {
      showAppToast(context, '无法打开链接');
    }
  }
}

/// 主题模式：右侧显示当前值，点击弹层选择（T8.3）。
class _ThemeModeTile extends ConsumerWidget {
  const _ThemeModeTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;
    return SettingsTile(
      title: '主题模式',
      icon: Icons.brightness_6_outlined,
      trailing: Text(
        themeModeLabel(mode),
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
      onTap: () => showThemeModeSheet(context),
    );
  }
}

/// 绕开国内：国内域名/IP 直连、国外走代理（规则模式）。
class _BypassChinaTile extends ConsumerWidget {
  const _BypassChinaTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bypass = ref.watch(bypassChinaProvider);
    return SettingsTile(
      title: '绕开国内',
      subtitle: '国内应用直连，国外走代理',
      icon: Icons.public_off_outlined,
      trailing: Switch(
        value: bypass,
        onChanged: (_) => _toggle(ref, bypass),
      ),
      onTap: () => _toggle(ref, bypass),
      showChevron: false,
    );
  }

  /// 修改绕开国内：已连接时自动断开重连，让新路由规则生效。
  Future<void> _toggle(WidgetRef ref, bool current) async {
    await ref.read(bypassChinaProvider.notifier).set(!current);
    await ref.read(vpnProvider.notifier).reconnectActive();
  }
}

/// 我的信息：邮箱 / 订阅 token（可复制）。
class _MyInfoTile extends StatelessWidget {
  const _MyInfoTile({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: '我的信息',
      subtitle: email.isEmpty ? '未登录' : email,
      icon: Icons.person_outline,
      onTap: () => context.push(SettingsRoutes.myInfo),
    );
  }
}

/// 套餐：从底部导航收进「我的」页面（产品调整），跳 /plans。
class _PlansTile extends StatelessWidget {
  const _PlansTile();

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: '套餐',
      icon: Icons.storefront_outlined,
      onTap: () => context.push(PlansRoutes.plans),
    );
  }
}

/// 免责声明：网络加速工具的合规声明。
class _DisclaimerTile extends StatelessWidget {
  const _DisclaimerTile();

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: '免责声明',
      icon: Icons.gavel_outlined,
      onTap: () => showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('免责声明'),
          content: const SingleChildScrollView(
            child: Text(
              '本工具仅供学习、研究与合法用途。\n\n'
              '使用前请确认您的行为符合当地法律法规。\n\n'
              '严禁利用本工具从事任何违法违规活动，由此产生的一切法律后果由使用者自行承担。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 版本号（T8.5）+ 隐藏地址入口（T9.4：连点 5 次）。
class _VersionTile extends ConsumerWidget {
  const _VersionTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(localVersionProvider);
    final cs = Theme.of(context).colorScheme;
    final label = version.value?.label ?? '—';

    return VersionTapTrigger(
      onTriggered: () => _openHiddenEntry(context, ref),
      child: SettingsTile(
        title: '版本号',
        icon: Icons.info_outline,
        // 展示值放右侧，与「我的信息」等跳转项区分开（这一项本身不跳转）。
        trailing: Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        showChevron: false,
      ),
    );
  }

  Future<void> _openHiddenEntry(BuildContext context, WidgetRef ref) async {
    final changed = await showHiddenApiBaseDialog(context);
    if (!changed || !context.mounted) return;
    showAppToast(context, '地址已保存，重启后生效');
  }
}

/// 检查更新：手动触发（绕 24h 节流），有新版弹更新框，无新版提示已最新。
class _CheckUpdateTile extends ConsumerStatefulWidget {
  const _CheckUpdateTile();

  @override
  ConsumerState<_CheckUpdateTile> createState() => _CheckUpdateTileState();
}

class _CheckUpdateTileState extends ConsumerState<_CheckUpdateTile> {
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      title: '检查更新',
      icon: Icons.system_update_alt_outlined,
      trailing: _checking
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: _checking ? null : _check,
    );
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    VersionDecision? decision;
    try {
      decision = await checkUpdateManually(ref);
    } catch (_) {
      decision = null;
    }
    if (!mounted) return;
    setState(() => _checking = false);

    if (decision == null) {
      showAppToast(context, '已是最新版本');
      return;
    }
    // 有更新：直接弹更新框（force / optional 都由弹窗自己处理形态）。
    await showUpdateDialog(
      context,
      decision,
      installer: ref.read(apkInstallerProvider),
    );
  }
}

/// 右上角退出登录：二次确认 → 断 VPN 清 token → 跳登录。
Future<void> _confirmAndLogout(BuildContext context, WidgetRef ref) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('退出登录'),
      content: const Text('退出后将断开 VPN 连接，需要重新登录才能继续使用。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('退出'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  // 顺序由 LogoutService 保证（断 VPN → 清 token → 清用户缓存 → 清订阅缓存）。
  await ref.read(logoutServiceProvider).run();
  // token 清空后路由守卫也会跳，但显式 go 一次避免依赖 provider 重建时序。
  if (context.mounted) context.go(SettingsRoutes.login);
}
