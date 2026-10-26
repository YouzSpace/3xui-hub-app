import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/models/invite_info.dart';
import 'package:controlhub_app/features/invite/invite_share.dart';
import 'package:controlhub_app/features/tutorials/tutorial_content.dart';
import 'package:controlhub_app/features/tutorials/tutorial_grouping.dart';
import 'package:controlhub_app/data/models/tutorial.dart';

void main() {
  group('InviteInfo.fromJson（T7.1 Go 契约）', () {
    test('Go 形态：invite_code / invited_count / redeem_codes[{code,status}]', () {
      final info = InviteInfo.fromJson(const {
        'invite_code': 'ABC123',
        'invited_count': 3,
        'redeem_codes': [
          {'code': 'RDM1', 'status': 'active'},
          {'code': 'RDM2', 'status': 'expired'},
        ],
      });
      expect(info.code, 'ABC123');
      expect(info.hasCode, isTrue);
      expect(info.invitedCount, 3);
      expect(info.redeemCodes.length, 2);
      expect(info.redeemCodes.first.code, 'RDM1');
      // Go 端不返回 discount/note，解析出来必须是 null 而不是 0/空串。
      expect(info.redeemCodes.first.discount, isNull);
      expect(info.redeemCodes.first.note, isNull);
    });

    test('老 PHP 形态：嵌套 invite.code 也能解析', () {
      final info = InviteInfo.fromJson(const {
        'invite': {'code': 'NESTED9'},
        'invited_count': 1,
        'redeem_codes': [
          {
            'code': 'R9',
            'discount': 0.9,
            'note': '新人券',
            'status': 'active',
            'expires_at': '2026-12-01T00:00:00+08:00',
          },
        ],
      });
      expect(info.code, 'NESTED9');
      final r = info.redeemCodes.single;
      expect(r.discountLabel, '9折');
      expect(r.note, '新人券');
      expect(r.expiresAt, isNotNull);
    });

    test('邀请码未生成：invite_code 缺失 → hasCode=false，不抛异常', () {
      final info = InviteInfo.fromJson(const {
        'invited_count': 0,
        'redeem_codes': [],
      });
      expect(info.hasCode, isFalse);
      expect(info.code, '');
      expect(info.redeemCodes, isEmpty);
    });

    test('全部字段为 null：数值归 0、列表为空', () {
      final info = InviteInfo.fromJson(const {
        'invite_code': null,
        'invited_count': null,
        'redeem_codes': null,
      });
      expect(info.code, '');
      expect(info.invitedCount, 0);
      expect(info.redeemCodes, isEmpty);
    });

    test('兑换码坏行跳过，不影响好行', () {
      final info = InviteInfo.fromJson(const {
        'invite_code': 'X',
        'redeem_codes': [
          {'code': ''},
          'not-a-map',
          {'code': 'GOOD', 'status': 'used_up'},
        ],
      });
      expect(info.redeemCodes.length, 1);
      expect(info.redeemCodes.single.code, 'GOOD');
    });

    test('整包不是对象 → 抛 codeParse', () {
      expect(
        () => parseInviteInfo('oops'),
        throwsA(isA<ApiException>()
            .having((e) => e.code, 'code', ApiException.codeParse)),
      );
    });
  });

  group('redeemStatusLabel（T7.1 状态口径）', () {
    test('四种后端状态', () {
      expect(redeemStatusLabel('active'), '可用');
      expect(redeemStatusLabel('used_up'), '已用完');
      expect(redeemStatusLabel('expired'), '已过期');
      expect(redeemStatusLabel('refreshed'), '已刷新');
    });

    test('未知状态原样返回，空状态显示「未知」', () {
      expect(redeemStatusLabel('weird'), 'weird');
      expect(redeemStatusLabel(''), '未知');
    });
  });

  group('RedeemCode.discountLabel（折扣显示）', () {
    RedeemCode make(double? d) =>
        RedeemCode(code: 'C', discount: d, status: 'active');

    test('0.9 → 9折，0.85 → 8.5折', () {
      expect(make(0.9).discountLabel, '9折');
      expect(make(0.85).discountLabel, '8.5折');
    });

    test('无折扣 / 非法折扣值 → null', () {
      expect(make(null).discountLabel, isNull);
      expect(make(0).discountLabel, isNull);
      expect(make(1).discountLabel, isNull);
    });
  });

  group('inviteShareText（T7.1 分享文案）', () {
    test('标准句式', () {
      expect(
        inviteShareText(code: 'ABC123', siteTitle: '柚子云'),
        '注册填写邀请码 ABC123，一起用 柚子云',
      );
    });

    test('站点名为空 → 用「本服务」兜底，不留断句', () {
      expect(
        inviteShareText(code: 'ABC123', siteTitle: '   '),
        '注册填写邀请码 ABC123，一起用 本服务',
      );
    });
  });

  group('Tutorial.fromJson（T7.2/T7.3）', () {
    test('列表项：全字段', () {
      final t = Tutorial.fromJson(const {
        'id': 7,
        'title': 'iOS 配置',
        'category': '客户端',
        'content': '<p>hi</p>',
        'created_at': '2026-07-01T15:42:57.000000Z',
      });
      expect(t.id, 7);
      expect(t.title, 'iOS 配置');
      expect(t.category, '客户端');
      expect(t.content, '<p>hi</p>');
      expect(t.createdAt, isNotNull);
    });

    test('详情无 category → 归入「默认」', () {
      final t = Tutorial.fromJson(const {
        'id': 8,
        'title': 'x',
        'content': 'y',
        'created_at': null,
      });
      expect(t.category, '默认');
      expect(t.createdAt, isNull);
    });

    test('缺 id → 抛 codeParse', () {
      expect(
        () => Tutorial.fromJson(const {'title': 'x'}),
        throwsA(isA<ApiException>()),
      );
    });

    test('listFromJson 跳过坏行，整包非数组才抛', () {
      final list = Tutorial.listFromJson([
        {'id': 1, 'title': 'a', 'category': 'A', 'content': ''},
        {'title': 'no-id'},
        42,
        {'id': 2, 'title': 'b', 'category': '', 'content': ''},
      ]);
      expect(list.length, 2);
      expect(list.last.category, '默认');
      expect(
        () => Tutorial.listFromJson({'code': 0}),
        throwsA(isA<ApiException>()),
      );
    });
  });

  group('groupTutorials（T7.2 分组逻辑）', () {
    Tutorial t(int id, String category) => Tutorial(
          id: id,
          title: 'T$id',
          category: category,
          content: '',
          createdAt: null,
        );

    test('按首次出现顺序分组，组内保持原顺序', () {
      final groups = groupTutorials([
        t(1, '客户端'),
        t(2, '入门'),
        t(3, '客户端'),
        t(4, '进阶'),
      ]);
      expect(groups.map((g) => g.category).toList(), ['客户端', '入门', '进阶']);
      expect(groups.first.items.map((e) => e.id).toList(), [1, 3]);
      expect(groups[1].items.single.id, 2);
    });

    test('空列表 → 空分组', () {
      expect(groupTutorials(const []), isEmpty);
    });

    test('分类名空白 → 归入「默认」且不产生重复组', () {
      final groups = groupTutorials([t(1, '  '), t(2, '默认')]);
      expect(groups.length, 1);
      expect(groups.single.category, '默认');
      expect(groups.single.items.length, 2);
    });
  });

  group('detectRenderMode（T7.3 HTML/纯文本判定）', () {
    test('含 HTML 标签 → WebView', () {
      expect(detectRenderMode('<p>hello</p>'), TutorialRenderMode.html);
      expect(detectRenderMode('text<br/>more'), TutorialRenderMode.html);
      expect(detectRenderMode('<div class="a">x</div>'), TutorialRenderMode.html);
    });

    test('纯文本 / Markdown → 纯文本渲染', () {
      expect(detectRenderMode('第一行\n第二行'), TutorialRenderMode.plainText);
      expect(detectRenderMode('# 标题\n- 列表'), TutorialRenderMode.plainText);
    });

    test('数学比较号不算标签（避免把正文送进 WebView 后白屏）', () {
      expect(looksLikeHtml('当 a < b 时'), isFalse);
      expect(looksLikeHtml('1 < 2 > 0'), isFalse);
    });

    test('空内容 → 纯文本', () {
      expect(detectRenderMode(''), TutorialRenderMode.plainText);
    });
  });
}
