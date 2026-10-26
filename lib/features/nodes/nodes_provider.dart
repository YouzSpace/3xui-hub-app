import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/network/api_exception.dart';
import '../../core/storage/prefs.dart';
import '../../data/models/node.dart';
import '../../data/repositories/subscription_repository.dart';
import '../../providers/auth_providers.dart';
import '../../vpn/vpn_controller.dart';

/// 订阅仓库 Provider：测试时可 override 注入 fake。
final subscriptionRepositoryProvider =
    Provider<SubscriptionRepository>((ref) => SubscriptionRepository());

/// 测速并发上限（T3.4：限 3 并发）。
const int kMeasureConcurrency = 3;

/// 自动选择最快节点的 prefs 键。
///
/// 边界说明：`lib/core/storage/prefs.dart` 属于公共文件（并行期间禁止改），
/// 所以这个键暂时留在本模块；汇总时再收口进 Prefs。
const String _keyAutoSelectFastest = 'auto_select_fastest';

/// 订阅节点（T3.4）：拉订阅 → 解析 → 测速 → 选中。
///
/// 状态只有节点列表；「选中节点」「自动选择」是两个独立 Provider
/// （见 [selectedNodeProvider] / [autoSelectFastestProvider]），
/// 这样 UI 可以分别 watch，测速重排不会把选中态带着抖。
final nodesProvider =
    AsyncNotifierProvider<NodesNotifier, List<Node>>(NodesNotifier.new);

class NodesNotifier extends AsyncNotifier<List<Node>> {
  @override
  Future<List<Node>> build() => _load();

  /// 拉一次订阅并解析；顺带把选中态对齐到新列表。
  Future<List<Node>> _load() async {
    // 订阅 token 来自 /api/me 的 data.token（不是 access_token）。
    final user = await ref.watch(userProvider.future);
    if (user == null) {
      // 未登录：清空选中态，交给路由守卫跳登录。
      await ref.read(selectedNodeProvider.notifier).reset();
      return const [];
    }
    if (user.token.isEmpty) {
      throw const ApiException(401, '缺少订阅凭证，请重新登录');
    }

    final fetched =
        await ref.read(subscriptionRepositoryProvider).fetchNodes(user.token);

    // 刷新后保留上一次的测速结果（同一条分享链接视为同一节点）。
    final previousLatency = <String, int?>{
      for (final n in state.valueOrNull ?? const <Node>[])
        if (n.latencyMs != null) n.raw: n.latencyMs,
    };
    final nodes = [
      for (final n in fetched)
        previousLatency.containsKey(n.raw)
            ? n.withLatency(previousLatency[n.raw])
            : n,
    ];

    await ref.read(selectedNodeProvider.notifier).reconcile(nodes);
    return nodes;
  }

  /// 下拉刷新 / 重试：重新拉订阅。
  ///
  /// 不用 `invalidateSelf`，避免刷新时列表闪回骨架屏（下拉刷新要保留旧内容）。
  Future<void> refresh() async {
    try {
      final nodes = await _load();
      state = AsyncData(nodes);
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  /// 选中节点（持久化到 prefs）。
  Future<void> select(Node node) =>
      ref.read(selectedNodeProvider.notifier).select(node);

  /// 全量测速（3 并发）。已知节点全部重测，失败/超时的节点延迟置为 null。
  Future<void> measureAll() async {
    final nodes = state.valueOrNull;
    if (nodes == null || nodes.isEmpty) return;
    final measured = await _measure(nodes);
    state = AsyncData(measured);

    // 自动选择开启时，测完立刻切到最快的那个。
    if (ref.read(autoSelectFastestProvider)) {
      final fastest = _fastest(measured);
      if (fastest != null) {
        await ref.read(selectedNodeProvider.notifier).select(fastest);
      }
    }
  }

  /// 只测一个节点（列表长按）。
  Future<void> measureOne(Node node) async {
    final nodes = state.valueOrNull;
    if (nodes == null || nodes.isEmpty) return;
    final measured = await _measure(nodes, only: node);
    state = AsyncData(measured);
  }

  /// 开关「自动选择最快节点」：打开时立即测速并切到最快节点。
  Future<void> setAutoSelectFastest(bool value) async {
    await ref.read(autoSelectFastestProvider.notifier).set(value);
    if (value) await measureAll();
  }

  /// 并发上限为 [kMeasureConcurrency] 的测速；`only` 非空时只测该节点。
  Future<List<Node>> _measure(List<Node> nodes, {Node? only}) async {
    final targets = only == null ? nodes : [only];
    if (targets.isEmpty) return nodes;

    final latency = <String, int?>{};
    var cursor = 0;
    final measuring = ref.read(measuringNodesProvider.notifier);

    Future<void> worker() async {
      while (true) {
        final index = cursor++;
        if (index >= targets.length) return;
        final node = targets[index];
        measuring.mark(node.raw);
        try {
          latency[node.raw] =
              await ref.read(vpnEngineProvider).measureDelay(node.raw);
        } catch (_) {
          latency[node.raw] = null;
        } finally {
          measuring.unmark(node.raw);
        }
      }
    }

    await Future.wait([
      for (var i = 0; i < math.min(kMeasureConcurrency, targets.length); i++)
        worker(),
    ]);

    return [
      for (final n in nodes)
        latency.containsKey(n.raw) ? n.withLatency(latency[n.raw]) : n,
    ];
  }

  static Node? _fastest(List<Node> nodes) {
    Node? best;
    for (final n in nodes) {
      final ms = n.latencyMs;
      if (ms == null) continue;
      if (best == null || ms < (best.latencyMs ?? 1 << 30)) best = n;
    }
    return best;
  }
}

/// 当前选中的节点（prefs 持久化，重开 App 仍是它）。
final selectedNodeProvider =
    NotifierProvider<SelectedNodeNotifier, Node?>(SelectedNodeNotifier.new);

class SelectedNodeNotifier extends Notifier<Node?> {
  @override
  Node? build() => null;

  /// 与最新节点列表对齐：
  /// 1. prefs 里记的 raw 还在 → 用列表里的新对象（带上新测速值）；
  /// 2. 不在了 → 退回第一个节点（保证首页「一键连接」总有节点可用）；
  /// 3. 列表为空 → 清空。
  ///
  /// 只在选中态真的变化时写盘，避免每次刷新都碰一次磁盘。
  Future<void> reconcile(List<Node> nodes) async {
    if (nodes.isEmpty) {
      await reset();
      return;
    }

    final current = state;
    if (current != null) {
      final matched = _match(nodes, current.raw);
      if (matched != null) {
        if (!identical(matched, current)) state = matched;
        return;
      }
    }

    String? persistedRaw;
    try {
      persistedRaw = await Prefs.getSelectedNode();
    } catch (_) {
      persistedRaw = null;
    }
    final persisted = persistedRaw == null ? null : _match(nodes, persistedRaw);
    final next = persisted ?? nodes.first;

    state = next;
    if (persisted == null) {
      // 首次进入 / 订阅已变：落盘，保证下次冷启动能直接命中。
      await _persist(next.raw);
    }
  }

  Future<void> select(Node node) async {
    state = node;
    await _persist(node.raw);
  }

  Future<void> reset() async {
    if (state != null) state = null;
  }

  Future<void> _persist(String raw) async {
    try {
      await Prefs.setSelectedNode(raw);
    } catch (_) {
      // prefs 写失败不影响本次选中（内存态已更新），下次冷启动退回第一个节点。
    }
  }

  static Node? _match(List<Node> nodes, String raw) {
    for (final n in nodes) {
      if (n.raw == raw) return n;
    }
    return null;
  }
}

/// 「自动选择最快节点」开关（prefs 持久化）。
final autoSelectFastestProvider =
    NotifierProvider<AutoSelectFastestNotifier, bool>(
        AutoSelectFastestNotifier.new);

class AutoSelectFastestNotifier extends Notifier<bool> {
  /// 用户（或启动流程之外）是否已经改过开关。
  ///
  /// 冷启动的 prefs 回填是异步的；回填落地前用户可能已经点了 Switch，
  /// 这时回填**不能**覆盖用户刚做的选择（否则开关会「点不动」）。
  bool _touched = false;

  @override
  bool build() {
    // 先返回默认值，异步回填（与 blockedApps 同一套做法）。
    unawaited(_restore());
    return false;
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getBool(_keyAutoSelectFastest) ?? false;
      if (_touched || value == state) return;
      state = value;
    } catch (_) {
      // 读失败保持默认关。
    }
  }

  Future<void> set(bool value) async {
    _touched = true;
    if (state == value) return;
    state = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyAutoSelectFastest, value);
    } catch (_) {
      // 写失败只影响下次冷启动的默认值。
    }
  }
}

/// 正在测速的节点 raw 集合（UI 在延迟徽章位置显示转圈）。
final measuringNodesProvider =
    NotifierProvider<MeasuringNodesNotifier, Set<String>>(
        MeasuringNodesNotifier.new);

class MeasuringNodesNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void mark(String raw) => state = {...state, raw};

  void unmark(String raw) {
    if (!state.contains(raw)) return;
    state = {...state}..remove(raw);
  }
}
