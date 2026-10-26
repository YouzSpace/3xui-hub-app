import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/vpn/blocked_apps.dart';
import 'package:controlhub_app/vpn/vpn_controller.dart';
import 'package:controlhub_app/vpn/vpn_engine.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';

/// 可编程的 mock 引擎：记录调用、可注入失败、可手动推状态事件。
class _MockEngine implements VpnEngine {
  int initializeCalls = 0;
  int startCalls = 0;
  int stopCalls = 0;
  Object? startError;

  final _controller = StreamController<VpnStatus>.broadcast();
  String? lastRemark;
  String? lastConfig;
  List<String>? lastBlockedApps;

  @override
  Future<void> initialize() async => initializeCalls++;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> buildConfig(String shareLink) async =>
      '{"inbounds":[],"outbounds":[]}';

  @override
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
  }) async {
    startCalls++;
    if (startError != null) throw startError!;
    lastRemark = remark;
    lastConfig = config;
    lastBlockedApps = blockedApps;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Stream<VpnStatus> get statusStream => _controller.stream;

  void emit(VpnStatus s) => _controller.add(s);

  @override
  Future<int?> measureDelay(String shareLink) async => 42;
}

/// 区分「没传」与「显式传 null」的哨兵（3b 用例要显式传 null 过期时间）。
class _Unset {
  const _Unset();
}

const _unset = _Unset();

UserProfile _user({
  bool enabled = true,
  int planId = 2,
  Object? expiredAt = _unset,
  int monthlyUsed = 100,
  int monthlyLimit = 1000,
}) {
  return UserProfile(
    id: 1,
    email: 'a@b.com',
    token: 'sub-token',
    protocol: 'vless',
    planId: planId,
    planType: 'period',
    planName: '月付',
    planIncludeLocal: true,
    planMonths: 1,
    planPrice: 19.9,
    planResetPrice: 5,
    trafficLimit: 0,
    trafficUsed: 0,
    monthlyTrafficUsed: monthlyUsed,
    monthlyTrafficLimit: monthlyLimit,
    nextTrafficResetAt: null,
    expiredAt: expiredAt == _unset
        ? DateTime.now().add(const Duration(days: 30))
        : expiredAt as DateTime?,
    enabled: enabled,
  );
}

Node _node() => Node(
      raw: 'vless://uuid@host:443?security=tls#香港01',
      name: '香港01',
      protocol: 'vless',
      host: 'host',
      port: 443,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late _MockEngine engine;
  late ProviderContainer container;

  setUp(() {
    engine = _MockEngine();
    container = ProviderContainer(overrides: [
      vpnEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
  });

  VpnController ctrl() => container.read(vpnProvider.notifier);
  VpnState state() => container.read(vpnProvider);

  group('connect 前 5 项校验（失败不启动隧道）', () {
    test('1. user == null → error「请先登录后再连接」', () async {
      await ctrl().connect(_node(), user: null);
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '请先登录后再连接');
      expect(engine.startCalls, 0);
    });

    test('1b. enabled == false → error「账号已被禁用」', () async {
      await ctrl().connect(_node(), user: _user(enabled: false));
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '账号已被禁用，请联系管理员');
      expect(engine.startCalls, 0);
    });

    test('2. 无套餐（planId == 0）→ error「还没有可用套餐」', () async {
      await ctrl().connect(_node(), user: _user(planId: 0));
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '还没有可用套餐，请先购买');
      expect(engine.startCalls, 0);
    });

    test('3. 已过期 → error「套餐已到期」', () async {
      await ctrl().connect(
        _node(),
        user: _user(expiredAt: DateTime.now().subtract(const Duration(days: 1))),
      );
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '套餐已到期，请先续费');
      expect(engine.startCalls, 0);
    });

    test('3b. expiredAt == null → error「套餐已到期」', () async {
      await ctrl().connect(_node(), user: _user(expiredAt: null));
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '套餐已到期，请先续费');
      expect(engine.startCalls, 0);
    });

    test('4. 月流量耗尽 → error「本月流量已用完」', () async {
      await ctrl().connect(
        _node(),
        user: _user(monthlyUsed: 1000, monthlyLimit: 1000),
      );
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '本月流量已用完，请等待重置或购买重置包');
      expect(engine.startCalls, 0);
    });

    test('4b. monthlyTrafficLimit == 0 视为不限，校验通过', () async {
      await ctrl().connect(
        _node(),
        user: _user(monthlyUsed: 999999, monthlyLimit: 0),
      );
      expect(engine.startCalls, 1);
      expect(state().status, VpnStatus.connecting);
    });

    test('5. 无节点 → error「请先选择一个节点」', () async {
      await ctrl().connect(null, user: _user());
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '请先选择一个节点');
      expect(engine.startCalls, 0);
    });

    test('全部通过 → 启动隧道并进入 connecting，节点名传给 remark', () async {
      await ctrl().connect(_node(), user: _user());
      expect(engine.startCalls, 1);
      expect(engine.lastRemark, '香港01');
      expect(state().status, VpnStatus.connecting);
      expect(state().activeNode?.name, '香港01');
      expect(state().errorMessage, isNull);
    });
  });

  group('连接流程与状态机', () {
    test('connect：initialize 被调用，start 失败 → error 态', () async {
      engine.startError = ArgumentError('bad config');
      await ctrl().connect(_node(), user: _user());
      expect(engine.initializeCalls, 1);
      expect(engine.startCalls, 1);
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '连接失败，请稍后重试');
    });

    test('VpnException → error 态且文案原样透传', () async {
      engine.startError = const VpnException('需要 VPN 权限才能连接');
      await ctrl().connect(_node(), user: _user());
      expect(state().status, VpnStatus.error);
      expect(state().errorMessage, '需要 VPN 权限才能连接');
    });

    test('原生回调 connecting → connected，connected 后开始计时', () async {
      await ctrl().connect(_node(), user: _user());
      expect(state().status, VpnStatus.connecting);

      engine.emit(VpnStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(state().status, VpnStatus.connected);

      ctrl().tick();
      expect(state().connectedFor, const Duration(seconds: 1));
      ctrl().tick();
      expect(state().connectedFor, const Duration(seconds: 2));
    });

    test('disconnect：disconnecting → idle，隧道 stop 被调用', () async {
      await ctrl().connect(_node(), user: _user());
      engine.emit(VpnStatus.connected);
      await Future<void>.delayed(Duration.zero);
      expect(state().status, VpnStatus.connected);

      await ctrl().disconnect();
      expect(engine.stopCalls, 1);
      expect(state().status, VpnStatus.idle);
      expect(state().activeNode, isNull);
      expect(state().connectedFor, Duration.zero);
    });

    test('原生断开回调 → 自动回 idle', () async {
      await ctrl().connect(_node(), user: _user());
      engine.emit(VpnStatus.connected);
      await Future<void>.delayed(Duration.zero);
      engine.emit(VpnStatus.idle);
      await Future<void>.delayed(Duration.zero);
      expect(state().status, VpnStatus.idle);
    });

    test('busy 态重复 connect 不重复启动隧道', () async {
      final c = ctrl();
      await c.connect(_node(), user: _user());
      expect(state().status, VpnStatus.connecting);
      await c.connect(_node(), user: _user());
      expect(engine.startCalls, 1);
    });

    test('连接时透传分应用代理包名列表', () async {
      await container
          .read(blockedAppsProvider.notifier)
          .setApps(['com.foo.bar', 'com.baz.qux']);
      await ctrl().connect(_node(), user: _user());
      expect(engine.lastBlockedApps, ['com.foo.bar', 'com.baz.qux']);
    });
  });
}
