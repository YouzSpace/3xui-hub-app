import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/core/theme/app_theme.dart';
import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/data/models/site_content.dart';
import 'package:controlhub_app/data/models/user_profile.dart';
import 'package:controlhub_app/data/repositories/content_repository.dart';
import 'package:controlhub_app/data/repositories/subscription_repository.dart';
import 'package:controlhub_app/features/announcements/site_content_providers.dart';
import 'package:controlhub_app/features/home/home_page.dart';
import 'package:controlhub_app/features/home/home_providers.dart';
import 'package:controlhub_app/features/nodes/nodes_provider.dart';
import 'package:controlhub_app/features/update/version_reporter.dart';
import 'package:controlhub_app/features/update/update_providers.dart';
import 'package:controlhub_app/providers/auth_providers.dart';
import 'package:controlhub_app/vpn/vpn_controller.dart';
import 'package:controlhub_app/vpn/vpn_engine.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';
import 'package:controlhub_app/widgets/connect_button.dart';
import 'package:controlhub_app/widgets/traffic_card.dart';

const int _gb = 1024 * 1024 * 1024;

// ---------------------------------------------------------------- fakes

class _FakeSubscriptionRepository implements SubscriptionRepository {
  List<Node> nodes = const [];
  int fetchCalls = 0;

  @override
  Future<String> fetchRaw(String token) async => 'raw';

  @override
  Future<List<Node>> fetchNodes(String token) async {
    fetchCalls++;
    return nodes;
  }
}

class _FakeContentRepository implements ContentRepository {
  String siteTitle = '柚子云';
  String announcement = '';

  @override
  Future<SiteContent> fetchSiteContent() async => SiteContent(
        siteTitle: siteTitle,
        announcement: announcement,
        feedbackLink: '',
      );
}

class _FakeEngine implements VpnEngine {
  final _status = StreamController<VpnStatus>.broadcast();
  int startCalls = 0;
  int stopCalls = 0;

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
  Future<void> stop() async => stopCalls++;

  @override
  Stream<VpnStatus> get statusStream => _status.stream;

  @override
  Future<int?> measureDelay(String shareLink) async => 88;

  void emit(VpnStatus s) => _status.add(s);
}

/// 可变用户：refresh 一次就换成 [next]。
class _MutableUserNotifier extends UserNotifier {
  _MutableUserNotifier(this.current);

  UserProfile current;
  UserProfile? next;
  int builds = 0;

  @override
  Future<UserProfile?> build() async {
    builds++;
    final pending = next;
    if (pending != null) {
      next = null;
      current = pending;
    }
    return current;
  }
}

/// 版本检查桩：固定返回给定决策。
class _FakeVersionReporter implements VersionReporter {
  _FakeVersionReporter(this.decision);

  final VersionDecision? decision;
  int calls = 0;

  @override
  Future<VersionDecision?> report({bool force = false}) async {
    calls++;
    return decision;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Node _node(String name) => Node(
      raw: 'vless://uuid@${name.toLowerCase()}.example.com:443#$name',
      name: name,
      protocol: 'vless',
      host: '${name.toLowerCase()}.example.com',
      port: 443,
    );

UserProfile _user({
  String protocol = 'vless',
  int planId = 2,
  bool includeLocal = true,
  int used = 0,
  int limit = 0,
  DateTime? expiredAt,
}) =>
    UserProfile(
      id: 1,
      email: 'a@b.com',
      token: 'sub-token',
      protocol: protocol,
      planId: planId,
      planType: 'period',
      planName: '月付',
      planIncludeLocal: includeLocal,
      planMonths: 1,
      planPrice: 19.9,
      planResetPrice: 5,
      trafficLimit: 0,
      trafficUsed: 0,
      monthlyTrafficUsed: used,
      monthlyTrafficLimit: limit,
      nextTrafficResetAt: DateTime.now().add(const Duration(days: 30)),
      expiredAt: expiredAt ?? DateTime.now().add(const Duration(days: 30)),
      enabled: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeSubscriptionRepository subRepo;
  late _FakeContentRepository contentRepo;
  late _FakeEngine engine;
  late _MutableUserNotifier userNotifier;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    subRepo = _FakeSubscriptionRepository()..nodes = [_node('HK'), _node('JP')];
    contentRepo = _FakeContentRepository();
    engine = _FakeEngine();
    userNotifier = _MutableUserNotifier(_user());
  });

  Widget app({VersionDecision? update}) => ProviderScope(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(subRepo),
          contentRepositoryProvider.overrideWithValue(contentRepo),
          vpnEngineProvider.overrideWithValue(engine),
          userProvider.overrideWith(() => userNotifier),
          versionReporterProvider.overrideWith(
            (ref) => _FakeVersionReporter(update),
          ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomePage()),
      );

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(HomePage)));

  group('T5.1 页面结构', () {
    testWidgets('AppBar 显示站点名；无公告时不亮红点', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('柚子云'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
      expect(find.byType(ConnectButton), findsOneWidget);
      expect(find.byType(TrafficCard), findsOneWidget);
    });

    testWidgets('optional 更新：出现一行提示条', (tester) async {
      await tester.pumpWidget(app(
        update: const VersionDecision(
          action: 'optional',
          latestName: '1.2.0',
          downloadUrl: 'https://example.com/a.apk',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 1.2.0，点击查看'), findsOneWidget);
    });

    testWidgets('没有更新时不出现提示条', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.textContaining('发现新版本'), findsNothing);
    });
  });

  group('T5.4 公告', () {
    testWidgets('有公告：顶部条 + 红点；关闭后本次会话不再显示', (tester) async {
      contentRepo.announcement = '今晚 23:00 维护，预计 30 分钟';
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.textContaining('今晚 23:00 维护'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);

      await tester.tap(find.byTooltip('关闭公告'));
      await tester.pumpAndSettle();

      expect(find.textContaining('今晚 23:00 维护'), findsNothing);
      expect(
        containerOf(tester).read(noticeDismissedProvider),
        isTrue,
        reason: '关闭状态只存内存，供本次会话复用',
      );
    });

    testWidgets('点击公告条 → AlertDialog 全文', (tester) async {
      contentRepo.announcement = '第一行\n第二行\n第三行';
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.campaign_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('公告'), findsOneWidget);
      // 弹窗里是完整正文（列表条只显示前两行，但 Text.data 仍是全文，
      // 所以这里限定在 AlertDialog 内部找）。
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('第一行'),
        ),
        findsOneWidget,
        reason: '详情弹窗展示全文',
      );
    });

    testWidgets('无公告：不显示公告条', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.campaign_outlined), findsNothing);
    });
  });

  group('T5.5 下拉刷新', () {
    testWidgets('同时刷新 /api/me 与订阅，且订阅只拉一次', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(userNotifier.builds, 1);
      expect(subRepo.fetchCalls, 1);

      // 后端数据变化：流量用掉一半、节点换成一个新的。
      userNotifier.next = _user(used: 5 * _gb, limit: 10 * _gb);
      subRepo.nodes = [_node('HK'), _node('JP'), _node('US')];

      await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
      await tester.pumpAndSettle();

      expect(userNotifier.builds, 2, reason: '下拉要重拉 /api/me');
      expect(find.text('5.0 GB / 10.0 GB'), findsOneWidget);
      expect(
        subRepo.fetchCalls,
        2,
        reason: 'userProvider 变化会自动重拉订阅，不能再手工 refresh 一次',
      );
      expect(find.text('当前节点 · HK'), findsOneWidget);
    });
  });

  group('T5.2 连接按钮与状态联动', () {
    testWidgets('点击按钮 → 用当前选中节点连接', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(ConnectButton));
      await tester.pump();
      await tester.pump();

      expect(engine.startCalls, 1, reason: '已连接节点时才会真正启动引擎');
    });

    testWidgets('套餐到期：按钮禁用，点击弹 SnackBar 说明原因', (tester) async {
      userNotifier.current = _user(
        expiredAt: DateTime.now().subtract(const Duration(days: 1)),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('暂不可连接'), findsOneWidget);

      await tester.tap(find.byType(ConnectButton));
      await tester.pump();

      expect(find.text('套餐已到期，请先续费'), findsOneWidget);
      expect(engine.startCalls, 0);
    });

    testWidgets('订阅刷新后当前连接节点不存在 → 自动断开 + 提示', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      final container = containerOf(tester);
      await container.read(vpnProvider.notifier).connect(_node('HK'));
      engine.emit(VpnStatus.connected);
      // 已连接态有常驻呼吸光晕 + 每秒 ticker，不能 pumpAndSettle。
      await tester.pump();
      await tester.pump();
      expect(container.read(vpnProvider).status, VpnStatus.connected);

      // 后端删掉了 HK（只剩 JP）。
      subRepo.nodes = [_node('JP')];
      await container.read(nodesProvider.notifier).refresh();
      await tester.pumpAndSettle();

      await tester.pump();
      expect(container.read(vpnProvider).status, VpnStatus.idle);
      expect(engine.stopCalls, greaterThan(0));
      expect(find.text('节点已失效，请重新选择'), findsOneWidget);
      expect(container.read(homeNoticeProvider), isNull, reason: '提示读后即清');
    });

    testWidgets('/api/me 的 protocol 变化 → 清节点缓存 + 重拉订阅并提示', (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      final container = containerOf(tester);
      expect(subRepo.fetchCalls, 1);
      expect(container.read(selectedNodeProvider)?.name, 'HK');

      // 协议切换 vless → trojan，且订阅内容随之变化。
      userNotifier.next = _user(protocol: 'trojan');
      subRepo.nodes = [_node('US')];
      await container.read(userProvider.notifier).refresh();
      await tester.pumpAndSettle();

      expect(find.text('节点协议已更新，正在重新获取'), findsOneWidget);
      // 只重拉一次（不是 refresh + 自动重拉两次）。
      expect(subRepo.fetchCalls, 2);
      expect(container.read(selectedNodeProvider)?.name, 'US');
      expect(await PrefsProbe.selectedNode(), isNot('vless://uuid@hk.example.com:443#HK'));
    });
  });

  group('T5.3 流量卡片接入', () {
    testWidgets('未订阅：卡片显示去选购', (tester) async {
      userNotifier.current = _user(planId: 0);
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('去选购'), findsOneWidget);
    });
  });
}

/// 只读 prefs 的小工具（避免测试直接依赖 Prefs 的方法名）。
abstract class PrefsProbe {
  static Future<String?> selectedNode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_node');
  }
}
