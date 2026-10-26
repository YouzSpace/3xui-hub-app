import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/models/order.dart';
import 'package:controlhub_app/data/models/pay_method.dart';
import 'package:controlhub_app/data/models/plan.dart';

void main() {
  group('Plan.fromJson（T6.1，契约取自 handler.go:handlePlans）', () {
    test('1. 正常月付套餐全字段', () {
      final p = Plan.fromJson(const {
        'id': 1,
        'name': '月付',
        'price': 19.9,
        'type': 'period',
        'months': 1,
        'monthly_traffic': 107374182400,
        'period_traffic': 0,
        'total_traffic': 0,
        'include_local': true,
        'third_party_sub_ids': <int>[],
      });
      expect(p.id, 1);
      expect(p.name, '月付');
      expect(p.price.cents, 1990);
      expect(p.type, 'period');
      expect(p.months, 1);
      expect(p.monthlyTraffic, 107374182400);
      expect(p.includeLocal, isTrue);
      expect(p.isPeriod, isTrue);
      expect(p.isPureThirdParty, isFalse);
      expect(p.priceUnitLabel, '/月');
      expect(p.typeChipLabel, '月付');
    });

    test('2. 实测纯第三方套餐：total_traffic 为 null（不能当 0 处理成字段缺失）', () {
      final p = Plan.fromJson(const {
        'id': 113,
        'name': '节点',
        'price': 0,
        'type': 'period',
        'months': 1,
        'monthly_traffic': 0,
        'period_traffic': 0,
        'total_traffic': null,
        'include_local': false,
        'third_party_sub_ids': <int>[5],
      });
      expect(p.totalTraffic, isNull);
      expect(p.monthlyTraffic, 0);
      expect(p.includeLocal, isFalse);
      expect(p.isPureThirdParty, isTrue);
      expect(p.price.isZero, isTrue);
    });

    test('3. 全 null：数值归 0/null、字符串空、include_local 缺省 true', () {
      final p = Plan.fromJson(const {
        'id': 7,
        'name': null,
        'price': null,
        'type': null,
        'months': null,
        'monthly_traffic': null,
        'period_traffic': null,
        'total_traffic': null,
        'include_local': null,
        'third_party_sub_ids': null,
      });
      expect(p.name, '');
      expect(p.price.cents, 0);
      expect(p.type, '');
      expect(p.months, 0);
      expect(p.monthlyTraffic, isNull);
      expect(p.thirdPartySubIds, isEmpty);
      // (bool)($p->include_local ?? true) —— 缺省视为含本地节点。
      expect(p.includeLocal, isTrue);
    });

    test('4. 类型混排：String 数字 / double / 非字符串', () {
      final p = Plan.fromJson(const {
        'id': '7',
        'name': 100,
        'price': '4.90',
        'type': 'total',
        'months': '3',
        'monthly_traffic': '1024',
        'total_traffic': 2048.0,
        'include_local': false,
        'third_party_sub_ids': ['5', 6, null, 'x'],
      });
      expect(p.id, 7);
      expect(p.name, '');
      expect(p.price.cents, 490);
      expect(p.months, 3);
      expect(p.monthlyTraffic, 1024);
      expect(p.totalTraffic, 2048);
      expect(p.includeLocal, isFalse);
      expect(p.thirdPartySubIds, [5, 6]);
      expect(p.isPeriod, isFalse);
      expect(p.priceUnitLabel, '一次性');
      expect(p.typeChipLabel, '总量');
    });

    test('5. 缺 id → 抛 codeParse（整包非法）', () {
      expect(
        () => Plan.fromJson(const {'name': '月付', 'price': 19.9}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.codeParse)),
      );
    });

    test('6. 列表解析：非数组抛 codeParse，坏元素也抛（不静默吞）', () {
      expect(
        () => Plan.listFromJson({'id': 1}),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => Plan.listFromJson([
          {'id': 1, 'name': 'a', 'price': 1},
          'oops',
        ]),
        throwsA(isA<ApiException>()),
      );
      final list = Plan.listFromJson([
        {'id': 1, 'name': 'a', 'price': 1, 'type': 'period', 'months': 1},
      ]);
      expect(list.single.id, 1);
    });

    test('周期/总量/多月 的展示派生', () {
      Plan make({String type = 'period', int months = 1, num price = 30}) =>
          Plan.fromJson({
            'id': 1,
            'name': 'x',
            'price': price,
            'type': type,
            'months': months,
          });
      expect(make(months: 3).priceUnitLabel, '/季');
      expect(make(months: 12).priceUnitLabel, '/年');
      expect(make(months: 6).priceUnitLabel, '/6个月');
      expect(make(months: 6).typeChipLabel, '6 个月');
      expect(make(months: 3, price: 30).monthlyEquivalent.text, '10.00');
      expect(make(type: 'total').monthlyEquivalent.text, '30.00');
    });
  });

  group('PayMethod / CreateOrderResult', () {
    test('支付方式解析（只有 id/name/bank_code）', () {
      final m = PayMethod.fromJson(const {
        'id': 2,
        'name': '支付宝',
        'bank_code': 'alipay',
      });
      expect(m.id, 2);
      expect(m.name, '支付宝');
      expect(m.bankCode, 'alipay');
    });

    test('支付方式缺 id 抛 codeParse，bank_code 缺省空串', () {
      expect(
        () => PayMethod.fromJson(const {'name': 'x'}),
        throwsA(isA<ApiException>()),
      );
      final m = PayMethod.fromJson(const {'id': 1, 'name': 'x'});
      expect(m.bankCode, '');
    });

    test('下单结果：正常 / 免费套餐 pay_url=null', () {
      final r = CreateOrderResult.fromJson(const {
        'order_no': 'CH20261026001',
        'amount': 88.65,
        'status': 'pending',
        'pay_url': 'https://pay.example.com/submit?x=1',
      });
      expect(r.orderNo, 'CH20261026001');
      expect(r.amount.text, '88.65');
      expect(r.status, 'pending');
      expect(r.payUrl, 'https://pay.example.com/submit?x=1');
      expect(r.isPaid, isFalse);

      final free = CreateOrderResult.fromJson(const {
        'order_no': 'CH20261026002',
        'amount': 0,
        'status': 'paid',
        'pay_url': null,
      });
      expect(free.isPaid, isTrue);
      expect(free.payUrl, isNull);
    });

    test('下单结果空 pay_url 归一成 null（后端 nullIfEmpty 的等价处理）', () {
      final r = CreateOrderResult.fromJson(const {
        'order_no': 'N1',
        'amount': 1,
        'status': 'pending',
        'pay_url': '',
      });
      expect(r.payUrl, isNull);
    });

    test('下单结果缺 order_no 抛 codeParse', () {
      expect(
        () => CreateOrderResult.fromJson(const {'amount': 1, 'status': 'paid'}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('Order / 状态', () {
    test('订单列表解析：plan_id 与 paid_at 可空', () {
      final orders = Order.listFromJson([
        {
          'order_no': 'A1',
          'plan_id': 2,
          'plan_name': '月付',
          'order_type': 'plan',
          'amount': 19.9,
          'status': 'paid',
          'paid_at': '2026-10-26T10:00:00+08:00',
          'created_at': '2026-10-26T09:58:00+08:00',
        },
        {
          'order_no': 'A2',
          'plan_id': null,
          'plan_name': '代理 · 香港',
          'order_type': 'proxy',
          'amount': 5,
          'status': 'pending',
          'paid_at': null,
          'created_at': '2026-10-26T09:59:00+08:00',
        },
      ]);
      expect(orders.length, 2);
      expect(orders[0].isPaid, isTrue);
      expect(orders[0].canRetry, isFalse);
      expect(orders[0].paidAt, isNotNull);
      expect(orders[1].planId, isNull);
      expect(orders[1].paidAt, isNull);
      expect(orders[1].canRetry, isTrue);
      expect(orders[1].statusLabel, '待支付');
    });

    test('状态徽章文案', () {
      expect(OrderStatus.label('paid'), '已支付');
      expect(OrderStatus.label('pending'), '待支付');
      expect(OrderStatus.label('expired'), '已关闭');
      expect(OrderStatus.label('cancelled'), '已取消');
      expect(OrderStatus.label(''), '未知');
    });

    test('状态查询：isPaid / isClosed', () {
      OrderStatusResult make(String status) => OrderStatusResult.fromJson({
            'order_no': 'A1',
            'status': status,
            'amount': 19.9,
            'paid_at': status == 'paid' ? '2026-10-26T10:00:00+08:00' : null,
          });
      expect(make('paid').isPaid, isTrue);
      expect(make('paid').isClosed, isFalse);
      expect(make('pending').isPaid, isFalse);
      expect(make('pending').isClosed, isFalse);
      expect(make('expired').isClosed, isTrue);
      expect(make('cancelled').isClosed, isTrue);
    });

    test('续付结果：缺 pay_url 抛 codeParse', () {
      expect(
        () => RetryPayResult.fromJson(const {'order_no': 'A1', 'pay_url': ''}),
        throwsA(isA<ApiException>()),
      );
      final ok = RetryPayResult.fromJson(
          const {'order_no': 'A1', 'pay_url': 'https://p/x'});
      expect(ok.payUrl, 'https://p/x');
    });
  });

  group('DiscountResult（兼容 PHP 完整结构 与 Go 精简结构）', () {
    test('PHP/Web 完整结构：usable + discount + final_amount + note', () {
      final r = DiscountResult.fromJson(const {
        'usable': true,
        'discount': 0.9,
        'final_amount': 88.65,
        'note': '新人专享',
        'message': '优惠码可用',
      });
      expect(r.usable, isTrue);
      expect(r.rate, 0.9);
      expect(r.finalAmount!.text, '88.65');
      expect(r.note, '新人专享');
      expect(r.message, '优惠码可用');
      expect(r.hasFinalAmount, isTrue);
    });

    test('PHP 失败结构：usable=false + message，且没有折后价', () {
      final r = DiscountResult.fromJson(const {
        'usable': false,
        'discount': null,
        'final_amount': null,
        'note': null,
        'message': '优惠码无效或不可用',
      });
      expect(r.usable, isFalse);
      expect(r.hasFinalAmount, isFalse);
      expect(r.message, '优惠码无效或不可用');
    });

    test('Go 精简结构 {valid, code}：usable 兜底取 valid，折后价未知', () {
      final r = DiscountResult.fromJson(const {'valid': true, 'code': 'ABC'});
      expect(r.usable, isTrue);
      expect(r.hasFinalAmount, isFalse); // 不能假装知道折后价
      expect(r.finalAmount, isNull);
      expect(r.rate, isNull);
    });

    test('Go 精简结构里 valid=false', () {
      final r = DiscountResult.fromJson(const {'valid': false});
      expect(r.usable, isFalse);
    });

    test('discount 为字符串也能解析', () {
      final r = DiscountResult.fromJson(const {
        'usable': true,
        'discount': '0.85',
        'final_amount': '84.15',
      });
      expect(r.rate, 0.85);
      expect(r.finalAmount!.text, '84.15');
    });

    test('DiscountResult.invalid 是失败结果', () {
      final r = DiscountResult.invalid('优惠码无效或不可用');
      expect(r.usable, isFalse);
      expect(r.hasFinalAmount, isFalse);
      expect(r.message, '优惠码无效或不可用');
    });
  });
}
