import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';
import '../../vpn/blocked_apps.dart';

/// 顶部计数条：「已选 N 个应用不走代理」+ 说明。
class SplitTunnelHeader extends StatelessWidget {
  const SplitTunnelHeader({super.key, required this.selectedCount});

  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainer,
      padding: const EdgeInsets.all(Sp.base),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '已选 $selectedCount 个应用不走代理',
            style: textTheme.titleMedium?.copyWith(color: cs.onSurface),
          ),
          const SizedBox(height: Sp.xs),
          Text(
            '勾选的应用将直接使用本机网络，其余应用走 VPN。已连接时修改需重新连接生效。',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// 搜索框（filled 底、无边框，design-tokens §6.3）。
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.base, Sp.md, Sp.base, Sp.md),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: '搜索应用名称或包名',
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: cs.surfaceContainerHighest,
          border: const OutlineInputBorder(borderSide: BorderSide.none),
          isDense: true,
        ),
      ),
    );
  }
}

/// 单个应用行：包名 + 名称 + 勾选框，整行可点（≥48dp）。
class InstalledAppTile extends StatelessWidget {
  const InstalledAppTile({
    super.key,
    required this.app,
    required this.selected,
    required this.onChanged,
  });

  final InstalledApp app;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => onChanged(!selected),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 72),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Sp.base,
            vertical: Sp.sm,
          ),
          child: Row(
            children: [
              // 图标：InstalledAppsChannel 不返回应用图标（避免大图传输），
              // 用统一的 app 图标占位。
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.android,
                  size: 24,
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      app.appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    const SizedBox(height: Sp.xs),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Sp.sm),
              // 只读展示勾选态，点击由外层 InkWell 统一处理（避免双触发）。
              Checkbox(
                value: selected,
                onChanged: (v) => onChanged(v ?? false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
