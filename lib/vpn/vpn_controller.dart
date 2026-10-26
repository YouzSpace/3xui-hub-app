import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/node.dart';
import '../data/models/user_profile.dart';
import '../providers/auth_providers.dart';
import 'bypass_china.dart';
import 'vpn_engine.dart';
import 'vpn_state.dart';

/// 连接状态机控制器（system-design §4.1 / tasks/04_vpn.md T4.3）。
///
/// 状态迁移：idle → preparing → connecting → connected → disconnecting → idle；
/// preparing/connecting 失败 → error。
class VpnController extends Notifier<VpnState> {
  /// 引擎经 Provider 注入：测试时可 override 成 mock 引擎。
  late final VpnEngine _engine = ref.read(vpnEngineProvider);

  StreamSubscription<VpnStatus>? _statusSub;
  Timer? _ticker;

  @override
  VpnState build() {
    // 订阅引擎状态流：原生侧状态变化（含连接中断）直接驱动本地状态机。
    _statusSub = _engine.statusStream.listen(_onEngineStatus);
    ref.onDispose(() {
      _statusSub?.cancel();
      _ticker?.cancel();
    });
    return const VpnState();
  }

  /// 原生状态回调 → 本地状态。
  void _onEngineStatus(VpnStatus status) {
    switch (status) {
      case VpnStatus.connected:
        _startTicker();
        state = state.copyWith(
          status: VpnStatus.connected,
          errorMessage: null,
        );
      case VpnStatus.connecting:
        state = state.copyWith(status: VpnStatus.connecting, errorMessage: null);
      case VpnStatus.disconnecting:
        state = state.copyWith(status: VpnStatus.disconnecting);
      case VpnStatus.idle:
      case VpnStatus.preparing:
      case VpnStatus.error:
        // disconnected 回调/未知来源的 idle：收尾清态。
        if (state.status != VpnStatus.idle) {
          _stopTicker();
          state = VpnState(status: VpnStatus.idle, latencyMs: state.latencyMs);
        }
    }
  }

  /// 首页大按钮：已连接/错误/空闲 → 连接或断开。
  Future<void> toggle() async {
    if (state.isBusy) return;
    if (state.status == VpnStatus.connected) {
      await disconnect();
    } else {
      final user = ref.read(userProvider).value;
      // 校验需要套餐信息，拿不到时只报「未找到可用节点」之前的账号问题由
      // 校验链 1-4 覆盖；节点列表 M3 未接入时这里传 null 让校验拦下。
      await connect(null, user: user);
    }
  }

  /// 连接前 5 项校验（顺序执行，任一不满足 → error 态，不启动隧道）。
  /// 返回 null 表示校验通过（user/plan 由调用方继续使用）。
  String? validate(UserProfile? user, Node? node) {
    if (user == null) return '请先登录后再连接';
    if (!user.enabled) return '账号已被禁用，请联系管理员';
    if (user.planId == 0) return '还没有可用套餐，请先购买';
    final expired = user.expiredAt;
    // total 流量套餐没有过期时间（expired_at 为 null），跳过过期校验；
    // 只有周期套餐（month 等）才检查 expired_at。
    if (expired != null && !expired.isAfter(DateTime.now())) {
      return '套餐已到期，请先续费';
    }
    // monthly_traffic_limit == 0 视为不限流量。
    final limit = user.monthlyTrafficLimit;
    if (limit > 0 && user.monthlyTrafficUsed >= limit) {
      return '本月流量已用完，请等待重置或购买重置包';
    }
    if (node == null || node.raw.isEmpty) return '请先选择一个节点';
    return null;
  }

  /// 连接指定节点；node 为 null 时先做账号校验（快速失败给首页按钮）。
  Future<void> connect(Node? node, {UserProfile? user}) async {
    if (state.isBusy || state.status == VpnStatus.connected) return;

    // 校验链：账号/套餐/到期/流量/节点。任一失败不碰隧道。
    final profile = user ?? ref.read(userProvider).value;
    final error = validate(profile, node);
    if (error != null) {
      state = VpnState(status: VpnStatus.error, errorMessage: error);
      return;
    }

    state = state.copyWith(status: VpnStatus.preparing, errorMessage: null);
    try {
      await _engine.initialize();
      final config = await _engine.buildConfig(
        node!.raw,
        bypassChina: ref.read(bypassChinaProvider),
      );
      await _engine.start(
        remark: node.name,
        config: config,
      );
      // 原生侧状态回调会把状态推进到 connecting/connected；
      // 这里只兜底置 connecting，避免回调延迟时 UI 卡在 preparing。
      state = state.copyWith(
        status: VpnStatus.connecting,
        activeNode: node,
      );
    } on VpnException catch (e) {
      _fail(e.message);
    } catch (_) {
      // ArgumentError（config 非法）等插件异常：不把内部细节暴露给用户。
      _fail('连接失败，请稍后重试');
    }
  }

  /// 断开。M8 退出登录流程必须先调本方法。
  Future<void> disconnect() async {
    if (state.status == VpnStatus.idle ||
        state.status == VpnStatus.disconnecting) {
      return;
    }
    _stopTicker();
    state = state.copyWith(status: VpnStatus.disconnecting);
    try {
      await _engine.stop();
    } catch (_) {
      // stop 失败也继续收尾：原生 disconnected 回调或用户重连可恢复。
    }
    _stopTicker();
    state = VpnState(status: VpnStatus.idle, latencyMs: state.latencyMs);
  }

  /// 已连接时断开并用当前节点重连（绕开国内等连接配置变更后让新配置生效）。
  Future<void> reconnectActive() async {
    final node = state.activeNode;
    if (state.status != VpnStatus.connected || node == null) return;
    await disconnect();
    await connect(node);
  }

  /// 连接后测速并写入状态（M3/M5 调用）。
  Future<void> measureActiveLatency() async {
    final node = state.activeNode;
    if (node == null) return;
    // 已连接时复用当前 VPN 进程测延迟（getServerDelay 会另起 xray 进程，
    // 与正在跑的 VPN 冲突，导致「连接中刷不出延迟」）。
    final delay = await _engine.measureConnectedDelay();
    if (delay != null) {
      state = state.copyWith(latencyMs: delay);
      node.latencyMs = delay;
    }
  }

  /// 每秒更新 connectedFor（connected 态由 _startTicker 驱动，外部无需手动调）。
  void tick() {
    if (state.status != VpnStatus.connected) return;
    state = state.copyWith(
      connectedFor: state.connectedFor + const Duration(seconds: 1),
    );
  }

  void _startTicker() {
    // 引擎在 connected 状态下会周期性重复回调，若每次都重置计时器，
    // 时长会一直 00:01 来回跳。已在计时则直接忽略，只保留首次启动。
    if (_ticker != null) return;
    state = state.copyWith(connectedFor: Duration.zero);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => tick());
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  void _fail(String message) {
    _stopTicker();
    state = VpnState(
      status: VpnStatus.error,
      errorMessage: message,
      latencyMs: state.latencyMs,
    );
  }
}

/// 引擎 Provider：测试 override 注入 mock VpnEngine。
final vpnEngineProvider = Provider<VpnEngine>((ref) => FlutterVlessEngine());

final vpnProvider = NotifierProvider<VpnController, VpnState>(VpnController.new);
