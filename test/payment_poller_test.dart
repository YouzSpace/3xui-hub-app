import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/models/order.dart';
import 'package:controlhub_app/features/payment/payment_poller.dart';

OrderStatusResult _status(String status) => OrderStatusResult.fromJson({
      'order_no': 'N1',
      'status': status,
      'amount': 19.9,
      'paid_at': status == 'paid' ? '2026-10-26T10:00:00+08:00' : null,
    });

void main() {
  group('轮询参数（T6.5 铁律：2s × 最多 30 次 = 60s）', () {
    test('默认间隔 2 秒、上限 30 次', () {
      expect(PaymentPoller.interval, const Duration(seconds: 2));
      expect(PaymentPoller.maxAttempts, 30);
      expect(
        PaymentPoller.interval * PaymentPoller.maxAttempts,
        const Duration(seconds: 60),
      );
    });
  });

  group('PaymentPoller 行为（注入 1ms 间隔加速）', () {
    PaymentPoller make(
      Future<OrderStatusResult> Function(String) query, {
      int maxAttempts = 30,
    }) =>
        PaymentPoller(
          query: query,
          pollInterval: const Duration(milliseconds: 1),
          pollMaxAttempts: maxAttempts,
        );

    test('1. 第一次就是 paid：立刻返回 paid，只查一次', () async {
      var calls = 0;
      final poller = make((_) async {
        calls++;
        return _status('paid');
      });
      final outcome = await poller.start('N1');
      expect(outcome, PaymentOutcome.paid);
      expect(calls, 1);
      expect(poller.isRunning, isFalse);
    });

    test('2. pending → pending → paid：第 3 次命中后停止', () async {
      var calls = 0;
      final poller = make((_) async {
        calls++;
        return _status(calls >= 3 ? 'paid' : 'pending');
      });
      final outcome = await poller.start('N1');
      expect(outcome, PaymentOutcome.paid);
      expect(calls, 3);
    });

    test('3. expired / cancelled → 立即返回 closed', () async {
      for (final closed in ['expired', 'cancelled']) {
        var calls = 0;
        final poller = make((_) async {
          calls++;
          return _status(closed);
        });
        expect(await poller.start('N1'), PaymentOutcome.closed);
        expect(calls, 1);
      }
    });

    test('4. 一直 pending → 查满上限后 timeout', () async {
      var calls = 0;
      final poller = make((_) async {
        calls++;
        return _status('pending');
      }, maxAttempts: 4);
      expect(await poller.start('N1'), PaymentOutcome.timeout);
      expect(calls, 4);
    });

    test('5. 网络异常继续重试，不提前放弃；之后的 paid 仍能命中', () async {
      var calls = 0;
      final poller = make((_) async {
        calls++;
        if (calls < 3) {
          throw const ApiException(ApiException.codeNetwork, '网络连接失败，请检查网络');
        }
        return _status('paid');
      });
      expect(await poller.start('N1'), PaymentOutcome.paid);
      expect(calls, 3);
    });

    test('6. 解析类/404 致命错误立即放弃（aborted），不空转 60 秒', () async {
      for (final code in [401, 404, ApiException.codeParse]) {
        var calls = 0;
        final poller = make((_) async {
          calls++;
          throw ApiException(code, 'x');
        });
        expect(await poller.start('N1'), PaymentOutcome.aborted);
        expect(calls, 1, reason: 'code=$code');
      }
    });

    test('7. 手动 stop() 后下一次 tick 返回 aborted', () async {
      final poller = make((_) async => _status('pending'));
      final future = poller.start('N1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      poller.stop();
      expect(await future, PaymentOutcome.aborted);
      expect(poller.isRunning, isFalse);
    });

    test('8. onTick 拿到每次结果与次数', () async {
      final ticks = <(int, String?)>[];
      var calls = 0;
      final poller = PaymentPoller(
        query: (_) async {
          calls++;
          return _status(calls >= 2 ? 'paid' : 'pending');
        },
        pollInterval: const Duration(milliseconds: 1),
        onTick: (attempt, result) => ticks.add((attempt, result?.status)),
      );
      await poller.start('N1');
      expect(ticks, [(1, 'pending'), (2, 'paid')]);
    });
  });
}
