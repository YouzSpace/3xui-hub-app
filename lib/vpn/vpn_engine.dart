import 'dart:async';

import 'package:flutter_vless/flutter_vless.dart';

import 'vpn_state.dart';

/// VPN 引擎层异常：message 直接可展示给用户（同 ApiException 约定）。
class VpnException implements Exception {
  final String message;

  const VpnException(this.message);

  @override
  String toString() => message;
}

/// VPN 引擎抽象（system-design §4.2）。
///
/// 本抽象是 flutter_vless 在整个 App 里的**唯一封装层**：
/// 上层（controller / UI）只 import 本文件，不直接 import flutter_vless。
abstract class VpnEngine {
  /// 插件初始化（App 启动调一次，幂等，重复调用不报错）。
  Future<void> initialize();

  /// 请求系统 VPN 授权（Android 首次连接弹授权框）。
  Future<bool> requestPermission();

  /// 把分享链接转成 Xray JSON 配置（解析失败抛 [VpnException]）。
  Future<String> buildConfig(String shareLink);

  /// 启动隧道。config 为 Xray JSON 字符串；[remark] 是节点名，
  /// 原生前台服务通知用它展示「已连接 · {节点名}」。
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
  });

  /// 停止隧道。
  Future<void> stop();

  /// 连接状态流（由插件状态回调转换而来）。
  Stream<VpnStatus> get statusStream;

  /// 单节点测速（毫秒）；超时/失败/链接非法返回 null。
  Future<int?> measureDelay(String shareLink);
}

/// flutter_vless 1.1.6 的真实适配实现（API 依据包内 doc/api.md）。
class FlutterVlessEngine implements VpnEngine {
  /// iOS/macOS Packet Tunnel 扩展用基础 bundle id；Android 不使用。
  static const String providerBundleIdentifier = 'com.controlhub.controlhub_app';

  /// 测速探测端点（204 无正文，最快返回）。
  static const String _delayProbeUrl =
      'https://www.gstatic.com/generate_204';

  final StreamController<VpnStatus> _statusController =
      StreamController<VpnStatus>.broadcast();

  bool _initialized = false;

  late final FlutterVless _vless = FlutterVless(onStatusChanged: _onStatus);

  /// 插件状态回调 → 本地状态机映射。
  ///
  /// unknown（原生侧未识别状态）不向外发事件，避免污染本地状态机。
  void _onStatus(VlessStatus status) {
    switch (status.connectionState) {
      case VlessConnectionState.connected:
        _statusController.add(VpnStatus.connected);
      case VlessConnectionState.connecting:
        _statusController.add(VpnStatus.connecting);
      case VlessConnectionState.disconnecting:
        _statusController.add(VpnStatus.disconnecting);
      case VlessConnectionState.disconnected:
        _statusController.add(VpnStatus.idle);
      case VlessConnectionState.unknown:
        break;
    }
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    await _vless.initializeVless(
      notificationIconResourceType: 'mipmap',
      notificationIconResourceName: 'ic_launcher',
      providerBundleIdentifier: providerBundleIdentifier,
      groupIdentifier: '',
    );
    _initialized = true;
  }

  @override
  Future<bool> requestPermission() => _vless.requestPermission();

  @override
  Future<String> buildConfig(String shareLink) async {
    try {
      final parsed = FlutterVless.parse(shareLink);
      return parsed.getFullConfiguration();
    } catch (_) {
      throw const VpnException('节点链接无法解析');
    }
  }

  @override
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
  }) async {
    // 插件在已授权时立即返回 true，不会重复弹框。
    final allowed = await _vless.requestPermission();
    if (!allowed) {
      throw const VpnException('需要 VPN 权限才能连接');
    }
    // config 非法时插件抛 ArgumentError，由上层 controller 统一转 error 态。
    await _vless.startVless(
      remark: remark,
      config: config,
      blockedApps: blockedApps,
      proxyOnly: false,
    );
  }

  @override
  Future<void> stop() => _vless.stopVless();

  @override
  Stream<VpnStatus> get statusStream => _statusController.stream;

  @override
  Future<int?> measureDelay(String shareLink) async {
    try {
      final parsed = FlutterVless.parse(shareLink);
      // 插件测速失败时返回平台自定义失败值或抛异常，统一收口为 null。
      final delay = await _vless.getServerDelay(
        config: parsed.getFullConfiguration(),
        url: _delayProbeUrl,
      );
      return delay;
    } catch (_) {
      return null;
    }
  }
}
