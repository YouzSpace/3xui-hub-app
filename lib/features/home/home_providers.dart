import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/storage/prefs.dart';
import '../../data/models/node.dart';
import '../../data/models/user_profile.dart';
import '../../features/update/update_providers.dart';
import '../../features/update/version_reporter.dart';
import '../../providers/auth_providers.dart';
import '../../vpn/vpn_controller.dart';
import '../../vpn/vpn_state.dart';
import '../nodes/nodes_provider.dart';

/// 首页一次性提示（SnackBar 文案）。
///
/// 写入后由首页消费并清空；只存内存，不落盘。
final homeNoticeProvider = StateProvider<String?>((ref) => null);

/// 公告是否已读（本次会话内存态，不落盘）：点「知道了」后红点消失。
final noticeReadProvider = StateProvider<bool>((ref) => false);

/// 套餐层面的连接阻断原因；null = 允许点击连接。
///
/// 规则与 `VpnController.validate()` 的第 1–4 条一致（未登录 / 禁用 / 无套餐 /
/// 到期 / 流量耗尽），但不校验节点：节点还没选好时首页不该把按钮判成禁用，
/// 点下去由 `connect()` 给出「请先选择一个节点」的明确提示。
String? planBlockReason(UserProfile? user, {DateTime? now}) {
  if (user == null) return '请先登录后再连接';
  if (!user.enabled) return '账号已被禁用，请联系管理员';
  if (user.planId == 0) return '还没有可用套餐，请先购买';
  final expired = user.expiredAt;
  // total 流量套餐没有过期时间（expired_at 为 null），跳过过期校验；
  // 只有周期套餐（month 等）才检查 expired_at。
  if (expired != null && !expired.isAfter(now ?? DateTime.now())) {
    return '套餐已到期，请先续费';
  }
  final limit = user.monthlyTrafficLimit;
  if (limit > 0 && user.monthlyTrafficUsed >= limit) {
    return '本月流量已用完，请等待重置或购买重置包';
  }
  return null;
}

/// 首页连接按钮的禁用原因（null = 可点）。
final planBlockReasonProvider = Provider<String?>(
  (ref) => planBlockReason(ref.watch(userProvider).valueOrNull),
);

/// 连接按钮的动作（T5.2：点击 → vpnProvider）。
///
/// - 已连接 / 断开中：走 M4 的 `toggle()`；
/// - 其余状态：`toggle()` 内部是 `connect(null)`，会被校验链拦成
///   「请先选择一个节点」，因此这里显式传当前选中节点。
final connectionToggleProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final controller = ref.read(vpnProvider.notifier);
    final state = ref.read(vpnProvider);
    if (state.status == VpnStatus.connected ||
        state.status == VpnStatus.disconnecting) {
      await controller.toggle();
      return;
    }
    await controller.connect(_resolveConnectNode(ref));
  };
});

/// 连接目标节点：自动选择开启时用延迟最低（有测速结果），否则用选中节点。
///
/// 测速还没出结果（或全部失败）时用第一个节点而非「选中节点」——
/// 自动选择模式下不该回退到手动选的那个，否则「打开自动选择」形同虚设。
Node? _resolveConnectNode(Ref ref) {
  if (!ref.read(autoSelectFastestProvider)) {
    return ref.read(selectedNodeProvider);
  }
  final nodes = ref.read(nodesProvider).valueOrNull ?? const <Node>[];
  if (nodes.isEmpty) return ref.read(selectedNodeProvider);
  Node? fastest;
  for (final n in nodes) {
    final ms = n.latencyMs;
    if (ms == null) continue;
    if (fastest == null || ms < (fastest.latencyMs ?? 1 << 30)) fastest = n;
  }
  return fastest ?? nodes.first;
}

/// 下拉刷新（T5.5）：同时刷新 userProvider 与 nodesProvider，且不重复请求。
///
/// 关键点：`NodesNotifier._load()` 里 `ref.watch(userProvider.future)`，
/// 所以 invalidate(userProvider) 已经让订阅自动重拉。这里再调
/// `nodesProvider.refresh()` 会把订阅拉两次 —— 只 await 两边即可。
class HomeRefresher {
  HomeRefresher(this._ref);

  final Ref _ref;
  Future<void>? _inflight;

  /// 重复下拉返回同一个 Future，不发第二次请求。
  Future<void> call() {
    final running = _inflight;
    if (running != null) return running;
    final future = _run();
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<void> _run() async {
    _ref.invalidate(userProvider);
    try {
      await Future.wait([
        _ref.read(userProvider.future),
        _ref.read(nodesProvider.future),
      ]);
    } catch (_) {
      // 失败由各自的 error 态承担（页面 ErrorView / 节点页重试），
      // 下拉刷新只负责把转圈收掉。
    }
  }
}

final homeRefresherProvider = Provider<HomeRefresher>(HomeRefresher.new);

/// 进首页时的版本检查（T5.1 ④）：optional 显示提示条，force 直接弹窗。
///
/// 不走 M9B 的 `UpdateGate`：那个守卫对 optional 也直接弹窗，
/// 与首页「optional 只出现一行提示条」的规格冲突。
final updateDecisionProvider = FutureProvider<VersionDecision?>((ref) async {
  try {
    return await ref.read(versionReporterProvider).report();
  } catch (_) {
    // 检查更新永远不影响首页渲染。
    return null;
  }
});

/// 只有 action == optional 才在首页出现提示条。
final optionalUpdateProvider = Provider<VersionDecision?>((ref) {
  final decision = ref.watch(updateDecisionProvider).valueOrNull;
  return decision != null && decision.isOptional ? decision : null;
});

/// 首页状态联动（T5.6）。
///
/// 由 `HomePage` watch 住，首页存活期间常驻：
/// 1. `/api/me` 的 protocol 变化 → 清节点缓存 + 重拉订阅；
/// 2. 订阅刷新后当前连接节点不存在 → 自动断开 + 提示「节点已失效，请重新选择」。
final homeSyncProvider = Provider<HomeStatusSync>(HomeStatusSync.new);

class HomeStatusSync {
  HomeStatusSync(this._ref) {
    // 首页可能挂载时 /api/me 已有数据（从别的 tab 切回来），先记下基线。
    _protocol = _ref.read(userProvider).valueOrNull?.protocol;
    _ref.listen<AsyncValue<UserProfile?>>(userProvider, _onUser);
    _ref.listen<AsyncValue<List<Node>>>(
      nodesProvider,
      (_, next) => _onNodes(next.valueOrNull),
    );
  }

  final Ref _ref;

  /// 上一次看到的用户协议（null = 还没有基线，首次下发不触发重拉）。
  String? _protocol;

  void _onUser(AsyncValue<UserProfile?>? _, AsyncValue<UserProfile?> next) {
    // 刷新中（invalidateSelf）会先来一帧 loading：保留基线，否则协议变化
    // 会在「loading 清空基线 → 新值到达」的过程中被吞掉。
    if (next.isLoading) return;
    final user = next.valueOrNull;
    if (user == null) {
      _protocol = null;
      return;
    }
    final previous = _protocol;
    _protocol = user.protocol;
    if (previous == null || previous == user.protocol) return;
    unawaited(_onProtocolChanged());
  }

  Future<void> _onProtocolChanged() async {
    await _clearNodeCache();
    _notify('节点协议已更新，正在重新获取');
    try {
      // userProvider 已变化 → nodesProvider 失效；读 .future 会触发（且只触发一次）
      // 重新拉订阅。这里不再额外 refresh()，否则订阅被拉两次。
      await _ref.read(nodesProvider.future);
    } catch (_) {
      // 重拉失败由节点页/首页的 error 态承担，联动本身不再重复提示。
    }
  }

  Future<void> _onNodes(List<Node>? nodes) async {
    if (nodes == null) return;
    final vpn = _ref.read(vpnProvider);
    final active = vpn.activeNode;
    if (active == null) return;
    if (vpn.status == VpnStatus.idle || vpn.status == VpnStatus.error) return;
    if (nodes.any((n) => n.raw == active.raw)) return;

    await _ref.read(vpnProvider.notifier).disconnect();
    _notify('节点已失效，请重新选择');
  }

  void _notify(String text) =>
      _ref.read(homeNoticeProvider.notifier).state = text;

  /// 清节点缓存（订阅正文不落盘，这里清的是「上次选中的节点」）。
  Future<void> _clearNodeCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(Prefs.keySelectedNode);
    } catch (_) {
      // 清缓存失败不影响后续：选中态 reconcile 时同样会回退到第一个节点。
    }
  }
}
