/// 站点内容配置（M7 用到的三个字段，来自 GET /api/site-config）。
///
/// 为什么不建完整 SiteConfig：M5/M8 并行开发中会各自定义站点配置模型，
/// 这里只取本模块需要的最小集合，避免同名类冲突。合并时可平移到统一模型。
class SiteContent {
  /// 站点名，用于邀请分享文案「一起用 {site_title}」。
  final String siteTitle;

  /// 公告正文；空串 = 没有公告。
  final String announcement;

  /// 外部反馈链接（TG 群 / 表单）；空串 = 站点未配置反馈入口。
  final String feedbackLink;

  /// 站点 Logo URL（后台「站点信息」配置）；空串 = 未配置，用默认图标。
  final String siteLogo;

  const SiteContent({
    required this.siteTitle,
    required this.announcement,
    required this.feedbackLink,
    this.siteLogo = '',
  });

  /// 公告是否可展示（纯空白视为无公告）。
  bool get hasAnnouncement => announcement.trim().isNotEmpty;

  /// 反馈入口是否可展示。
  bool get hasFeedbackLink => feedbackLink.trim().isNotEmpty;

  /// 是否配置了站点 Logo。
  bool get hasLogo => siteLogo.trim().isNotEmpty;

  /// site-config 所有值都是字符串，但历史站点可能混入 null，统一兜成空串。
  factory SiteContent.fromJson(Map<String, dynamic> json) {
    return SiteContent(
      siteTitle: _toStr(json['site_title']).trim(),
      announcement: _toStr(json['announcement']),
      feedbackLink: _toStr(json['feedback_link']).trim(),
      siteLogo: _toStr(json['site_logo']).trim(),
    );
  }

  /// 序列化（用于本地缓存 site-config，启动时先读缓存避免闪变）。
  Map<String, dynamic> toJson() => {
        'site_title': siteTitle,
        'announcement': announcement,
        'feedback_link': feedbackLink,
        'site_logo': siteLogo,
      };
}

String _toStr(dynamic v) => v is String ? v : (v == null ? '' : '$v');
