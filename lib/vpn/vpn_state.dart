import '../data/models/node.dart';

/// VPN 连接状态机（system-design §4.1）。
///
/// 状态迁移：idle → preparing → connecting → connected → disconnecting → idle；
/// preparing/connecting 失败 → error。
enum VpnStatus { idle, preparing, connecting, connected, disconnecting, error }

class VpnState {
  final VpnStatus status;

  /// 当前连接的节点；未连接为 null。
  final Node? activeNode;

  /// 已连接时长（connected 状态下每秒 tick 更新）。
  final Duration connectedFor;

  /// 最近一次测速结果（毫秒）。
  final int? latencyMs;

  /// 可直接展示的中文错误文案（status == error 时非空）。
  final String? errorMessage;

  const VpnState({
    this.status = VpnStatus.idle,
    this.activeNode,
    this.connectedFor = Duration.zero,
    this.latencyMs,
    this.errorMessage,
  });

  /// preparing/connecting/disconnecting 属于过渡态，UI 上按钮应禁用防连点。
  bool get isBusy =>
      status == VpnStatus.preparing ||
      status == VpnStatus.connecting ||
      status == VpnStatus.disconnecting;

  VpnState copyWith({
    VpnStatus? status,
    Node? activeNode,
    Duration? connectedFor,
    int? latencyMs,
    String? errorMessage,
  }) {
    return VpnState(
      status: status ?? this.status,
      activeNode: activeNode ?? this.activeNode,
      connectedFor: connectedFor ?? this.connectedFor,
      latencyMs: latencyMs ?? this.latencyMs,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VpnState &&
      other.status == status &&
      other.activeNode == activeNode &&
      other.connectedFor == connectedFor &&
      other.latencyMs == latencyMs &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode =>
      Object.hash(status, activeNode, connectedFor, latencyMs, errorMessage);

  @override
  String toString() =>
      'VpnState($status, node=$activeNode, for=$connectedFor, err=$errorMessage)';
}
