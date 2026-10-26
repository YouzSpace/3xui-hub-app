import 'package:flutter_test/flutter_test.dart';

import 'package:controlhub_app/core/network/api_exception.dart';
import 'package:controlhub_app/features/tutorials/tutorial_content.dart';
import 'package:controlhub_app/features/tutorials/tutorial_grouping.dart';
import 'package:controlhub_app/data/models/tutorial.dart';

void main() {

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
