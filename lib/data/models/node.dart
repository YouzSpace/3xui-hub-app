/// 节点模型（system-design §4.3）。
///
/// `raw` 保存原始分享链接，连接时直接交给 VpnEngine 转换；
/// `latencyMs` 是测速结果，允许就地更新（测速后写回）。
class Node {
  /// 原始分享链接（vless:// / trojan:// ...），连接时直接传。
  final String raw;

  /// 展示名（链接 # 后面的名字，URL decode 后）。
  final String name;

  /// 协议：vless / trojan / vmess / ss ...
  final String protocol;

  final String host;
  final int port;

  /// 最近一次测速结果（毫秒），null 表示未测。
  int? latencyMs;

  Node({
    required this.raw,
    required this.name,
    required this.protocol,
    required this.host,
    required this.port,
    this.latencyMs,
  });

  Node copyWith({
    String? raw,
    String? name,
    String? protocol,
    String? host,
    int? port,
    int? latencyMs,
  }) {
    return Node(
      raw: raw ?? this.raw,
      name: name ?? this.name,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Node && other.raw == raw && other.name == name;

  @override
  int get hashCode => Object.hash(raw, name);

  @override
  String toString() => 'Node($name, $protocol://$host:$port)';
}
