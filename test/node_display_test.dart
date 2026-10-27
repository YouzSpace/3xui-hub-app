import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/features/nodes/node_display.dart';

Node _node(String name) => Node(
      raw: 'vless://uuid@hk.example.com:443#$name',
      name: name,
      protocol: 'vless',
      host: 'hk.example.com',
      port: 443,
    );

void main() {
  group('displayNodeName（emoji 过滤）', () {
    test('国旗 + 中文：只剥 emoji，保留文字', () {
      expect(displayNodeName(_node('🇭🇰 香港 01')), '香港 01');
      expect(displayNodeName(_node('🇯🇵 东京 02')), '东京 02');
    });

    test('emoji 夹在中间 / 结尾也剥干净，空白收拢', () {
      expect(displayNodeName(_node('香港 🇭🇰 01')), '香港 01');
      expect(displayNodeName(_node('香港01 🚀')), '香港01');
      expect(displayNodeName(_node('🎌   日本   🇯🇵')), '日本');
    });

    test('纯 emoji 节点名 → 用 host:port 兜底', () {
      expect(displayNodeName(_node('🇭🇰')), 'hk.example.com:443');
      expect(displayNodeName(_node('🏳️‍🌈')), 'hk.example.com:443');
    });

    test('无 emoji 的名字原样返回', () {
      expect(displayNodeName(_node('US-01')), 'US-01');
      expect(displayNodeName(_node('香港 01')), '香港 01');
    });

    test('全角空格同样收拢', () {
      expect(displayNodeName(_node('香港　　01')), '香港 01');
    });
  });

  group('displayNodeSubtitle / latencyLabel', () {
    test('第二行是「协议 · host:port」', () {
      expect(displayNodeSubtitle(_node('x')), 'VLESS · hk.example.com:443');
    });

    test('延迟文案：未测速 —，超时显示超时，已测速带单位', () {
      expect(latencyLabel(null), '—');
      expect(latencyLabel(-1), '超时');
      expect(latencyLabel(0), '0 ms');
      expect(latencyLabel(123), '123 ms');
    });

    test('延迟无障碍文案分档', () {
      expect(latencySemantics(null), '未测速');
      expect(latencySemantics(-1), '测速超时');
      expect(latencySemantics(50), contains('良好'));
      expect(latencySemantics(150), contains('一般'));
      expect(latencySemantics(300), contains('较差'));
    });
  });
}
