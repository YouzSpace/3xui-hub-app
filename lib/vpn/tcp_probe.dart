import 'dart:io';

/// TCP 握手测速（对齐 v2rayNG 的 tcping 模式 `socketConnectTime`）。
///
/// 直连节点 `host:port` 做一次 TCP 握手，返回握手耗时毫秒；
/// 失败（端口不通/服务器宕机/超时）返回 -1。域名由 [Socket.connect]
/// 自动解析，IPv6 字面量直接可用，异常一律按失败处理（不抛出）。
///
/// 相比「真延迟」（起 xray 进程发 HTTP 到 gstatic 测完整往返），
/// 这里只测客户端到节点的物理 TCP 延迟，数值更低、更快，但**不验证
/// 节点能否真正代理流量**（端口开着但协议配错也判可达）。
Future<int> tcpConnectTime(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  try {
    final sw = Stopwatch()..start();
    final socket = await Socket.connect(host, port, timeout: timeout);
    sw.stop();
    socket.destroy();
    return sw.elapsedMilliseconds;
  } catch (_) {
    return -1;
  }
}
