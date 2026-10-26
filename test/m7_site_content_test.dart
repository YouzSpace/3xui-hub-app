import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/data/models/site_content.dart';
import 'package:controlhub_app/features/feedback/feedback_launcher.dart';

void main() {
  group('SiteContent.fromJson（site-config 全是字符串）', () {
    test('正常值：三个字段取出并 trim 链接/标题', () {
      final c = SiteContent.fromJson(const {
        'site_title': ' 柚子云 ',
        'announcement': '10 月 26 日维护通知',
        'feedback_link': ' https://t.me/yuzi ',
      });
      expect(c.siteTitle, '柚子云');
      expect(c.hasAnnouncement, isTrue);
      expect(c.announcement, contains('维护'));
      expect(c.hasFeedbackLink, isTrue);
      expect(c.feedbackLink, 'https://t.me/yuzi');
    });

    test('空串 / null：两个入口都不显示，不抛异常', () {
      final c = SiteContent.fromJson(const {
        'site_title': null,
        'announcement': '',
        'feedback_link': null,
      });
      expect(c.siteTitle, '');
      expect(c.hasAnnouncement, isFalse);
      expect(c.hasFeedbackLink, isFalse);
    });

    test('纯空白公告视为没有公告', () {
      final c = SiteContent.fromJson(const {
        'announcement': '   \n  ',
      });
      expect(c.hasAnnouncement, isFalse);
    });

    test('数字等非字符串安全转成字符串', () {
      final c = SiteContent.fromJson(const {
        'site_title': 123,
        'feedback_link': 0,
      });
      expect(c.siteTitle, '123');
    });
  });

  group('resolveFeedbackUri（T7.4 只放行 http/https）', () {
    test('正常 https 链接', () {
      expect(resolveFeedbackUri('https://t.me/abc')?.host, 't.me');
      expect(resolveFeedbackUri('http://example.com/f')?.scheme, 'http');
    });

    test('首尾空白被忽略', () {
      expect(resolveFeedbackUri('  https://a.b  ')?.toString(), 'https://a.b');
    });

    test('空串 / 非法 scheme 一律拒绝', () {
      expect(resolveFeedbackUri(''), isNull);
      expect(resolveFeedbackUri('   '), isNull);
      expect(resolveFeedbackUri('file:///etc/passwd'), isNull);
      expect(resolveFeedbackUri('intent://x#Intent;end'), isNull);
      expect(resolveFeedbackUri('javascript:alert(1)'), isNull);
    });
  });
}
