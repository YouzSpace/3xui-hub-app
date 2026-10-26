import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/vpn/subscription_parser.dart';

/// base64 标准编码（后端 `b64encode` = PHP base64_encode，带 padding）。
String _b64(String text) => base64.encode(utf8.encode(text));

const _vless1 =
    'vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@us.example.com:443'
    '?type=ws&security=tls&sni=us.example.com&path=%2Fws#US-01';
const _vless2 =
    'vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@us.example.com:8443'
    '?type=tcp&security=none#US-01-port8443';
const _vless3 =
    'vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@hk1.example.com:443'
    '?type=ws&security=tls#%E9%A6%99%E6%B8%AF%2001';
const _trojan =
    'trojan://pass@hk1.provider.net:443?security=tls&sni=hk1.provider.net'
    '#%E9%A6%99%E6%B8%AF';
const _ss = 'ss://YWVzLTI1Ni1nY206cGFzcw==@jp.provider.net:8388#Japan';

void main() {
  group('looksBase64（T3.2 第 1 条）', () {
    test('明文分享链接（含 ://）不判为 base64', () {
      expect(SubscriptionParser.looksBase64(_vless1), isFalse);
      expect(
        SubscriptionParser.looksBase64('$_vless1\n$_vless2\n$_vless3'),
        isFalse,
      );
    });

    test('足够长的无 :// 正文判为 base64', () {
      final body = _b64('$_vless1\n$_vless2');
      expect(body.contains('://'), isFalse);
      expect(body.length, greaterThan(40));
      expect(SubscriptionParser.looksBase64(body), isTrue);
    });

    test('短正文 / 空内容不判为 base64', () {
      expect(SubscriptionParser.looksBase64(''), isFalse);
      expect(SubscriptionParser.looksBase64('   \n  '), isFalse);
      expect(SubscriptionParser.looksBase64('aGVsbG8='), isFalse); // 长 8
    });

    test('带 BOM 的明文不判为 base64（BOM 先行剥掉）', () {
      expect(SubscriptionParser.looksBase64('﻿$_vless1'), isFalse);
    });
  });

  group('base64 订阅', () {
    test('1. 正常 base64 订阅（3 个 vless 节点）→ 3 个节点，名字正确', () {
      final body = _b64('$_vless1\n$_vless2\n$_vless3');
      final result = SubscriptionParser.parseDetailed(body);

      expect(result.nodes, hasLength(3));
      expect(result.errors, isEmpty);
      expect(result.decodedBase64, isTrue);
      expect(result.base64DecodeFailed, isFalse);

      expect(result.nodes[0].name, 'US-01');
      expect(result.nodes[0].protocol, 'vless');
      expect(result.nodes[0].host, 'us.example.com');
      expect(result.nodes[0].port, 443);
      // raw 必须完整保留（连接时直接交给引擎）。
      expect(result.nodes[0].raw, _vless1);

      expect(result.nodes[1].name, 'US-01-port8443');
      expect(result.nodes[1].port, 8443);
      // `%E9%A6%99%E6%B8%AF%2001` → 「香港 01」
      expect(result.nodes[2].name, '香港 01');
      expect(result.nodes[2].host, 'hk1.example.com');
    });

    test('2. 后端真实形态：base64 里含 ss/trojan/vmess 混合协议', () {
      final vmess = 'vmess://${_b64(jsonEncode({
            'v': '2',
            'ps': '🇯🇵 东京 02',
            'add': 'jp2.example.com',
            'port': '2053',
            'id': 'uuid-2',
            'net': 'ws',
            'tls': 'tls',
          }))}';
      final body = _b64([_trojan, _ss, vmess].join('\n'));
      final nodes = SubscriptionParser.parse(body);

      expect(nodes, hasLength(3));
      expect(nodes[0].protocol, 'trojan');
      expect(nodes[0].name, '香港');
      expect(nodes[0].host, 'hk1.provider.net');
      expect(nodes[0].port, 443);

      expect(nodes[1].protocol, 'ss');
      expect(nodes[1].name, 'Japan');
      expect(nodes[1].host, 'jp.provider.net');
      expect(nodes[1].port, 8388);

      // vmess 的名字只在 JSON 的 ps 里（后端 xrayVmessURI 不追加 #fragment）。
      expect(nodes[2].protocol, 'vmess');
      expect(nodes[2].name, '🇯🇵 东京 02');
      expect(nodes[2].host, 'jp2.example.com');
      expect(nodes[2].port, 2053);
    });

    test('3. URL-safe base64 + 缺 padding 也能解', () {
      final plain = '$_vless1\n$_vless2';
      final standard = base64.encode(utf8.encode(plain));
      final urlSafe = base64Url
          .encode(utf8.encode(plain))
          .replaceAll('=', '');
      expect(SubscriptionParser.parse(standard), hasLength(2));
      expect(SubscriptionParser.parse(urlSafe), hasLength(2));
    });
  });

  group('明文订阅', () {
    test('4. 明文多行链接（含空行、注释行、Windows CRLF）', () {
      const body = '# 我的订阅\n'
          '\n'
          '$_vless1\r\n'
          '   \r\n'
          '$_trojan\r\n'
          '$_ss\r\n'
          '# 以下为备用\n';
      final result = SubscriptionParser.parseDetailed(body);

      expect(result.decodedBase64, isFalse);
      expect(result.nodes, hasLength(3));
      expect(result.errors, isEmpty);
      expect(
        result.nodes.map((n) => n.protocol).toList(),
        ['vless', 'trojan', 'ss'],
      );
    });

    test('5. 含 emoji 节点名（🇭🇰 香港 01）解析后名字保留原文', () {
      const line = 'vless://uuid@hk.example.com:443?security=tls'
          '#%F0%9F%87%AD%F0%9F%87%B0%20%E9%A6%99%E6%B8%AF%2001';
      final node = SubscriptionParser.parseLine(line);

      expect(node, isNotNull);
      // 解析层不过滤 emoji（过滤是 UI 的 displayNodeName 的职责）。
      expect(node!.name, '🇭🇰 香港 01');
      expect(node.host, 'hk.example.com');
      expect(node.port, 443);
      expect(SubscriptionParser.parse(line).single.name, '🇭🇰 香港 01');
    });

    test('6. 名字缺失 → host:port 兜底', () {
      final node = SubscriptionParser.parseLine('vless://uuid@host.example:8443');
      expect(node, isNotNull);
      expect(node!.name, 'host.example:8443');
      expect(node.port, 8443);

      // `#` 后缀为空 / 只有空白，同样走兜底。
      final empty = SubscriptionParser.parseLine('trojan://p@h.example:443#');
      expect(empty?.name, 'h.example:443');
    });
  });

  group('异常输入', () {
    test('7. 空内容 → 空列表，不抛异常', () {
      expect(SubscriptionParser.parse(''), isEmpty);
      expect(SubscriptionParser.parse('   \n\n  \n'), isEmpty);
      final result = SubscriptionParser.parseDetailed('');
      expect(result.nodes, isEmpty);
      expect(result.errors, isEmpty);
      expect(result.base64DecodeFailed, isFalse);
    });

    test('8. 非法 base64 → base64DecodeFailed，节点为空不抛异常', () {
      // 长度 > 40、不含 ://、但不是合法 base64。
      final body = '!!!不是 base64 的垃圾内容!!! ${'x' * 60}';
      final result = SubscriptionParser.parseDetailed(body);

      expect(result.nodes, isEmpty);
      expect(result.base64DecodeFailed, isTrue);
      expect(result.decodedBase64, isFalse);
      // parse() 只取节点，也不抛。
      expect(SubscriptionParser.parse(body), isEmpty);
    });

    test('9. 混合垃圾行 → 只保留合法节点，垃圾行进 errors', () {
      const body = '$_vless1\n'
          'hello world\n'
          'http://example.com/not-a-node\n'
          'vless://\n'
          'vless://uuid@host-without-port\n'
          'ss://\n'
          '$_trojan\n'
          'vless://uuid@ok.example.com:99999#端口越界\n';
      final result = SubscriptionParser.parseDetailed(body);

      expect(result.nodes.map((n) => n.name).toList(), ['US-01', '香港']);
      expect(result.nodes, hasLength(2));
      // 6 条垃圾行全部记录（含端口越界那条）。
      expect(result.errors, hasLength(6));
      expect(result.errors, contains('hello world'));
    });

    test('10. 重复行只保留一条（去重按 raw）', () {
      final body = '$_vless1\n$_vless1\n$_vless2';
      final nodes = SubscriptionParser.parse(body);
      expect(nodes, hasLength(2));
      expect(nodes.first.raw, _vless1);
    });

    test('11. 超长行跳过并记录，不影响其他节点', () {
      final body = '$_vless1\nvless://${'a' * 5000}';
      final result = SubscriptionParser.parseDetailed(body);
      expect(result.nodes, hasLength(1));
      expect(result.errors.single, contains('超长行'));
    });
  });

  group('parseLine 细节', () {
    test('JSON 里的控制字符 / 空白前缀不影响解析', () {
      expect(
        SubscriptionParser.parseLine('   $_vless1   ')?.name,
        'US-01',
      );
    });

    test('不支持或不合法的 scheme → null', () {
      expect(SubscriptionParser.parseLine(''), isNull);
      expect(SubscriptionParser.parseLine('   '), isNull);
      expect(SubscriptionParser.parseLine('http://example.com'), isNull);
      expect(SubscriptionParser.parseLine('vless://'), isNull);
      expect(SubscriptionParser.parseLine('://host:443'), isNull);
      expect(SubscriptionParser.parseLine('vless://uuid@:443'), isNull);
    });

    test('IPv6 字面量 host 正确切分', () {
      final node =
          SubscriptionParser.parseLine('vless://uuid@[2001:db8::1]:8443#v6');
      expect(node, isNotNull);
      expect(node!.host, '2001:db8::1');
      expect(node.port, 8443);
    });
  });

  group('Node 基础契约', () {
    test('latencyLabel / withLatency 语义', () {
      final node = Node(
        raw: _vless1,
        name: 'US-01',
        protocol: 'vless',
        host: 'us.example.com',
        port: 443,
      );
      expect(node.latencyMs, isNull);
      expect(node.address, 'us.example.com:443');

      final measured = node.withLatency(88);
      expect(measured.latencyMs, 88);
      // 原对象不被就地修改（列表重建时靠不可变比较）。
      expect(node.latencyMs, isNull);

      // 显式清空测速结果。
      expect(measured.withLatency(null).latencyMs, isNull);
    });
  });
}
