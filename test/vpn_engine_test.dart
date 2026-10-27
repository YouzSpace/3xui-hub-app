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

  /// 前 N 次测速调用先失败（模拟主端点不通，验证备用端点重试）。
  int delayFailuresBeforeSuccess = 0;

  /// 记录每次测速用到的 url（验证主/备用端点切换）。
  final List<String> delayUrls = [];

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
    delayUrls.add(url);
    if (delayFailuresBeforeSuccess > 0) {
      delayFailuresBeforeSuccess--;
      throw const VpnException('probe failed');
    }
    if (delayResult == null) throw const VpnException('probe failed');
    return delayResult!;
  }
}

/// 把合法分享链接转 Xray JSON：不依赖原生，FlutterVless.parse 是纯 Dart。
const _validLink =
    'vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443'
    '?encryption=none&security=tls&type=tcp#TestNode';

/// UDP 传输节点：type=quic 让 measureDelay 走内核真延迟降级路径。
const _quicLink =
    'vless://b831381d-6324-4d53-ad4f-8cda48b30811@example.com:443'
    '?encryption=none&type=quic&quicSecurity=none&key=abc#QuicNode';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeVlessPlatform fake;
  late FlutterVlessEngine engine;

  setUp(() {
    fake = _FakeVlessPlatform();
    VlessPlatform.instance = fake;
    // TCP 握手测速注入 fake（返回 100ms）：单测不依赖真实网络。
    engine = FlutterVlessEngine(tcpProbe: (_, _) async => 100);
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

  test('measureDelay：TCP 节点走握手测速，返回握手耗时（不起内核）', () async {
    final delay = await engine.measureDelay(_validLink);
    expect(delay, 100);
    expect(fake.serverDelayCalls, 0, reason: 'TCP 握手测速不起 xray 进程');
  });

  test('measureDelay：握手失败（-1）→ 返回 -1（超时），不起内核', () async {
    final unreachable = FlutterVlessEngine(tcpProbe: (_, _) async => -1);
    expect(await unreachable.measureDelay(_validLink), -1);
    expect(fake.serverDelayCalls, 0);
  });

  test('measureDelay：UDP 节点（quic）降级内核真延迟', () async {
    expect(await engine.measureDelay(_quicLink), 120);
    expect(fake.serverDelayCalls, 1);
  });

  test('measureDelay：UDP 节点真延迟失败换备用端点重试一次', () async {
    fake.delayFailuresBeforeSuccess = 1;
    expect(await engine.measureDelay(_quicLink), 120);
    expect(fake.serverDelayCalls, 2);
    expect(fake.delayUrls[0], contains('gstatic'));
    expect(fake.delayUrls[1], contains('google'));
  });

  test('measureDelay：UDP 节点原生返回负值（-1）→ 归一为 null', () async {
    fake.delayResult = -1;
    expect(await engine.measureDelay(_quicLink), isNull);
  });

  test('measureDelay：链接非法 → null 不抛出', () async {
    expect(await engine.measureDelay('garbage-link'), isNull);
  });
}
