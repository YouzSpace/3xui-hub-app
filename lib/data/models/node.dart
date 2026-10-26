import 'dart:convert';

/// 节点模型（system-design §4.3 / tasks/03_subscription.md T3.1）。
///
/// `raw` 保存原始分享链接，连接时直接交给 VpnEngine 转换；
/// `latencyMs` 是测速结果，允许就地更新（测速后写回）。
///
/// 解析入口统一收口在 [Node.fromShareLink]：订阅解析器（`vpn/subscription_parser.dart`）
/// 与单测都走这里，避免两套解析逻辑漂移。
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

  /// `host:port`（UI 第二行与名字兜底都用它）。
  String get address => '$host:$port';

  /// 支持的分享链接协议（后端 `xrayuri.go` 实际会输出的四种）。
  static const Set<String> supportedSchemes = {'vless', 'trojan', 'vmess', 'ss'};

  /// 从分享链接构造节点；无法识别返回 null（**不抛异常**）。
  ///
  /// 解析规则（tasks/03_subscription.md T3.2 第 3/4 条）：
  /// - `scheme://` 到 `#` 之前是配置，`#` 之后是名字（`Uri.decodeComponent`）；
  /// - 名字缺失（或 decode 后为空）用 `host:port` 兜底；
  /// - vmess 链接的名字可能只存在于 JSON 的 `ps` 字段（后端 `xrayVmessURI`
  ///   不追加 `#fragment`），因此 vmess 额外认 `ps`。
  static Node? fromShareLink(String shareLink) {
    final line = shareLink.trim();
    if (line.isEmpty) return null;

    final schemeEnd = line.indexOf('://');
    if (schemeEnd <= 0) return null;
    final scheme = line.substring(0, schemeEnd).toLowerCase();
    if (!supportedSchemes.contains(scheme)) return null;

    final rest = line.substring(schemeEnd + 3);
    final hashAt = rest.indexOf('#');
    final config = hashAt >= 0 ? rest.substring(0, hashAt) : rest;
    final name = _decodeName(hashAt >= 0 ? rest.substring(hashAt + 1) : '');
    if (config.isEmpty) return null;

    try {
      switch (scheme) {
        case 'vmess':
          return _fromVmess(line, config, name);
        case 'ss':
          return _fromShadowsocks(line, config, name);
        default:
          return _fromStandard(scheme, line, config, name);
      }
    } catch (_) {
      // 任何畸形链接都只返回 null，由调用方记 errors。
      return null;
    }
  }

  /// 单行解析的别名（订阅解析器按行调用）。
  static Node? parseLine(String line) => fromShareLink(line);

  /// `vless://uuid@host:port?query` / `trojan://pass@host:port?query`。
  static Node? _fromStandard(
    String scheme,
    String raw,
    String config,
    String? name,
  ) {
    // 只看 authority 部分：去掉 query 与可能存在的 path。
    final queryAt = config.indexOf('?');
    final authority = (queryAt >= 0 ? config.substring(0, queryAt) : config)
        .split('/')
        .first;
    // uuid / password 里允许出现 '@'（极少见），取最后一个分隔符更稳。
    final at = authority.lastIndexOf('@');
    if (at < 0) return null;
    final hostPort = _splitHostPort(authority.substring(at + 1));
    if (hostPort == null) return null;
    return Node(
      raw: raw,
      name: name ?? '${hostPort.host}:${hostPort.port}',
      protocol: scheme,
      host: hostPort.host,
      port: hostPort.port,
    );
  }

  /// `vmess://base64({add,port,ps,...})[#name]`。
  ///
  /// 后端 `xrayVmessURI` 生成的就是这种「整段 base64 JSON，无 fragment」形态。
  static Node? _fromVmess(String raw, String config, String? name) {
    final queryAt = config.indexOf('?');
    final payload = queryAt >= 0 ? config.substring(0, queryAt) : config;
    final jsonText = _base64ToUtf8(payload);
    if (jsonText == null) return null;
    final decoded = jsonDecode(jsonText);
    if (decoded is! Map) return null;

    final host = (decoded['add'] ?? '').toString().trim();
    final port = int.tryParse((decoded['port'] ?? '').toString().trim());
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;

    final ps = (decoded['ps'] ?? '').toString().trim();
    return Node(
      raw: raw,
      name: name ?? (ps.isEmpty ? '$host:$port' : ps),
      protocol: 'vmess',
      host: host,
      port: port,
    );
  }

  /// Shadowsocks 两种形态：
  /// - SIP002：`ss://base64(method:password)@host:port#name`（后端用这种）；
  /// - 旧版：`ss://base64(method:password@host:port)#name`。
  static Node? _fromShadowsocks(String raw, String config, String? name) {
    final queryAt = config.indexOf('?');
    final body = (queryAt >= 0 ? config.substring(0, queryAt) : config)
        .split('/')
        .first;

    String authority;
    final at = body.lastIndexOf('@');
    if (at >= 0) {
      authority = body.substring(at + 1);
    } else {
      // 旧版：整段是 base64，解出来才是 method:password@host:port。
      final decoded = _base64ToUtf8(body);
      if (decoded == null) return null;
      final innerAt = decoded.lastIndexOf('@');
      if (innerAt < 0) return null;
      authority = decoded.substring(innerAt + 1).split('/').first;
    }

    final hostPort = _splitHostPort(authority);
    if (hostPort == null) return null;
    return Node(
      raw: raw,
      name: name ?? '${hostPort.host}:${hostPort.port}',
      protocol: 'ss',
      host: hostPort.host,
      port: hostPort.port,
    );
  }

  /// 解析 `host:port` / `[ipv6]:port`；不合法返回 null。
  static ({String host, int port})? _splitHostPort(String input) {
    final text = input.trim();
    if (text.isEmpty) return null;

    String host;
    String portText;
    if (text.startsWith('[')) {
      // IPv6 字面量：[2001:db8::1]:443
      final close = text.indexOf(']');
      if (close < 0) return null;
      host = text.substring(1, close);
      final rest = text.substring(close + 1);
      if (!rest.startsWith(':')) return null;
      portText = rest.substring(1);
    } else {
      final colon = text.lastIndexOf(':');
      if (colon <= 0) return null;
      host = text.substring(0, colon);
      portText = text.substring(colon + 1);
    }

    final port = int.tryParse(portText);
    if (host.isEmpty || port == null || port <= 0 || port > 65535) return null;
    return (host: host, port: port);
  }

  /// `#` 之后的原始值 → 展示名；decode 失败或为空返回 null（交给兜底）。
  static String? _decodeName(String fragment) {
    final text = fragment.trim();
    if (text.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(text);
    } catch (_) {
      // 非法的百分号转义（如 `#100%`）原样使用，不丢节点。
      decoded = text;
    }
    decoded = decoded.trim();
    return decoded.isEmpty ? null : decoded;
  }

  /// base64（标准/URL-safe，允许缺 padding 与空白）→ UTF-8 文本；失败返回 null。
  static String? _base64ToUtf8(String input) {
    final compact = input.replaceAll(RegExp(r'\s'), '');
    if (compact.isEmpty) return null;
    try {
      return utf8.decode(base64.decode(base64.normalize(compact)));
    } catch (_) {
      return null;
    }
  }

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

  /// 显式改写测速结果：传 null 可清空（[copyWith] 的 `??` 语义做不到这点）。
  Node withLatency(int? ms) => Node(
        raw: raw,
        name: name,
        protocol: protocol,
        host: host,
        port: port,
        latencyMs: ms,
      );

  @override
  bool operator ==(Object other) =>
      other is Node && other.raw == raw && other.name == name;

  @override
  int get hashCode => Object.hash(raw, name);

  @override
  String toString() => 'Node($name, $protocol://$host:$port)';
}
