/// 教程正文的渲染方式判定（T7.3）。
///
/// 后端 content 可能是 HTML 片段，也可能是纯文本/Markdown，
/// 判定规则（任务书指定）：含 `<` 标签即按 HTML 交给 WebView，否则按纯文本渲染。
enum TutorialRenderMode { html, plainText }

/// 判断内容是否按 HTML 渲染。
///
/// 只认「像标签」的尖括号：`a < b` 这种数学比较不该被当成 HTML 送进 WebView，
/// 否则用户会看到一段被吃掉正文的白屏。所以要求 `<` 后面紧跟字母或 `/`。
bool looksLikeHtml(String content) {
  if (!content.contains('<')) return false;
  return RegExp(r'<\s*/?\s*[a-zA-Z][^>]*>').hasMatch(content);
}

TutorialRenderMode detectRenderMode(String content) =>
    looksLikeHtml(content) ? TutorialRenderMode.html : TutorialRenderMode.plainText;
