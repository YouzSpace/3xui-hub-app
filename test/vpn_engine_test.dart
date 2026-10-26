import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vless/flutter_vless.dart';
import 'package:flutter_vless_platform_interface/flutter_vless_platform_interface.dart';

import 'package:controlhub_app/vpn/vpn_engine.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';

/// VlessPlatform 桩：记录调用 + 按脚本回放状态事件（单测无平台通道）。
///
/// VlessPlatform 是插件官方公开的平台接口，FlutterVless 全部方法都
/// 转发到 VlessPlatform.instance，替换它是插件文档推荐的 mock 方式。
class _FakeVlessPlatform extends VlessPlatform {
  int initializeCalls = 0;
  int requestPermissionCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  int serverDelayCalls = 0;

  bool permissionGranted = true;
  Object? startError;
  int? delayResult = 120;

  void Function(VlessStatus status)? onStatusChanged;

  @override
  Future<void> initializeVless({
    required void Function(VlessStatus status) onStatusChanged,
    required String notificationIconResourceType,
    required String notificationIconResourceName,
    required String providerBundleIdentifier,
    required String groupIdentifier,
    String? keychainAccessGroup,
  }) async {
    initializeCalls++;
    this.onStatusChanged = onStatusChanged;
  }

  @override
  Future<bool> requestPermission() async {
    requestPermissionCalls++;
    return permissionGranted;
  }

  @override
  Future<void> startVless({
    required String remark,
    required String config,
    required String notificationDisconnectButtonName,
    List<String>? blockedApps,
    List<String>? bypassSubnets,
    bool proxyOnly = false,
    String? geoAssetsDirectory,
    AndroidDnsPolicy androidDnsPolicy = AndroidDnsPolicy.config,
    String? androidDnsProxyOutboundTag,
  }) async {
    startCalls++;
    if (startError != null) throw startError!;
    lastRemark = remark;
    lastConfig = config;
  }

  String? lastRemark;
  String? lastConfig;

  @override
  Future<void> stopVless() async {
    stopCalls++;
  }

  @override
  Future<int> getServerDelay({
    required String config,
    required String url,
    String? geoAssetsDirectory,
  }) async {
    serverDelayCalls++;
    if (delayResult == null) throw const VpnException('probe failed');
    return delayResult!;
  }
}

/// 把合法分享链接转 Xray JSON：不依赖原生，FlutterVless.parse 是纯 Dart。
const _validLink =
    'vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443'
    '?encryption=none&security=tls&type=tcp#TestNode';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVlessPlatform fake;
  late FlutterVlessEngine engine;

  setUp(() {
    fake = _FakeVlessPlatform();
    VlessPlatform.instance = fake;
    engine = FlutterVlessEngine();
  });

  test('initialize 幂等：重复调用只初始化一次', () async {
    await engine.initialize();
    await engine.initialize();
    await engine.initialize();
    expect(fake.initializeCalls, 1);
  });

  test('start 前自动 requestPermission，授权通过正常启动', () async {
    await engine.initialize();
    final config = await engine.buildConfig(_validLink);
    await engine.start(remark: 'TestNode', config: config);

    expect(fake.requestPermissionCalls, 1);
    expect(fake.startCalls, 1);
    expect(fake.lastRemark, 'TestNode');
    expect(fake.lastConfig, isA<String>());
  });

  test('start 时权限被拒 → 抛 VpnException（中文文案）且不启动隧道', () async {
    fake.permissionGranted = false;
    await expectLater(
      engine.start(remark: 'x', config: '{"inbounds":[],"outbounds":[]}'),
      throwsA(isA<VpnException>()
          .having((e) => e.message, 'message', '需要 VPN 权限才能连接')),
    );
    expect(fake.startCalls, 0);
  });

  test('statusStream：插件连接状态回调转成本地 VpnStatus 流', () async {
    await engine.initialize();
    final events = <VpnStatus>[];
    final sub = engine.statusStream.listen(events.add);
    await Future<void>.delayed(Duration.zero);

    fake.onStatusChanged!(VlessStatus(state: 'CONNECTING'));
    fake.onStatusChanged!(VlessStatus(state: 'CONNECTED'));
    fake.onStatusChanged!(VlessStatus(state: 'DISCONNECTED'));
    fake.onStatusChanged!(VlessStatus(state: 'WEIRD-STATE')); // unknown：不发事件
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      VpnStatus.connecting,
      VpnStatus.connected,
      VpnStatus.idle,
    ]);
    await sub.cancel();
  });

  test('buildConfig：合法分享链接 → Xray JSON；非法链接 → VpnException', () async {
    final config = await engine.buildConfig(_validLink);
    expect(config, contains('"outbounds"'));
    expect(config, contains('"inbounds"'));

    await expectLater(
      engine.buildConfig('not-a-valid-link'),
      throwsA(isA<VpnException>()),
    );
  });

  test('measureDelay：正常返回毫秒数', () async {
    final delay = await engine.measureDelay(_validLink);
    expect(delay, 120);
    expect(fake.serverDelayCalls, 1);
  });

  test('measureDelay：探测异常 / 链接非法 → null 不抛出', () async {
    fake.delayResult = null;
    expect(await engine.measureDelay(_validLink), isNull);
    expect(await engine.measureDelay('garbage-link'), isNull);
  });
}
