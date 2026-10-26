import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/data/models/invite_info.dart';
import 'package:controlhub_app/data/models/site_content.dart';
import 'package:controlhub_app/data/models/tutorial.dart';
import 'package:controlhub_app/features/announcements/announcements_page.dart';
import 'package:controlhub_app/features/announcements/notice_detail_dialog.dart';
import 'package:controlhub_app/features/announcements/site_content_providers.dart';
import 'package:controlhub_app/features/invite/invite_page.dart';
import 'package:controlhub_app/features/invite/invite_providers.dart';
import 'package:controlhub_app/features/tutorials/tutorial_providers.dart';
import 'package:controlhub_app/features/tutorials/tutorials_page.dart';

/// 把单个页面塞进最小 MaterialApp + ProviderScope（override 掉仓库层）。
Widget _host(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: child),
  );
}

const _site = SiteContent(
  siteTitle: '柚子云',
  announcement: '10 月 26 日 02:00 维护，预计 30 分钟。\n维护期间节点会短暂中断。',
  feedbackLink: 'https://t.me/yuzi',
);

void main() {
  group('InvitePage（T7.1）', () {
    testWidgets('有邀请码：显示等宽码、人数、分享按钮', (tester) async {
      await tester.pumpWidget(_host(
        const InvitePage(),
        overrides: [
          inviteInfoProvider.overrideWith(() => _FakeInvite(const InviteInfo(
                code: 'ABC123',
                invitedCount: 3,
                redeemCodes: [],
              ))),
          siteContentProvider.overrideWith((ref) async => _site),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('我的邀请码'), findsOneWidget);
      expect(find.text('ABC123'), findsOneWidget);
      expect(find.text('已成功邀请 3 人'), findsOneWidget);
      expect(find.text('分享邀请'), findsOneWidget);
      // 无兑换码 → 空状态文案，而不是空白区。
      expect(find.text('暂无兑换码'), findsOneWidget);
    });

    testWidgets('邀请码为空：显示「暂无邀请码」+ 重试，且不给分享按钮', (tester) async {
      await tester.pumpWidget(_host(
        const InvitePage(),
        overrides: [
          inviteInfoProvider.overrideWith(() => _FakeInvite(const InviteInfo(
                code: '',
                invitedCount: 0,
                redeemCodes: [],
              ))),
          siteContentProvider.overrideWith((ref) async => _site),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('暂无邀请码'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
      expect(find.text('分享邀请'), findsNothing);
    });

    testWidgets('兑换码：折扣 badge + 状态 + 备注', (tester) async {
      await tester.pumpWidget(_host(
        const InvitePage(),
        overrides: [
          inviteInfoProvider.overrideWith(() => _FakeInvite(const InviteInfo(
                code: 'ABC123',
                invitedCount: 1,
                redeemCodes: [
                  RedeemCode(
                    code: 'RDM9OFF',
                    discount: 0.9,
                    note: '新人专享',
                    status: 'active',
                  ),
                  RedeemCode(code: 'RDMOLD', status: 'expired'),
                ],
              ))),
          siteContentProvider.overrideWith((ref) async => _site),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('我的兑换码'), findsOneWidget);
      expect(find.text('RDM9OFF'), findsOneWidget);
      expect(find.text('9折'), findsOneWidget);
      expect(find.text('新人专享'), findsOneWidget);
      expect(find.text('可用'), findsOneWidget);
      expect(find.text('已过期'), findsOneWidget);
      // Go 端不返回 discount 的码不显示假折扣。
      expect(find.text('10折'), findsNothing);
    });

    testWidgets('接口失败：展示 ApiException.message，不展示 toString', (tester) async {
      await tester.pumpWidget(_host(
        const InvitePage(),
        overrides: [
          inviteInfoProvider.overrideWith(_FailingInvite.new),
          siteContentProvider.overrideWith((ref) async => _site),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('邀请服务暂不可用'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);
    });
  });

  group('TutorialsPage（T7.2）', () {
    testWidgets('按分类分组渲染，两级标题都在', (tester) async {
      await tester.pumpWidget(_host(
        const TutorialsPage(),
        overrides: [
          tutorialsProvider.overrideWith(() => _FakeTutorials(const [
                Tutorial(
                  id: 1,
                  title: 'iOS 安装',
                  category: '客户端',
                  content: 'a',
                  createdAt: null,
                ),
                Tutorial(
                  id: 2,
                  title: '安卓安装',
                  category: '客户端',
                  content: 'b',
                  createdAt: null,
                ),
                Tutorial(
                  id: 3,
                  title: '套餐说明',
                  category: '入门',
                  content: 'c',
                  createdAt: null,
                ),
              ])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('客户端'), findsOneWidget);
      expect(find.text('入门'), findsOneWidget);
      expect(find.text('iOS 安装'), findsOneWidget);
      expect(find.text('安卓安装'), findsOneWidget);
      expect(find.text('套餐说明'), findsOneWidget);
    });

    testWidgets('空列表 → 空状态', (tester) async {
      await tester.pumpWidget(_host(
        const TutorialsPage(),
        overrides: [
          tutorialsProvider.overrideWith(() => _FakeTutorials(const [])),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('暂无教程'), findsOneWidget);
    });
  });

  group('AnnouncementsPage / NoticeDetailDialog（T7.5）', () {
    testWidgets('有公告 → 全文可读', (tester) async {
      await tester.pumpWidget(_host(
        const AnnouncementsPage(),
        overrides: [
          siteContentProvider.overrideWith((ref) async => _site),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('最新公告'), findsOneWidget);
      expect(find.textContaining('维护'), findsOneWidget);
    });

    testWidgets('无公告 → 「暂无公告」', (tester) async {
      await tester.pumpWidget(_host(
        const AnnouncementsPage(),
        overrides: [
          siteContentProvider.overrideWith(
            (ref) async => const SiteContent(
              siteTitle: 'x',
              announcement: '   ',
              feedbackLink: '',
            ),
          ),
        ],
      ));
      await tester.pumpAndSettle();

      expect(find.text('暂无公告'), findsOneWidget);
    });

    testWidgets('NoticeDetailDialog：标题「公告」+ 正文', (tester) async {
      await tester.pumpWidget(_host(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () =>
                    NoticeDetailDialog.show(context, '维护通知正文'),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('公告'), findsOneWidget);
      expect(find.text('维护通知正文'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);
    });

    testWidgets('NoticeBanner：首行摘要，点击开弹窗', (tester) async {
      await tester.pumpWidget(_host(
        Scaffold(body: NoticeBanner(announcement: _site.announcement)),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('维护'), findsOneWidget);
      await tester.tap(find.byType(NoticeBanner));
      await tester.pumpAndSettle();

      expect(find.text('公告'), findsOneWidget);
    });
  });
}

/// 固定返回邀请数据（不走网络）。
class _FakeInvite extends InviteNotifier {
  final InviteInfo value;

  _FakeInvite(this.value);

  @override
  Future<InviteInfo> build() async => value;
}

/// 固定抛错的邀请数据源。
class _FailingInvite extends InviteNotifier {
  @override
  Future<InviteInfo> build() async =>
      throw const ApiException(ApiException.codeParse, '邀请服务暂不可用');
}

class _FakeTutorials extends TutorialListNotifier {
  final List<Tutorial> value;

  _FakeTutorials(this.value);

  @override
  Future<List<Tutorial>> build() async => value;
}
