import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/prefs.dart';

/// 「绕开国内」开关：开启后国内域名/IP 直连、国外走代理（规则模式）。
///
/// 默认开启：全局代理会拖慢国内应用，绕开国内更符合直觉。
class BypassChinaNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  /// 启动时从 prefs 回填一次（main 里 unawaited）。
  Future<void> restore() async {
    try {
      state = await Prefs.getBypassChina();
    } catch (_) {
      state = true;
    }
  }

  Future<void> set(bool value) async {
    if (state == value) return;
    state = value;
    try {
      await Prefs.setBypassChina(value);
    } catch (_) {
      // 写失败只影响下次冷启动默认值。
    }
  }
}

final bypassChinaProvider =
    NotifierProvider<BypassChinaNotifier, bool>(BypassChinaNotifier.new);
