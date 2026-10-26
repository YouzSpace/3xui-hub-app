import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/data/models/node.dart';
import 'package:controlhub_app/vpn/vpn_state.dart';

Node _node() => Node(
      raw: 'vless://uuid@host:443?security=tls#节点A',
      name: '节点A',
      protocol: 'vless',
      host: 'host',
      port: 443,
    );

void main() {
  test('isBusy：preparing/connecting/disconnecting 为 true，其余 false', () {
    expect(const VpnState(status: VpnStatus.idle).isBusy, isFalse);
    expect(const VpnState(status: VpnStatus.preparing).isBusy, isTrue);
    expect(const VpnState(status: VpnStatus.connecting).isBusy, isTrue);
    expect(const VpnState(status: VpnStatus.disconnecting).isBusy, isTrue);
    expect(const VpnState(status: VpnStatus.connected).isBusy, isFalse);
    expect(const VpnState(status: VpnStatus.error).isBusy, isFalse);
  });

  test('默认态：idle / connectedFor 零 / 无节点 / 无错误', () {
    const s = VpnState();
    expect(s.status, VpnStatus.idle);
    expect(s.connectedFor, Duration.zero);
    expect(s.activeNode, isNull);
    expect(s.latencyMs, isNull);
    expect(s.errorMessage, isNull);
  });

  test('copyWith：未传字段保留旧值', () {
    const s = VpnState(status: VpnStatus.connecting);
    final s2 = s.copyWith(status: VpnStatus.connected, activeNode: _node());
    expect(s2.status, VpnStatus.connected);
    expect(s2.activeNode?.name, '节点A');
    expect(s2.connectedFor, Duration.zero);
  });

  test('状态机合法迁移：idle→preparing→connecting→connected→disconnecting→idle', () {
    var s = const VpnState();
    expect(s.status, VpnStatus.idle);

    s = s.copyWith(status: VpnStatus.preparing, activeNode: _node());
    s = s.copyWith(status: VpnStatus.connecting);
    s = s.copyWith(status: VpnStatus.connected, connectedFor: Duration.zero);
    expect(s.isBusy, isFalse);

    // 每秒 tick 累计。
    s = s.copyWith(connectedFor: s.connectedFor + const Duration(seconds: 3));
    expect(s.connectedFor, const Duration(seconds: 3));

    s = s.copyWith(status: VpnStatus.disconnecting);
    expect(s.isBusy, isTrue);
    s = const VpnState();
    expect(s.status, VpnStatus.idle);
  });

  test('失败迁移：preparing → error 携带中文文案，latency 保留', () {
    const s = VpnState(status: VpnStatus.preparing, latencyMs: 88);
    final err = s.copyWith(
      status: VpnStatus.error,
      errorMessage: '需要 VPN 权限才能连接',
    );
    expect(err.status, VpnStatus.error);
    expect(err.errorMessage, '需要 VPN 权限才能连接');
    expect(err.latencyMs, 88);
    expect(err.isBusy, isFalse);
  });

  test('相等性：同字段相等，status 或 node 不同则不等', () {
    final a = VpnState(activeNode: _node());
    final b = VpnState(activeNode: _node());
    expect(a, equals(b));
    expect(
      a,
      isNot(equals(a.copyWith(status: VpnStatus.connecting))),
    );
  });
}
