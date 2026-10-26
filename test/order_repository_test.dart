import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_client.dart';
import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/repositories/order_repository.dart';

/// 记录真实发出的请求，并按路径返回预设的 `{code,msg,data}`。
///
/// 用接口而不是继承 ApiClient（ApiClient 是单例、构造私有，且 dio 初始化
/// 需要平台依赖）—— 仓库只依赖 `request()` 这一个方法，注入 fake 足够。
class _RecordingClient implements ApiClient {
  _RecordingClient(this.handler);

  final Future<dynamic> Function(_Call call) handler;
  final List<_Call> requests = [];

  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? data,
    Map<String, dynamic>? query,
  }) async {
    final call = _Call(
      path: path,
      method: method,
      data: data,
      query: query,
    );
    requests.add(call);
    return handler(call);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// 一次被记录的请求。
class _Call {
  final String path;
  final String method;
  final Map<String, dynamic>? data;
  final Map<String, dynamic>? query;

  const _Call({
    required this.path,
    required this.method,
    this.data,
    this.query,
  });
}

void main() {
  group('OrderRepository.createOrder 请求参数（对齐 Go handler）', () {
    test('1. 只传 plan_id：请求体不出现 payment_config_id / discount_code', () async {
      final client = _RecordingClient((_) async => {
            'order_no': 'N1',
            'amount': 19.9,
            'status': 'pending',
            'pay_url': 'https://pay.example.com/x',
          });
      final repo = OrderRepository(client: client);

      final result = await repo.createOrder(planId: 11);

      final req = client.requests.single;
      expect(req.path, '/api/payment/create');
      expect(req.method, 'POST');
      expect(req.data, {'plan_id': 11});
      expect(result.orderNo, 'N1');
    });

    test('2. 带支付方式：字段名是 payment_config_id（不是 method_id）', () async {
      final client = _RecordingClient((_) async => {
            'order_no': 'N2',
            'amount': 19.9,
            'status': 'pending',
            'pay_url': 'https://pay.example.com/x',
          });
      final repo = OrderRepository(client: client);

      await repo.createOrder(planId: 11, methodId: 3);

      final data = client.requests.single.data!;
      expect(data['payment_config_id'], 3);
      expect(data.containsKey('method_id'), isFalse);
    });

    test('3. 优惠码去空白后按 discount_code 传；空串不传', () async {
      final client = _RecordingClient((_) async => {
            'order_no': 'N3',
            'amount': 17.91,
            'status': 'pending',
            'pay_url': 'https://pay.example.com/x',
          });
      final repo = OrderRepository(client: client);

      await repo.createOrder(planId: 11, discountCode: '  SAVE10  ');
      expect(client.requests.last.data!['discount_code'], 'SAVE10');

      await repo.createOrder(planId: 11, discountCode: '   ');
      expect(client.requests.last.data!.containsKey('discount_code'), isFalse);

      // methodId 传 0 视为「未选择」，不下发该字段。
      await repo.createOrder(planId: 11, methodId: 0);
      expect(
        client.requests.last.data!.containsKey('payment_config_id'),
        isFalse,
      );
    });
  });

  group('OrderRepository 查询', () {
    test('queryStatus 走 GET + order_no 查询参数', () async {
      final client = _RecordingClient((_) async => {
            'order_no': 'N1',
            'status': 'paid',
            'amount': 19.9,
            'paid_at': '2026-10-26T10:00:00+08:00',
          });
      final repo = OrderRepository(client: client);

      final status = await repo.queryStatus('N1');

      expect(client.requests.single.method, 'GET');
      expect(client.requests.single.query, {'order_no': 'N1'});
      expect(status.isPaid, isTrue);
    });

    test('retryPay 走 POST + order_no', () async {
      final client = _RecordingClient((_) async => {
            'order_no': 'N1',
            'pay_url': 'https://pay.example.com/retry',
          });
      final repo = OrderRepository(client: client);

      final result = await repo.retryPay('N1');

      expect(client.requests.single.path, '/api/payment/retry');
      expect(client.requests.single.data, {'order_no': 'N1'});
      expect(result.payUrl, 'https://pay.example.com/retry');
    });

    test('fetchMethods / fetchOrders 解析列表', () async {
      final client = _RecordingClient((options) async {
        if (options.path == '/api/payment/methods') {
          return [
            {'id': 1, 'name': '支付宝', 'bank_code': 'alipay'},
          ];
        }
        return [
          {
            'order_no': 'A1',
            'plan_id': 2,
            'plan_name': '月付',
            'order_type': 'plan',
            'amount': 19.9,
            'status': 'pending',
            'paid_at': null,
            'created_at': '2026-10-26T09:58:00+08:00',
          },
        ];
      });
      final repo = OrderRepository(client: client);

      expect((await repo.fetchMethods()).single.name, '支付宝');
      expect((await repo.fetchOrders()).single.canRetry, isTrue);
    });

    test('结构异常收敛成 ApiException(codeParse)，不泄露 Dart 异常', () async {
      final client = _RecordingClient((_) async => 'not-a-list');
      final repo = OrderRepository(client: client);
      await expectLater(
        repo.fetchOrders(),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.codeParse)),
      );
    });
  });

  group('OrderRepository.checkDiscount 归一化', () {
    test('正常返回 usable 结果并带 plan_id', () async {
      final client = _RecordingClient((_) async => {
            'usable': true,
            'discount': 0.9,
            'final_amount': 17.91,
            'note': '',
            'message': '优惠码可用',
          });
      final repo = OrderRepository(client: client);

      final result = await repo.checkDiscount(' CD90 ', 11);

      expect(client.requests.single.data, {'code': 'CD90', 'plan_id': 11});
      expect(result.usable, isTrue);
      expect(result.finalAmount!.text, '17.91');
    });

    test('后端抛 400（Go 口径）→ 返回 usable=false，不向上抛', () async {
      final client = _RecordingClient((_) async {
        throw const ApiException(400, '优惠码无效或不可用');
      });
      final repo = OrderRepository(client: client);

      final result = await repo.checkDiscount('BAD', 11);

      expect(result.usable, isFalse);
      expect(result.message, '优惠码无效或不可用');
      expect(result.hasFinalAmount, isFalse);
    });

    test('429 限流原样上抛（UI 要走「频繁输码」分支）', () async {
      final client = _RecordingClient((_) async {
        throw const ApiException(429, '操作过于频繁，请 10 分钟后再试');
      });
      final repo = OrderRepository(client: client);

      await expectLater(
        repo.checkDiscount('BAD', 11),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 429)),
      );
    });
  });
}
