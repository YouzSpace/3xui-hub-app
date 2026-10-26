import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/spacing.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/user_profile.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_state.dart';
import '../../widgets/connect_button.dart';
import '../nodes/nodes_provider.dart';
import 'home_providers.dart';

/// 连接区（T5.1 ②）：120dp 按钮 + 状态文字（titleMedium）+ 时长/延迟（bodySmall）。
class ConnectArea extends ConsumerWidget {
  const ConnectArea({super.key, required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vpn = ref.watch(vpnProvider);
    final blockedReason = ref.watch(planBlockReasonProvider);
    final selected = ref.watch(selectedNodeProvider);
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurfaceVariant;

    final meta = _metaLine(vpn);

    return Column(
      children: [
        const SizedBox(height: Sp.lg),
        Stack(
          alignment: Alignment.center,
          children: [
            // 世界地图装饰背景（按钮后面，主题色淡染）。
            SvgPicture.asset(
              'assets/decor/world.svg',
              width: 340,
              height: 200,
              colorFilter: ColorFilter.mode(
                cs.primary.withValues(alpha: 0.10),
                BlendMode.srcIn,
              ),
            ),
            ConnectButton(
              status: vpn.status,
              blockedReason: blockedReason,
              blockedIcon: profile.planId == 0
                  ? Icons.shopping_bag_outlined
                  : Icons.power_settings_new,
              onPressed: () => _onTap(context, ref, blockedReason),
            ),
          ],
        ),
        const SizedBox(height: Sp.base),
        Text(_statusLine(vpn, blockedReason), style: text.titleMedium),
        if (meta != null) ...[
          const SizedBox(height: Sp.xs),
          Text(meta, style: text.bodySmall?.copyWith(color: muted)),
        ] else if (selected != null && !vpn.isBusy) ...[
          const SizedBox(height: Sp.xs),
          Text(
            '当前节点 · ${selected.name}',
            style: text.bodySmall?.copyWith(color: muted),
          ),
        ],
        const SizedBox(height: Sp.lg),
      ],
    );
  }

  Future<void> _onTap(
    BuildContext context,
    WidgetRef ref,
    String? blockedReason,
  ) async {
    // 禁用态也响应点击：不说明原因最难受（T5.2）。
    if (blockedReason != null) {
      showHomeSnack(context, blockedReason);
      return;
    }
    await ref.read(connectionToggleProvider)();
    if (!context.mounted) return;
    // 连接失败的错误文案（校验链第 5 条 / 引擎异常）从状态机里取。
    final vpn = ref.read(vpnProvider);
    final error = vpn.errorMessage;
    if (vpn.status == VpnStatus.error && error != null) {
      showHomeSnack(context, error);
    }
  }
}

/// 状态文字（titleMedium）：未连接 / 连接中… / 已连接 · 节点名。
String _statusLine(VpnState vpn, String? blockedReason) {
  if (vpn.status == VpnStatus.error && vpn.errorMessage != null) {
    return vpn.errorMessage!;
  }
  if (blockedReason != null) return '暂不可连接';
  return switch (vpn.status) {
    VpnStatus.preparing || VpnStatus.connecting => '连接中…',
    VpnStatus.disconnecting => '正在断开…',
    VpnStatus.connected => '已连接 · ${vpn.activeNode?.name ?? '未知节点'}',
    _ => '未连接',
  };
}

/// 连接时长 + 延迟（bodySmall）；没有可展示内容时返回 null。
String? _metaLine(VpnState vpn) {
  final latency = vpn.latencyMs;
  if (vpn.status == VpnStatus.connected) {
    final parts = <String>['连接时长 ${formatDuration(vpn.connectedFor)}'];
    if (latency != null) parts.add('延迟 $latency ms');
    return parts.join(' · ');
  }
  if (latency != null) return '延迟 $latency ms';
  return null;
}

/// 首页通用提示（连接失败 / 禁用原因 / 状态联动）。
void showHomeSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
