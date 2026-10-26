import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/core/storage/prefs.dart';
import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/data/repositories/subscription_repository.dart';
import 'package:controlhub_app/features/nodes/nodes_provider.dart';
import 'package:controlhub_app/providers/auth_providers.dart';
import 'package:controlhub_app/vpn/vpn_controller.dart';
import 'package:controlhub_app/vpn/vpn_engine.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';

/// 假订阅仓库：按调用次数返回预设结果（可注入异常）。
class _FakeSubscriptionRepository implements SubscriptionRepository {
  List<Node> nodes = const [];
  Object? error;
  int fetchCalls = 0;
  String? lastToken;

  @override
  Future<String> fetchRaw(String token) async => 'raw';

  @override
  Future<List<Node>> fetchNodes(String token) async {
    fetchCalls++;
    lastToken = token;
    if (error != null) throw error!;
    return nodes;
  }
}

/// 假引擎：测速可编程，记录 buildConfig/start 调用。
class _FakeEngine implements VpnEngine {
  final Map<String, int?> latency = {};
  int startCalls = 0;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> buildConfig(String shareLink) async => '{}';

  @override
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
  }) async =>
      startCalls++;

  @override
  Future<void> stop() async {}

  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

  @override
  Future<int?> measureDelay(String shareLink) async => latency[shareLink];
}

Node _node(String name, {String? host}) {
  final h = host ?? '${name.toLowerCase()}.example.com';
  return Node(
    raw: 'vless://uuid@$h:443#$name',
    name: name,
    protocol: 'vless',
    host: h,
    port: 443,
  );
}

UserProfile _user({String token = 'sub-token'}) => UserProfile(
      id: 1,
      email: 'a@b.com',
      token: token,
      protocol: 'vless',
      planId: 2,
      planType: 'period',
      planName: '月付',
      planIncludeLocal: true,
      planMonths: 1,
      planPrice: 19.9,
      planResetPrice: 5,
      trafficLimit: 0,
      trafficUsed: 0,
      monthlyTrafficUsed: 0,
      monthlyTrafficLimit: 0,
      nextTrafficResetAt: null,
      expiredAt: DateTime.now().add(const Duration(days: 30)),
      enabled: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSubscriptionRepository repo;
  late _FakeEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _FakeSubscriptionRepository();
    engine = _FakeEngine();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      subscriptionRepositoryProvider.overrideWithValue(repo),
      vpnEngineProvider.overrideWithValue(engine),
      userProvider.overrideWith(() => _FakeUserNotifier(_user())),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  group('拉订阅与选中态', () {
    test('拉订阅 → 节点列表；默认选中第一个并写入 prefs', () async {
      repo.nodes = [_node('HK'), _node('JP'), _node('US')];
      final container = makeContainer();

      final nodes = await container.read(nodesProvider.future);
      expect(nodes, hasLength(3));
      expect(repo.fetchCalls, 1);
      expect(repo.lastToken, 'sub-token'); // 用的是 data.token，不是 access_token

      final selected = container.read(selectedNodeProvider);
      expect(selected?.name, 'HK');
      expect(await Prefs.getSelectedNode(), selected!.raw);
    });

    test('select 后 prefs 有记录，冷启动仍是那个节点', () async {
      repo.nodes = [_node('HK'), _node('JP')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      await container.read(nodesProvider.notifier).select(repo.nodes[1]);
      expect(await Prefs.getSelectedNode(), repo.nodes[1].raw);

      // 模拟重开 App：新容器 + 同一份 prefs。
      final reopened = makeContainer();
      await reopened.read(nodesProvider.future);
      expect(reopened.read(selectedNodeProvider)?.name, 'JP');
    });

    test('订阅里没有上次选的节点 → 退回第一个', () async {
      SharedPreferences.setMockInitialValues({
        Prefs.keySelectedNode: 'vless://uuid@gone.example.com:443#GONE',
      });
      repo.nodes = [_node('HK'), _node('JP')];
      final container = makeContainer();

      await container.read(nodesProvider.future);
      expect(container.read(selectedNodeProvider)?.name, 'HK');
      expect(
        await Prefs.getSelectedNode(),
        repo.nodes.first.raw,
        reason: '兜底选中也要落盘，保证下次冷启动命中',
      );
    });

    test('空订阅 → 空列表且选中态为空', () async {
      repo.nodes = const [];
      final container = makeContainer();
      expect(await container.read(nodesProvider.future), isEmpty);
      expect(container.read(selectedNodeProvider), isNull);
    });

    test('仓库异常透传（ApiException.message 可展示）', () async {
      repo.error = const ApiException(403, '账号已禁用');
      final container = makeContainer();
      await expectLater(
        container.read(nodesProvider.future),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', '账号已禁用')),
      );
    });

    test('refresh 重新拉订阅，并保留相同链接的测速结果', () async {
      repo.nodes = [_node('HK'), _node('JP')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      engine.latency[repo.nodes.first.raw] = 88;
      await container.read(nodesProvider.notifier).measureAll();
      expect(container.read(nodesProvider).value!.first.latencyMs, 88);

      // 后端重下发了同名节点（raw 相同）→ 旧测速结果保留。
      repo.nodes = [_node('HK'), _node('JP')];
      await container.read(nodesProvider.notifier).refresh();

      expect(repo.fetchCalls, 2);
      expect(container.read(nodesProvider).value!.first.latencyMs, 88);
    });
  });

  group('测速', () {
    test('measureAll 把延迟写进状态（未返回的节点为 null）', () async {
      repo.nodes = [_node('HK'), _node('JP'), _node('US')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      engine.latency[repo.nodes[0].raw] = 45;
      engine.latency[repo.nodes[1].raw] = 180;
      engine.latency[repo.nodes[2].raw] = 320;

      await container.read(nodesProvider.notifier).measureAll();
      final nodes = container.read(nodesProvider).value!;
      expect(nodes.map((n) => n.latencyMs).toList(), [45, 180, 320]);
      // 测速不改变选中态。
      expect(container.read(selectedNodeProvider)?.name, 'HK');
    });

    test('测速失败（null）也写回，不抛异常', () async {
      repo.nodes = [_node('HK')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      await container.read(nodesProvider.notifier).measureAll();
      expect(container.read(nodesProvider).value!.single.latencyMs, isNull);
    });

    test('并发上限 3：5 个节点同时最多 3 个在测', () async {
      repo.nodes = [for (var i = 0; i < 5; i++) _node('N$i')];

      var inFlight = 0;
      var peak = 0;
      // 探针引擎：记录同时进行的测速数量（人为加 5ms 延迟让并发窗口可见）。
      final probeEngine = _ProbeEngine((_) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
        return 100;
      });
      final container = ProviderContainer(overrides: [
        subscriptionRepositoryProvider.overrideWithValue(repo),
        vpnEngineProvider.overrideWithValue(probeEngine),
        userProvider.overrideWith(() => _FakeUserNotifier(_user())),
      ]);
      addTearDown(container.dispose);

      await container.read(nodesProvider.future);
      await container.read(nodesProvider.notifier).measureAll();

      expect(peak, lessThanOrEqualTo(kMeasureConcurrency));
      expect(peak, kMeasureConcurrency, reason: '5 个节点应该跑满 3 并发');
      expect(
        container.read(nodesProvider).value!.every((n) => n.latencyMs == 100),
        isTrue,
      );
    });

    test('measureOne 只测指定节点', () async {
      repo.nodes = [_node('HK'), _node('JP')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      engine.latency[repo.nodes[1].raw] = 66;
      await container.read(nodesProvider.notifier).measureOne(repo.nodes[1]);
      final nodes = container.read(nodesProvider).value!;
      expect(nodes[0].latencyMs, isNull);
      expect(nodes[1].latencyMs, 66);
    });

    test('自动选择：打开后立刻测速并切到最快节点，开关写进 prefs', () async {
      repo.nodes = [_node('HK'), _node('JP'), _node('US')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      // 默认已是开，先显式关掉，再打开以验证「打开」动作触发测速+切最快。
      await container.read(nodesProvider.notifier).setAutoSelectFastest(false);

      engine.latency[repo.nodes[0].raw] = 200;
      engine.latency[repo.nodes[1].raw] = 30;
      engine.latency[repo.nodes[2].raw] = 120;

      await container.read(nodesProvider.notifier).setAutoSelectFastest(true);
      expect(container.read(autoSelectFastestProvider), isTrue);
      expect(container.read(selectedNodeProvider)?.name, 'JP');
      expect(await Prefs.getSelectedNode(), repo.nodes[1].raw);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('auto_select_fastest'), isTrue);
    });

    test('自动选择关闭时测速不改选中节点', () async {
      repo.nodes = [_node('HK'), _node('JP')];
      final container = makeContainer();
      await container.read(nodesProvider.future);

      // 默认已是开，显式关闭后验证测速不切节点。
      await container.read(nodesProvider.notifier).setAutoSelectFastest(false);

      engine.latency[repo.nodes[1].raw] = 10;
      await container.read(nodesProvider.notifier).measureAll();
      expect(container.read(selectedNodeProvider)?.name, 'HK');
    });
  });
}

/// 用户状态桩：直接把 [userProvider] 固定成给定值。
class _FakeUserNotifier extends UserNotifier {
  _FakeUserNotifier(this.profile);

  final UserProfile profile;

  @override
  Future<UserProfile?> build() async => profile;
}

typedef _MeasureFn = Future<int?> Function(String raw);

/// 只替换测速实现的引擎（并发探针用）。
class _ProbeEngine implements VpnEngine {
  _ProbeEngine(this._measure);

  final _MeasureFn _measure;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<String> buildConfig(String shareLink) async => '{}';

  @override
  Future<void> start({
    required String remark,
    required String config,
    List<String>? blockedApps,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Stream<VpnStatus> get statusStream => const Stream.empty();

  @override
  Future<int?> measureDelay(String shareLink) => _measure(shareLink);
}
