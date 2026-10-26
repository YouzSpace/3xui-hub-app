/// 邀请分享文案（T7.1 指定句式，纯函数便于单测）。
///
/// 句式：「注册填写邀请码 {CODE}，一起用 {site_title}」。
/// 站点名取不到时用「本服务」占位，避免出现「一起用 」这种断句。
String inviteShareText({required String code, required String siteTitle}) {
  final title = siteTitle.trim();
  return '注册填写邀请码 $code，一起用 ${title.isEmpty ? '本服务' : title}';
}
