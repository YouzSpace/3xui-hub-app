import 'dart:async';

import '../../core/network/api_exception.dart';
import '../../data/models/order.dart';

/// 支付结果（支付页 push 返回值，套餐页据此决定提示与缓存失效）。
enum PaymentOutcome {
  /// 已到账（`status == paid`）。
  paid,

  /// 60 秒内没确认（订单仍可能稍后到账）。
  timeout,

  /// 订单已关闭（`expired` / `cancelled`），只能重新下单。
  closed,

  /// 用户主动离开且没有确认到账。
  aborted,
}

/// 支付状态轮询器（T6.5）。
///
/// 铁律（tasks/06_purchase.md）：**间隔 2 秒、最多 30 次（60 秒）**。
/// - `paid` → 立即停止；
/// - `expired` / `cancelled` → 立即停止（继续等没有意义）；
/// - 网络/服务异常 → 继续重试，不提前放弃（付款方已扣款，宁可多等）；
/// - 超时 → 返回 timeout，由 UI 引导去订单记录。
///
/// 抽成独立类而不是写在页面里：生命周期清晰（[stop] 幂等），也好单测。
class PaymentPoller {
  /// 轮询间隔（铁律 2s）。
  static const Duration interval = Duration(seconds: 2);

  /// 最多查询次数（30 次 × 2s = 60s）。
  static const int maxAttempts = 30;

  final Future<OrderStatusResult> Function(String orderNo) _query;

  int _attempts = 0;
  bool _stopped = false;

  /// 每轮结束（成功或失败）都会回调，UI 可用来展示「确认中…」文案。
  final void Function(int attempt, OrderStatusResult? result)? onTick;

  /// 实际使用的间隔与上限：默认就是上面的铁律常量；
  /// 命名参数在单测里注入更短的值，避免「验证 30 次上限」要真跑 60 秒。
  final Duration pollInterval;
  final int pollMaxAttempts;

  PaymentPoller({
    required this._query,
    this.onTick,
    this.pollInterval = PaymentPoller.interval,
    this.pollMaxAttempts = PaymentPoller.maxAttempts,
  });

  /// 立即查一次，然后每 [pollInterval] 查一次，直到 paid/closed/超时。
  ///
  /// 先立即查一次而不是等 2 秒：WebView 关闭时用户往往已经在支付页完成付款，
  /// 第一次就能命中，少等 2 秒体验差别很明显。
  Future<PaymentOutcome> start(String orderNo) {
    final completer = Completer<PaymentOutcome>();
    void finish(PaymentOutcome outcome) {
      if (!completer.isCompleted) completer.complete(outcome);
    }

    // 阶段 1：查询（可能有一次重入保护，避免 stop() 后仍写 completer）。
    Future<void> queryPhase() async {
      if (_stopped) return finish(PaymentOutcome.aborted);
      _attempts++;
      OrderStatusResult? result;
      try {
        result = await _query(orderNo);
      } on ApiException catch (e) {
        // 订单不存在 / 登录过期 / 解析失败这类确定性错误：再等 60 秒也不会有结果。
        if (_isFatal(e)) {
          stop();
          return finish(PaymentOutcome.aborted);
        }
        // 网络波动：本轮算失败，继续下一轮（用户可能已付款，宁可多等）。
      } catch (_) {
        // 解析异常同样按「本轮失败」处理。
      }
      if (_stopped) return finish(PaymentOutcome.aborted);

      onTick?.call(_attempts, result);
      if (result != null) {
        if (result.isPaid) {
          stop();
          return finish(PaymentOutcome.paid);
        }
        if (result.isClosed) {
          stop();
          return finish(PaymentOutcome.closed);
        }
      }
      if (_attempts >= pollMaxAttempts) {
        stop();
        return finish(PaymentOutcome.timeout);
      }
      // 阶段 2：等一个间隔再进入下一次查询。
      // 用 Future.delayed 而不是 Timer 句柄：stop() 只需要把 _stopped 置位，
      // 等待中的延迟会在到期后直接以 aborted 收尾（线程安全、无需取消追踪）。
      await Future<void>.delayed(pollInterval);
      await queryPhase();
    }

    // 用微任务起跑，保证调用方先拿到 completer.future（不会同步完成）。
    scheduleMicrotask(queryPhase);
    return completer.future;
  }

  /// 停止轮询（幂等；页面 dispose 必须调用）。
  ///
  /// 正在 `await` 的那一轮会在返回后看到 `_stopped` 并立刻以 aborted 收尾，
  /// 不会再发起新的查询。
  void stop() {
    _stopped = true;
  }

  /// 是否还会继续查询（UI 用来判断要不要显示「确认中」）。
  bool get isRunning => !_stopped;

  /// 已查询次数（测试与调试用）。
  int get attempts => _attempts;

  /// 只有「确定查不出结果」的错误才提前放弃：
  /// 401 登录过期（前端会跳登录）、404 订单不存在、-2 解析失败。
  static bool _isFatal(ApiException e) {
    if (e.code == 401 || e.code == 404) return true;
    return e.code == ApiException.codeParse;
  }
}
