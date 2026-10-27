import 'dart:async';
import 'dart:convert';

import 'package:flutter_vless/flutter_vless.dart';

import 'tcp_probe.dart';
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
  ///
  /// [bypassChina] 为 true 时注入「国内直连、国外代理」的 routing 规则。
  Future<String> buildConfig(String shareLink, {bool bypassChina = false});

  /// 启动隧道。config 为 Xray JSON 字符串；[remark] 是节点名，
  /// 原生前台服务通知用它展示「已连接 · {节点名}」。
  Future<void> start({
    required String remark,
    required String config,
  });

  /// 停止隧道。
  Future<void> stop();

  /// 连接状态流（由插件状态回调转换而来）。
  Stream<VpnStatus> get statusStream;

  /// 单节点测速（毫秒）；超时/失败/链接非法返回 null。
  Future<int?> measureDelay(String shareLink);

  /// 测当前已连接隧道的延迟（毫秒）；未连接/失败返回 null。
  ///
  /// 与 [measureDelay]（独立起一个 xray 进程测任意节点）不同，
  /// 这个方法复用正在跑的 VPN 进程，不启动新进程、不与连接冲突。
  Future<int?> measureConnectedDelay();
}

/// TCP 握手测速函数签名：返回握手耗时毫秒，失败返回 -1。
typedef TcpProbe = Future<int> Function(String host, int port);

/// flutter_vless 1.1.6 的真实适配实现（API 依据包内 doc/api.md）。
class FlutterVlessEngine implements VpnEngine {
  /// iOS/macOS Packet Tunnel 扩展用基础 bundle id；Android 不使用。
  static const String providerBundleIdentifier = 'com.controlhub.controlhub_app';

  /// 测速探测端点（204 无正文，最快返回）。
  static const String _delayProbeUrl =
      'https://www.gstatic.com/generate_204';

  /// 备用测速端点：主端点（gstatic）失败时换它重试一次（对齐 v2rayNG）。
  static const String _delayProbeUrl2 =
      'https://www.google.com/generate_204';

  /// TCP 握手测速（可注入，测试传 fake 避免依赖真实网络）。
  final TcpProbe _tcpProbe;

  FlutterVlessEngine({TcpProbe? tcpProbe})
      : _tcpProbe = tcpProbe ?? tcpConnectTime;

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
  Future<String> buildConfig(String shareLink, {bool bypassChina = false}) async {
    try {
      final parsed = FlutterVless.parse(shareLink);
      final config = parsed.fullConfiguration;
      if (bypassChina) {
        // 国内域名/IP 直连，其余走代理（规则模式）。geoip/geosite 数据由
        // 插件 AAR 内置；outbound tag 与插件生成的一致（proxy/direct）。
        config['routing'] = {
          'domainStrategy': 'AsIs',
          'rules': [
            {
              'type': 'field',
              'domain': ['geosite:cn'],
              'outboundTag': 'direct',
            },
            {
              'type': 'field',
              'ip': ['geoip:cn', 'geoip:private'],
              'outboundTag': 'direct',
            },
          ],
        };
      }
      return jsonEncode(config);
    } catch (_) {
      throw const VpnException('节点链接无法解析');
    }
  }

  @override
  Future<void> start({
    required String remark,
    required String config,
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
      proxyOnly: false,
      notificationDisconnectButtonName: '断开',
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
      final network = _transportNetwork(parsed);
      if (_isUdpTransport(network)) {
        // UDP 传输（quic/kcp）TCP 握手测不了，降级内核真延迟。
        final config = parsed.getFullConfiguration();
        return await _probeServerDelay(config, _delayProbeUrl) ??
            await _probeServerDelay(config, _delayProbeUrl2);
      }
      // TCP 握手测速：直连节点测物理延迟（快、数值低，对齐 v2rayNG tcping）。
      final ms = await _tcpProbe(parsed.address, parsed.port);
      return ms < 0 ? null : ms;
    } catch (_) {
      return null;
    }
  }

  /// 单次内核测速：原生返回负值（如 -1）表示失败，统一归一为 null。
  Future<int?> _probeServerDelay(String config, String url) async {
    try {
      // 测速加超时：引擎/节点卡住时不能拖死测速 worker（否则转圈永不结束）。
      final delay = await _vless
          .getServerDelay(config: config, url: url)
          .timeout(const Duration(seconds: 15));
      return delay < 0 ? null : delay;
    } catch (_) {
      return null;
    }
  }

  /// 从解析结果的 outbound streamSettings 拿实际传输类型（tcp/ws/quic/kcp…）。
  String? _transportNetwork(FlutterVlessURL parsed) {
    try {
      final streamSettings = parsed.outbound1['streamSettings'];
      if (streamSettings is Map) {
        return streamSettings['network']?.toString().toLowerCase();
      }
    } catch (_) {}
    return null;
  }

  /// quic/kcp 是 UDP 传输，TCP 握手测不了，跳过预检直接走内核测。
  bool _isUdpTransport(String? network) =>
      network == 'quic' || network == 'kcp';

  @override
  Future<int?> measureConnectedDelay() async {
    // 主端点失败 → 备用端点重试一次（对齐 v2rayNG 的双 URL 兜底）。
    return await _probeConnectedDelay(_delayProbeUrl) ??
        await _probeConnectedDelay(_delayProbeUrl2);
  }

  Future<int?> _probeConnectedDelay(String url) async {
    try {
      final delay = await _vless
          .getConnectedServerDelay(url: url)
          .timeout(const Duration(seconds: 15));
      // 原生返回负值（如 -1）表示探测失败。
      return delay < 0 ? null : delay;
    } catch (_) {
      return null;
    }
  }
}
