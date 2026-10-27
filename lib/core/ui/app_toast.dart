import 'package:flutter/material.dart';

import '../theme/spacing.dart';

/// 统一 Toast（美化版 SnackBar，T3.5 之后统一收口）。
///
/// 样式：浅色浮层卡片（`surfaceContainer` 背景 + `onSurface` 文字 +
/// `outlineVariant` 细边框）、24 圆角胶囊、浮动 + 左右留边距、文字居中、
/// 轻微阴影。浅色主题下是白色卡片，暗色主题自动跟随。替代默认深色通栏 SnackBar。
void showAppToast(BuildContext context, String message) {
  final cs = Theme.of(context).colorScheme;
  _show(ScaffoldMessenger.of(context), cs, message);
}

/// 脱离 context 的场景（页面可能已被返回键关掉，但提示仍要发生，
/// 如支付到账结果）：显式传提前捕获的 [messenger]。
void showAppToastWith(ScaffoldMessengerState messenger, String message) {
  _show(messenger, Theme.of(messenger.context).colorScheme, message);
}

void _show(ScaffoldMessengerState messenger, ColorScheme cs, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: cs.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: cs.outlineVariant),
        ),
        duration: const Duration(milliseconds: 2000),
        margin: const EdgeInsets.fromLTRB(Sp.lg, 0, Sp.lg, Sp.sm),
        elevation: 6,
      ),
    );
}
