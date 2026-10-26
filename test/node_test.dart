import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/data/models/node.dart';

String _b64(String text) => base64.encode(utf8.encode(text));

void main() {
  group('Node.fromShareLink（T3.1 验收）', () {
    test('vless：protocol/host/port/name 全部提取正确', () {
      const raw = 'vless://uuid-1@us.example.com:443'
          '?type=ws&security=tls&sni=us.example.com&path=%2Fws#US-01';
      final node = Node.fromShareLink(raw);

      expect(node, isNotNull);
      expect(node!.raw, raw);
      expect(node.protocol, 'vless');
      expect(node.host, 'us.example.com');
      expect(node.port, 443);
      expect(node.name, 'US-01');
      expect(node.latencyMs, isNull);
      expect(node.address, 'us.example.com:443');
    });

    test('trojan：密码里带特殊字符不影响 host 切分', () {
      const raw = 'trojan://p%40ss:w0rd@hk1.provider.net:443'
          '?security=tls&sni=hk1.provider.net#%E9%A6%99%E6%B8%AF%20%E4%BC%98%E9%80%89';
      final node = Node.fromShareLink(raw);

      expect(node, isNotNull);
      expect(node!.protocol, 'trojan');
      // 取最后一个 '@' 之后作为 authority，密码里的 '@' 不会切错。
      expect(node.host, 'hk1.provider.net');
      expect(node.port, 443);
      expect(node.name, '香港 优选');
    });

    test('vmess：整段 base64 JSON，名字取 ps', () {
      final payload = jsonEncode({
        'v': '2',
        'ps': 'SG-Premium',
        'add': 'sg.provider.net',
        'port': '443',
        'id': 'uuid-x',
        'net': 'grpc',
        'tls': 'tls',
      });
      final raw = 'vmess://${_b64(payload)}';
      final node = Node.fromShareLink(raw);

      expect(node, isNotNull);
      expect(node!.protocol, 'vmess');
      expect(node.host, 'sg.provider.net');
      expect(node.port, 443);
      expect(node.name, 'SG-Premium');
      expect(node.raw, raw);
    });

    test('vmess：JSON 不规范（port 是数字、缺 ps）也不崩', () {
      final payload = jsonEncode({'add': 'a.example.com', 'port': 8080});
      final node = Node.fromShareLink('vmess://${_b64(payload)}');

      expect(node, isNotNull);
      expect(node!.port, 8080);
      // ps 缺失 → host:port 兜底。
      expect(node.name, 'a.example.com:8080');
    });

    test('ss：SIP002（base64(method:password)@host:port）', () {
      const raw = 'ss://YWVzLTI1Ni1nY206cGFzcw==@jp.provider.net:8388#Japan';
      final node = Node.fromShareLink(raw);

      expect(node, isNotNull);
      expect(node!.protocol, 'ss');
      expect(node.host, 'jp.provider.net');
      expect(node.port, 8388);
      expect(node.name, 'Japan');
    });

    test('ss：旧版整段 base64 形态', () {
      final legacy = _b64('aes-256-gcm:pass@old.example.com:8389');
      final node = Node.fromShareLink('ss://$legacy#OldSS');

      expect(node, isNotNull);
      expect(node!.host, 'old.example.com');
      expect(node.port, 8389);
      expect(node.name, 'OldSS');
    });

    test('名字缺失 / 空 / 非法转义 → 兜底或原样，不抛异常', () {
      expect(
        Node.fromShareLink('vless://uuid@a.example.com:443')!.name,
        'a.example.com:443',
      );
      expect(
        Node.fromShareLink('vless://uuid@a.example.com:443#   ')!.name,
        'a.example.com:443',
      );
      // 非法的百分号转义：原样保留（不丢节点）。
      expect(
        Node.fromShareLink('vless://uuid@a.example.com:443#100%')!.name,
        '100%',
      );
    });

    test('非法输入返回 null，不抛异常', () {
      expect(Node.fromShareLink(''), isNull);
      expect(Node.fromShareLink('   '), isNull);
      expect(Node.fromShareLink('http://example.com'), isNull);
      expect(Node.fromShareLink('vless://'), isNull);
      expect(Node.fromShareLink('vless://uuid@'), isNull);
      expect(Node.fromShareLink('vless://uuid@host'), isNull); // 缺端口
      expect(Node.fromShareLink('vless://uuid@host:0'), isNull);
      expect(Node.fromShareLink('vless://uuid@host:70000'), isNull);
      expect(Node.fromShareLink('vmess://bm90LWpzb24='), isNull);
      expect(Node.fromShareLink('ss://bm90aGluZw=='), isNull);
    });

    test('IPv6 字面量：方括号剥掉，端口单独解析', () {
      final node = Node.fromShareLink('vless://uuid@[2001:db8::1]:443#v6');
      expect(node, isNotNull);
      expect(node!.host, '2001:db8::1');
      expect(node.port, 443);
    });

    test('parseLine 是 fromShareLink 的别名', () {
      const raw = 'vless://uuid@a.example.com:443#x';
      expect(Node.parseLine(raw)?.name, Node.fromShareLink(raw)?.name);
    });
  });

  group('Node.copyWith / withLatency', () {
    final base = Node(
      raw: 'vless://uuid@a.example.com:443#x',
      name: 'x',
      protocol: 'vless',
      host: 'a.example.com',
      port: 443,
    );

    test('copyWith 更新 latency，其他字段不变', () {
      final updated = base.copyWith(latencyMs: 42);
      expect(updated.latencyMs, 42);
      expect(updated.raw, base.raw);
      expect(updated.name, base.name);
      expect(updated.host, base.host);
      expect(updated.port, base.port);
      expect(base.latencyMs, isNull); // 原对象不动
    });

    test('copyWith(latencyMs: null) 保留原值（?? 语义）', () {
      final measured = base.copyWith(latencyMs: 42);
      expect(measured.copyWith(name: 'y').latencyMs, 42);
    });

    test('withLatency 可以显式清空', () {
      final measured = base.copyWith(latencyMs: 42);
      expect(measured.withLatency(null).latencyMs, isNull);
    });

    test('相等性按 raw+name（测速变化不影响选中态比较）', () {
      final a = base.copyWith(latencyMs: 10);
      final b = base.copyWith(latencyMs: 999);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == base.copyWith(name: 'y'), isFalse);
    });

    test('toString 便于日志排查', () {
      expect(base.toString(), 'Node(x, vless://a.example.com:443)');
    });
  });
}
