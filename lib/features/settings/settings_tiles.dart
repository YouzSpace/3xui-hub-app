import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';

/// 设置页分组标题（titleSmall + onSurfaceVariant，左侧 16dp 对齐）。
class SettingsSectionHeader extends StatelessWidget {
  const SettingsSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Sp.base, Sp.lg, Sp.base, Sp.sm),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: cs.onSurfaceVariant),
      ),
    );
  }
}

/// 设置项（单行 56dp / 双行 72dp，design-tokens §6.5）。
///
/// 整行可点，触控高度由 56dp 起（≥48dp 无障碍要求）；
/// 右侧 [trailing] 可以是文字、开关或箭头，缺省显示箭头（[onTap] 非空时）。
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.danger = false,
    this.semanticLabel,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// 无跳转的开关式条目关掉箭头更干净。
  final bool showChevron;

  /// 危险操作（退出登录）用 error 色标题。
  final bool danger;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final titleColor = danger ? cs.error : cs.onSurface;
    final hasSubtitle = subtitle != null && subtitle!.isNotEmpty;

    final Widget? end =
        trailing ??
        (onTap != null && showChevron
            ? Icon(Icons.chevron_right, size: 24, color: cs.onSurfaceVariant)
            : null);

    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: hasSubtitle ? 72 : 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Sp.base,
              vertical: Sp.md,
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 24, color: cs.onSurfaceVariant),
                  const SizedBox(width: Sp.base),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: titleColor,
                        ),
                      ),
                      if (hasSubtitle) ...[
                        const SizedBox(height: Sp.xs),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (end != null) ...[const SizedBox(width: Sp.sm), end],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 分组容器：把若干 [SettingsTile] 收进一张不透明卡片（圆角 12）。
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(const Divider(height: 1, indent: Sp.base, endIndent: Sp.base));
      }
      rows.add(children[i]);
    }
    return Card(
      color: Theme.of(context).brightness == Brightness.dark
          ? cs.surfaceContainerLow
          : cs.surfaceContainerLowest,
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}
