import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/models/node.dart';

/// 订阅解析结果（[SubscriptionParser.parseDetailed] 返回）。
///
/// [errors] 只用于调试/日志，不直接上屏；[base64DecodeFailed] 区分
/// 「订阅格式坏了」和「订阅正常但没有可用节点」两种空列表。
@immutable
class SubscriptionParseResult {
  final List<Node> nodes;

  /// 被跳过的行（原始文本，截断到 80 字符，避免日志过长）。
  final List<String> errors;

  /// 正文看起来是 base64 但解码失败（→「订阅格式异常」）。
  final bool base64DecodeFailed;

  /// 正文是否做过 base64 解码。
  final bool decodedBase64;

  const SubscriptionParseResult({
    required this.nodes,
    required this.errors,
    required this.base64DecodeFailed,
    required this.decodedBase64,
  });

  const SubscriptionParseResult.empty()
      : nodes = const [],
        errors = const [],
        base64DecodeFailed = false,
        decodedBase64 = false;

  @override
  String toString() => 'SubscriptionParseResult(${nodes.length} nodes, '
      '${errors.length} errors, base64=$decodedBase64)';
}

/// 订阅文本 → 节点列表（system-design §4.3 / tasks/03_subscription.md T3.2）。
///
/// 后端 `GET /api/sub/{token}` 默认输出 base64 编码的多行分享链接
/// （`server/internal/subscription/service.go` → `b64encode(strings.Join(links, "\n"))`），
/// 也兼容明文多行的调试输出。
///
/// 规则（严格按 T3.2 五条）：
/// 1. 正文不含 `://` 且长度 > 40 → 去掉所有空白后尝试 base64 解码；
/// 2. 按 `\n` 切分，过滤空行与 `#` 开头的注释行；
/// 3. `scheme://` 到 `#` 之前为配置，`#` 之后 `Uri.decodeComponent` 为名字；
/// 4. 名字缺失 → `host:port` 兜底；
/// 5. 解析异常的行跳过不抛，记录到 `errors`。
class SubscriptionParser {
  SubscriptionParser._();

  /// 单行长度上限：正常分享链接远小于它，超长行直接判为垃圾数据。
  static const int _maxLineLength = 4096;

  /// 少于这个长度的正文不可能是 base64 编码的订阅（最短的 `vless://a@b:1` 链接
  /// base64 后也有 20+ 字符，取 40 与 T3.2 一致）。
  static const int _minBase64Length = 40;

  /// 整体解析，只返回节点列表（T3.2 约定签名）。
  static List<Node> parse(String body) => parseDetailed(body).nodes;

  /// 整体解析，同时返回被跳过的行与 base64 状态（仓库/单测用）。
  static SubscriptionParseResult parseDetailed(String body) {
    // BOM 会污染第一行（部分 CDN 回源会加），先剥掉。
    final text = body.startsWith('﻿') ? body.substring(1) : body;

    var decodedBase64 = false;
    var base64DecodeFailed = false;
    var content = text;

    if (looksBase64(text)) {
      final decoded = _decodeBase64(text);
      if (decoded == null) {
        base64DecodeFailed = true;
      } else {
        decodedBase64 = true;
        content = decoded;
      }
    }

    final nodes = <Node>[];
    final errors = <String>[];
    // 同一份订阅里同名同链接的重复行只保留一条（后端第三方订阅可能重复下发）。
    final seen = <String>{};

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) continue;

      if (line.length > _maxLineLength) {
        errors.add('超长行(${line.length})');
        continue;
      }

      // 不做 base64 再解码，只解析分享链接本体。
      final node = Node.fromShareLink(line);
      if (node == null) {
        errors.add(_clip(line));
        continue;
      }
      if (seen.add(node.raw)) nodes.add(node);
    }

    return SubscriptionParseResult(
      nodes: List.unmodifiable(nodes),
      errors: List.unmodifiable(errors),
      base64DecodeFailed: base64DecodeFailed,
      decodedBase64: decodedBase64,
    );
  }

  /// 单行解析；不是支持的分享链接返回 null（vmess 的 `ps` 也参与取名字）。
  static Node? parseLine(String line) => Node.fromShareLink(line);

  /// 判断正文是否需要 base64 解码（T3.2 第 1 条）。
  ///
  /// 明文订阅一定含 `://`；不含又足够长，基本只可能是 base64。
  static bool looksBase64(String body) {
    final text = body.startsWith('﻿') ? body.substring(1) : body;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;
    if (trimmed.contains('://')) return false;
    // 长度按「去掉空白后」算：base64 正文里理论上没有换行，但粘贴进来的可能有。
    final compactLength = trimmed.replaceAll(RegExp(r'\s'), '').length;
    return compactLength > _minBase64Length;
  }

  /// 去空白后 base64 解码成 UTF-8；失败返回 null。
  static String? _decodeBase64(String body) {
    final compact = body.replaceAll(RegExp(r'\s'), '');
    if (compact.isEmpty) return null;
    try {
      // normalize：补齐 padding + URL-safe（`-_`）转标准字母表。
      return utf8.decode(base64.decode(base64.normalize(compact)));
    } catch (_) {
      return null;
    }
  }

  static String _clip(String line) =>
      line.length <= 80 ? line : '${line.substring(0, 80)}…';
}
