import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../../providers/theme_mode_provider.dart';

/// 主题模式选择弹层（T8.3）：跟随系统 / 亮色 / 暗色。
///
/// 选中即生效（MaterialApp 监听 themeModeProvider）并持久化，
/// 关闭弹层不丢选择 —— 与「确认后才保存」的表单不同。
Future<void> showThemeModeSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // 弹层用 28dp 顶部圆角（design-tokens §6.6）。
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _ThemeModeSheet(),
  );
}

class _ThemeModeSheet extends ConsumerWidget {
  const _ThemeModeSheet();

  static const _options = <(ThemeMode, String, IconData, String)>[
    (ThemeMode.system, '跟随系统', Icons.brightness_auto_outlined, '按系统深色设置自动切换'),
    (ThemeMode.light, '亮色', Icons.light_mode_outlined, '始终使用亮色界面'),
    (ThemeMode.dark, '暗色', Icons.dark_mode_outlined, '始终使用暗色界面'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Sp.base, 0, Sp.base, Sp.sm),
              child: Text(
                '主题模式',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            RadioGroup<ThemeMode>(
              groupValue: current,
              onChanged: (mode) {
                if (mode == null) return;
                ref.read(themeModeProvider.notifier).setMode(mode);
                Navigator.of(context).pop();
              },
              child: Column(
                children: [
                  for (final (mode, label, icon, hint) in _options)
                    RadioListTile<ThemeMode>(
                      value: mode,
                      title: Text(label),
                      subtitle: Text(
                        hint,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      secondary: Icon(icon, color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const SizedBox(height: Sp.base),
          ],
        ),
      ),
    );
  }
}

/// 主题模式的展示文案（设置页右侧当前值）。
String themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.system:
      return '跟随系统';
    case ThemeMode.light:
      return '亮色';
    case ThemeMode.dark:
      return '暗色';
  }
}
