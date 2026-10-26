import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/models/user_profile.dart';

void main() {
  group('UserProfile.fromJson（T2.1 容错三例）', () {
    test('1. 正常值：全字段按 §3.3 契约解析', () {
      final p = UserProfile.fromJson(const {
        'id': 12,
        'email': 'a@b.com',
        'token': 'sub-token-abc',
        'protocol': 'vless',
        'plan_id': 2,
        'plan_type': 'period',
        'plan_name': '月付套餐',
        'plan_include_local': true,
        'plan_months': 1,
        'plan_price': 19.9,
        'plan_reset_price': 5,
        'traffic_limit': 0,
        'traffic_used': 12345678,
        'monthly_traffic_used': 1234567,
        'monthly_traffic_limit': 107374182400,
        'next_traffic_reset_at': '2026-11-25T00:00:00+08:00',
        'expired_at': '2026-11-25T00:00:00+08:00',
        'enabled': true,
      });
      expect(p.id, 12);
      expect(p.email, 'a@b.com');
      expect(p.token, 'sub-token-abc');
      expect(p.protocol, 'vless');
      expect(p.planId, 2);
      expect(p.planType, 'period');
      expect(p.planName, '月付套餐');
      expect(p.planIncludeLocal, isTrue);
      expect(p.planMonths, 1);
      expect(p.planPrice, 19.9);
      expect(p.planResetPrice, 5.0);
      expect(p.trafficLimit, 0);
      expect(p.trafficUsed, 12345678);
      expect(p.monthlyTrafficUsed, 1234567);
      expect(p.monthlyTrafficLimit, 107374182400);
      expect(p.nextTrafficResetAt, isNotNull);
      expect(p.expiredAt, isNotNull);
      expect(p.enabled, isTrue);
    });

    test('2. 全 null：数值归 0、字符串空、时间为 null、不抛异常', () {
      final p = UserProfile.fromJson(const {
        'id': 12,
        'email': null,
        'token': null,
        'protocol': null,
        'plan_id': null,
        'plan_type': null,
        'plan_name': null,
        'plan_include_local': null,
        'plan_months': null,
        'plan_price': null,
        'plan_reset_price': null,
        'traffic_limit': null,
        'traffic_used': null,
        'monthly_traffic_used': null,
        'monthly_traffic_limit': null,
        'next_traffic_reset_at': null,
        'expired_at': null,
        'enabled': null,
      });
      expect(p.email, '');
      expect(p.token, '');
      expect(p.protocol, '');
      expect(p.planId, 0);
      expect(p.planType, '');
      expect(p.planName, '');
      expect(p.planIncludeLocal, isFalse);
      expect(p.planMonths, 0);
      expect(p.planPrice, 0);
      expect(p.planResetPrice, 0);
      expect(p.trafficLimit, 0);
      expect(p.trafficUsed, 0);
      expect(p.monthlyTrafficUsed, 0);
      expect(p.monthlyTrafficLimit, 0);
      expect(p.nextTrafficResetAt, isNull);
      expect(p.expiredAt, isNull);
      expect(p.enabled, isTrue); // null 不当禁用。
    });

    test('3. 类型不一致：int/double/String 混排 + 非法时间串，容错不抛', () {
      final p = UserProfile.fromJson(const {
        'id': '12', // String 数字
        'email': 100, // 非字符串
        'token': 'sub-token',
        'protocol': 'vless',
        'plan_id': 2.0, // double
        'plan_months': '3', // String
        'plan_price': '19.9', // String
        'plan_include_local': 'true', // 非法 bool → false
        'traffic_limit': 'abc', // 非法数字 → 0
        'next_traffic_reset_at': 'not-a-date', // 非法时间 → null
        'expired_at': '2026-11-25T00:00:00+08:00',
      });
      expect(p.id, 12);
      expect(p.email, '');
      expect(p.planId, 2);
      expect(p.planMonths, 3);
      expect(p.planPrice, 19.9);
      expect(p.planIncludeLocal, isFalse);
      expect(p.trafficLimit, 0);
      expect(p.nextTrafficResetAt, isNull);
      expect(p.expiredAt, isNotNull);
    });

    test('缺 id：抛 codeParse（整包非法）', () {
      expect(
        () => UserProfile.fromJson(const {'email': 'a@b.com'}),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.codeParse)),
      );
    });
  });
}
