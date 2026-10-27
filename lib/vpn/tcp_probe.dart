import 'dart:io';

/// TCP 握手预检（对齐 v2rayNG `SpeedtestManager.socketConnectTime`）。
///
/// 测速前先用短超时 TCP 握手连节点 `host:port`：连不上说明端口不通或
/// 服务器宕机，直接判失败，省去为死节点单独起一个 xray 进程的开销
/// （起内核约 60MB 内存 + 握手失败，是批量测速里最慢的失败路径）。
///
/// 返回 true 表示 TCP 可达。域名由 [Socket.connect] 自动解析，
/// IPv6 字面量直接可用。异常一律按不可达处理（不抛出）。
Future<bool> tcpReachable(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  try {
    final socket = await Socket.connect(host, port, timeout: timeout);
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}
