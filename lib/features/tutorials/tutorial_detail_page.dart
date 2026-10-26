import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/tutorial.dart';
import 'tutorial_content.dart';
import 'tutorial_providers.dart';

/// 教程详情（T7.3）。
///
/// content 含 HTML 标签 → WebView（JavaScriptMode.disabled，纯展示）；
/// 否则按纯文本渲染并保留换行。
class TutorialDetailPage extends ConsumerWidget {
  final int id;

  const TutorialDetailPage({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(tutorialDetailProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(detail.valueOrNull?.title ?? '教程详情')),
      body: detail.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(Sp.base),
          child: SkeletonList(count: 2),
        ),
        error: (e, _) => ErrorView(
          message: tutorialErrorText(e),
          onRetry: () => ref.invalidate(tutorialDetailProvider(id)),
        ),
        data: (tutorial) => _TutorialBody(tutorial: tutorial),
      ),
    );
  }
}

class _TutorialBody extends StatelessWidget {
  final Tutorial tutorial;

  const _TutorialBody({required this.tutorial});

  @override
  Widget build(BuildContext context) {
    final mode = detectRenderMode(tutorial.content);
    switch (mode) {
      case TutorialRenderMode.html:
        return _HtmlContent(html: tutorial.content);
      case TutorialRenderMode.plainText:
        return _PlainContent(text: tutorial.content);
    }
  }
}

/// HTML 正文：WebView 只做展示。
///
/// 安全边界（prompt.md「教程 WebView 用 JavaScriptMode.disabled」）：
/// - 关闭 JS，后端内容里的 `<script>` 不会执行
/// - 禁止导航离开初始文档，防止被诱导跳出到外部页面
class _HtmlContent extends StatefulWidget {
  final String html;

  const _HtmlContent({required this.html});

  @override
  State<_HtmlContent> createState() => _HtmlContentState();
}

class _HtmlContentState extends State<_HtmlContent> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.disabled)
      ..setNavigationDelegate(
        NavigationDelegate(
          // 只允许内联文档自身的加载（about:/data:/blob:）；
          // 正文里的外链一律拦住 —— 教程只用于展示，不该变成浏览器。
          onNavigationRequest: (request) {
            final scheme = Uri.tryParse(request.url)?.scheme ?? '';
            final inline = scheme == 'about' || scheme == 'data' || scheme == 'blob';
            return inline ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
        ),
      )
      ..loadHtmlString(_wrapHtml(widget.html));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      // WebView 背景独立于 Flutter 主题，用页面底色兜住加载瞬间的白闪。
      color: cs.surface,
      child: WebViewWidget(controller: _controller),
    );
  }
}

/// 给后端 HTML 补一层文档外壳：视口自适应 + 跟随深浅色的基础排版。
///
/// 不注入任何脚本（JS 已关闭，注入了也不执行），只加 meta/CSS。
String _wrapHtml(String body) {
  final css = '''
    :root { color-scheme: light dark; }
    body {
      margin: 0; padding: 16px;
      font-family: -apple-system, "Noto Sans CJK SC", "PingFang SC", sans-serif;
      font-size: 16px; line-height: 1.6;
      color: #1B1B1F; background: #FDFBFF;
      word-wrap: break-word;
    }
    @media (prefers-color-scheme: dark) {
      body { color: #E6E1E9; background: #141218; }
      a { color: #D0BCFF; }
    }
    img, video, table { max-width: 100%; height: auto; }
    pre { overflow-x: auto; }
    img { display: block; }
  ''';
  return '''
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>$css</style>
</head>
<body>$body</body>
</html>
''';
}

/// 纯文本正文：保留换行与空白，可选中复制。
class _PlainContent extends StatelessWidget {
  final String text;

  const _PlainContent({required this.text});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Sp.base),
      child: SizedBox(
        width: double.infinity,
        child: SelectableText(
          text,
          style: textTheme.bodyLarge?.copyWith(height: 1.7),
        ),
      ),
    );
  }
}
