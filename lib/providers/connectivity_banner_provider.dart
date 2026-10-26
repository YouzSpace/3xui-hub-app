import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/api_config.dart';

/// 连通性横幅状态（T9.3）：hidden 时完全不渲染，不占布局空间。
enum ConnectivityState { hidden, checking, visible }

/// 启动后异步 ping 一次；失败显示横幅，成功/重试成功自动收起。
///
/// ping 挂在 provider 里跑，不阻塞渲染；M2 登录页 / M5 首页在 build 里
/// `ref.watch` 横幅 provider，顶部叠一层 ConnectivityBanner 即可接入。
final connectivityBannerProvider =
    StateNotifierProvider<ConnectivityBannerController, ConnectivityState>(
        (ref) {
  return ConnectivityBannerController();
});

class ConnectivityBannerController extends StateNotifier<ConnectivityState> {
  ConnectivityBannerController() : super(ConnectivityState.hidden);

  /// app 起来后调一次：异步 ping，不等待结果。
  void checkOnStartup() {
    _ping();
  }

  /// 用户点 [重试]：横幅先进入 checking，结果出来再收起或保持。
  void retry() {
    _ping();
  }

  Future<void> _ping() async {
    if (state == ConnectivityState.checking) return;
    // 首次 ping 期间不闪横幅；只有确认失败才显示。
    state = ConnectivityState.checking;
    try {
      final ok = await ApiConfig.validate(ApiConfig.base);
      // controller 可能已 dispose，先判 mounted。
      if (!mounted) return;
      state = ok ? ConnectivityState.hidden : ConnectivityState.visible;
    } catch (_) {
      if (!mounted) return;
      // validate 内部吞异常，这里兜底：失败就亮横幅。
      state = ConnectivityState.visible;
    }
  }
}
