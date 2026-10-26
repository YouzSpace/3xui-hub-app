import 'package:url_launcher/url_launcher.dart';

/// 反馈外链（T7.4 / proposal F14）。
///
/// 后端没有工单系统，反馈一律走 site-config.feedback_link 外链
/// （TG 群 / 表单），用系统浏览器打开，不在 App 内嵌 WebView。

/// 把后台配置的链接解析成可打开的外部地址；不合法返回 null。
///
/// 只放行 http/https：feedback_link 是后台配置项，不能让它变成
/// 任意 scheme（file:// / intent:// / javascript:）的跳板。
Uri? resolveFeedbackUri(String link) {
  final trimmed = link.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}

/// 打开反馈链接。返回 true = 已交给外部 App；false = 打不开。
///
/// 调用方（[FeedbackEntry]）负责把 false 变成「无法打开链接」提示。
Future<bool> openFeedbackLink(String link) async {
  final uri = resolveFeedbackUri(link);
  if (uri == null) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    // 没有可处理该 scheme 的 App / 平台通道异常，一律按打不开处理。
    return false;
  }
}
