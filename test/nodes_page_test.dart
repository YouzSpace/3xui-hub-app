import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/core/theme/app_theme.dart';
import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/data/repositories/subscription_repository.dart';
import 'package:controlhub_app/features/nodes/node_tile.dart';
import 'package:controlhub_app/features/nodes/nodes_page.dart';
import 'package:controlhub_app/features/nodes/nodes_provider.dart';
import 'package:controlhub_app/providers/auth_providers.dart';
import 'package:controlhub_app/vpn/vpn_controller.dart';
import 'package:controlhub_app/vpn/vpn_engine.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';

class _FakeRepo implements SubscriptionRepository {
  List<Node> nodes = const [];
  Object? error;
  int fetchCalls = 0;

  @override
  Future<String> fetchRaw(String token) async => 'raw';

  @override
  Future<List<Node>> fetchNodes(String token) async {
    fetchCalls++;
    if (error != null) throw error!;
    return nodes;
  }
}

class _FakeEngine implements VpnEngine {
  int startCalls = 0;
  int stopCalls = 0;
  String? lastRemark;
  final _status = StreamController<VpnStatus>.broadcast();

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
  }) async {
    startCalls++;
    lastRemark = remark;
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Stream<VpnStatus> get statusStream => _status.stream;

  @override
  Future<int?> measureDelay(String shareLink) async => 88;

  void emit(VpnStatus s) => _status.add(s);
}

Node _node(String name) => Node(
      raw: 'vless://uuid@hk01.example.com:443#$name',
      name: name,
      protocol: 'vless',
      host: 'hk01.example.com',
      port: 443,
    );

class _FakeUserNotifier extends UserNotifier {
  @override
  Future<UserProfile?> build() async => UserProfile(
        id: 1,
        email: 'a@b.com',
        token: 'sub-token',
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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepo repo;
  late _FakeEngine engine;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _FakeRepo();
    engine = _FakeEngine();
  });

  Widget app() => ProviderScope(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repo),
          vpnEngineProvider.overrideWithValue(engine),
          userProvider.overrideWith(_FakeUserNotifier.new),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const NodesPage(),
        ),
      );

  testWidgets('加载完成：显示节点名（emoji 已过滤）与协议地址', (tester) async {
    repo.nodes = [_node('🇭🇰 香港 01'), _node('JP-02')];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('节点'), findsOneWidget);
    expect(find.text('香港 01'), findsOneWidget);
    expect(find.text('JP-02'), findsOneWidget);
    expect(find.text('VLESS · hk01.example.com:443'), findsNWidgets(2));
    // 未测速显示 —。
    expect(find.text('—'), findsNWidgets(2));
    expect(find.byType(NodeTile), findsNWidgets(2));
  });

  testWidgets('空订阅：EmptyView + 「重新获取」按钮', (tester) async {
    repo.nodes = const [];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('当前没有可用节点'), findsOneWidget);
    expect(find.text('重新获取'), findsOneWidget);

    repo.nodes = [_node('HK')];
    await tester.tap(find.text('重新获取'));
    await tester.pumpAndSettle();
    expect(find.byType(NodeTile), findsOneWidget);
    expect(repo.fetchCalls, 2);
  });

  testWidgets('错误状态：展示 ApiException.message + 重试', (tester) async {
    repo.error = const ApiException(403, '流量已用完');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    expect(find.text('流量已用完'), findsOneWidget);

    repo.error = null;
    repo.nodes = [_node('HK')];
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.byType(NodeTile), findsOneWidget);
  });

  testWidgets('点击节点 → 选中态持久化（未连接不弹确认）', (tester) async {
    repo.nodes = [_node('HK'), _node('JP')];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.tap(find.text('JP'));
    await tester.pumpAndSettle();

    // 未连接：不弹「切换节点会断开重连」。
    expect(find.text('切换节点会断开重连，继续？'), findsNothing);
    expect(engine.startCalls, 0);
  });

  testWidgets('已连接时点击别的节点 → 确认后断开重连', (tester) async {
    repo.nodes = [_node('HK'), _node('JP')];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    // 用控制器连上 HK，并让引擎回调 connected。
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NodesPage)),
    );
    await container.read(vpnProvider.notifier).connect(repo.nodes[0]);
    engine.emit(VpnStatus.connected);
    await tester.pumpAndSettle();

    await tester.tap(find.text('JP'));
    await tester.pumpAndSettle();
    expect(find.text('切换节点会断开重连，继续？'), findsOneWidget);

    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();

    expect(engine.stopCalls, 1);
    expect(engine.startCalls, 2); // 首次连接 + 切换后的重连
    expect(engine.lastRemark, 'JP');
  });

  testWidgets('长按节点 → 只测该节点并提示延迟', (tester) async {
    repo.nodes = [_node('HK'), _node('JP')];
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('HK'));
    await tester.pumpAndSettle();

    expect(find.text('88 ms'), findsOneWidget);
    expect(find.text('—'), findsOneWidget); // JP 仍未测速
    expect(find.text('延迟 88 ms'), findsOneWidget);
  });
}
