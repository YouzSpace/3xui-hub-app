import 'package:flutter/material.dart';

import '../../core/theme/spacing.dart';

/// 更新提示条（T5.1 ④）：仅 `action == optional` 时出现，点击进更新弹窗。
class UpdateHintBar extends StatelessWidget {
  const UpdateHintBar({
    super.key,
    required this.versionName,
    required this.onTap,
  });

  final String versionName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: Sp.base, vertical: Sp.md),
          child: Row(
            children: [
              Icon(Icons.system_update_alt, size: 20, color: cs.primary),
              const SizedBox(width: Sp.md),
              Expanded(
                child: Text(
                  '发现新版本 $versionName，点击查看',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.bodyMedium,
                ),
              ),
              Icon(Icons.chevron_right, size: 20, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
