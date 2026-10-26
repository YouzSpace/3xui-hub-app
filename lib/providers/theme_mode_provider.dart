import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/prefs.dart';

/// 主题模式（T8.3）：跟随系统 / 亮色 / 暗色，持久化到 prefs 的 `theme_mode`。
///
/// 首帧先按跟随系统渲染，读盘完成后切到用户选择（prefs 读盘在毫秒级，
/// 且默认值本身就是 system，绝大多数用户看不到差异）。
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  /// 用户本会话是否主动改过：改过之后不允许慢读盘的回填覆盖用户操作。
  bool _userChosen = false;
  bool _disposed = false;

  @override
  ThemeMode build() {
    ref.onDispose(() => _disposed = true);
    // 不 await：build 必须同步返回，读盘结果到了再切。
    restore();
    return ThemeMode.system;
  }

  /// 从 prefs 回填（启动一次；也可在测试里显式 await）。
  Future<void> restore() async {
    final saved = await _readSaved();
    if (saved == null || _userChosen || _disposed) return;
    state = saved;
  }

  /// 切换并持久化：MaterialApp 监听本 provider，切换后立即生效。
  Future<void> setMode(ThemeMode mode) async {
    _userChosen = true;
    state = mode;
    try {
      await Prefs.setThemeMode(encodeThemeMode(mode));
    } catch (_) {
      // 写盘失败只影响「重启保持」，本次切换仍然生效。
    }
  }

  Future<ThemeMode?> _readSaved() async {
    try {
      return decodeThemeMode(await Prefs.getThemeMode());
    } catch (_) {
      // prefs 读失败按「没存过」处理：跟随系统。
      return null;
    }
  }
}

/// prefs 值 → ThemeMode；未知/空值 → 跟随系统（老版本升级不会崩）。
ThemeMode decodeThemeMode(String? raw) {
  switch (raw) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

/// ThemeMode → prefs 值（与 [decodeThemeMode] 互逆）。
String encodeThemeMode(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.dark:
      return 'dark';
    case ThemeMode.system:
      return 'system';
  }
}
