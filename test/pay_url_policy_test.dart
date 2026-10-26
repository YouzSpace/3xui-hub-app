import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/features/payment/pay_url_policy.dart';

void main() {
  group('PayUrlPolicy.isUsablePayUrl（建 WebView 前的硬校验）', () {
    test('http / https 绝对地址可用', () {
      expect(PayUrlPolicy.isUsablePayUrl('https://pay.example.com/submit'), isTrue);
      expect(PayUrlPolicy.isUsablePayUrl('http://pay.example.com:8080/s'), isTrue);
    });

    test('非 http(s) 或没有主机一律不可用', () {
      for (final url in [
        '',
        'not a url',
        '/relative/path',
        'javascript:alert(1)',
        'data:text/html,<b>x</b>',
        'file:///etc/passwd',
        'intent://pay#Intent;end',
        'alipays://platformapi/startapp',
        'https://',
      ]) {
        expect(PayUrlPolicy.isUsablePayUrl(url), isFalse, reason: url);
      }
    });
  });

  group('PayUrlPolicy.check（导航白名单）', () {
    late PayUrlPolicy policy;

    setUp(() {
      policy = PayUrlPolicy.fromPayUrl('https://Pay.Example.com/submit?id=1');
    });

    test('1. payUrl 同域放行（主域大小写不敏感）', () {
      expect(policy.check('https://pay.example.com/next'),
          NavigationVerdict.allow);
      expect(policy.check('http://pay.example.com/next'),
          NavigationVerdict.allow);
      expect(policy.check('https://PAY.EXAMPLE.COM/x'), NavigationVerdict.allow);
    });

    test('2. 子域放行（支付网关常把收银台放在 cdn/pay 子域）', () {
      expect(policy.check('https://cdn.pay.example.com/a'),
          NavigationVerdict.allow);
      expect(policy.check('https://a.b.pay.example.com/a'),
          NavigationVerdict.allow);
    });

    test('3. 其它域名一律拦截（不加载、不外跳）', () {
      for (final url in [
        'https://evil.com/pay',
        'https://pay.example.com.evil.com/pay', // 后缀伪装
        'https://evil-pay.example.com/pay',
        'https://example.com/pay', // 父域不在白名单
        'https://apple.com/app-store',
      ]) {
        expect(policy.check(url), NavigationVerdict.block, reason: url);
      }
    });

    test('4. 支付平台回跳 scheme → returnToApp（不加载该 URL）', () {
      const customs = [
        'alipays://platformapi/startapp?appId=20000067',
        'alipay://x',
        'weixin://wap/pay?prepayid=1',
        'wechatpay://x',
        'unionpay://x',
        'uppay://x',
        'paypal://x',
      ];
      for (final url in customs) {
        expect(policy.check(url), NavigationVerdict.returnToApp, reason: url);
      }
    });

    test('5. 其它 scheme / 危险 scheme 一律拦截（不发 Intent、不外跳）', () {
      for (final url in [
        'javascript:alert(document.cookie)',
        'data:text/html,hi',
        'file:///sdcard/x.html',
        'intent://scan/#Intent;scheme=zxing;end',
        'market://details?id=com.evil',
        'sms:10086',
        'tel:10086',
        'mailto:a@b.com',
        'ftp://pay.example.com/x',
        'content://com.evil/x',
      ]) {
        expect(policy.check(url), NavigationVerdict.block, reason: url);
      }
    });

    test('6. 无法解析的 URL 拦截', () {
      expect(policy.check(''), NavigationVerdict.block);
      expect(policy.check('http://'), NavigationVerdict.block);
    });

    test('7. payUrl 本身非法 → 全部拦截（fail closed）', () {
      final broken = PayUrlPolicy.fromPayUrl('javascript:alert(1)');
      expect(broken.check('https://pay.example.com/a'), NavigationVerdict.block);
      expect(broken.check('https://any.com/a'), NavigationVerdict.block);
    });

    test('8. 同域但带端口/查询/片段仍放行', () {
      expect(policy.check('https://pay.example.com:8443/a?b=1#c'),
          NavigationVerdict.allow);
    });
  });
}
