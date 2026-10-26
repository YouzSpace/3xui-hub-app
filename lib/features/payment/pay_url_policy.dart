/// 支付页导航白名单（T6.4 安全铁律）。
///
/// 规则（纯函数，单测覆盖）：
/// 1. 只允许加载 **payUrl 自己的域名及其子域**（https/http 同 scheme 家族都拦，
///    见 [allows] 的 http 处理）；
/// 2. 支付平台「跳回 App」的自定义 scheme（`alipays:` / `weixin:` 等）**不加载、
///    也不调起外部 App**，只作为「支付可能已完成」的信号让调用方去轮询；
/// 3. 其余一切（别的域名、`javascript:`、`data:`、`file:`、`intent:`）一律拦截。
///
/// 这里刻意不做「注册域名 / 公共后缀」推断：`example.com.cn` 用「取后两段」会被
/// 误判成整个 `com.cn`，等于把白名单放大成互联网。宁可严格 —— 跨域跳转被拦时
/// 用户仍可从支付页返回并由轮询确认到账（记录在交付的待拍板项里）。
library;

/// 支付完成后「跳回 App」的 scheme 前缀（小写，不含冒号）。
///
/// 命中这些 scheme 时视为支付平台已完成引导，关闭 WebView 进入轮询；
/// 绝不 `launchUrl`（那会把用户丢到外部 App，且可能构成一次意外的外部动作）。
const List<String> paymentReturnSchemes = <String>[
  'alipays',
  'alipay',
  'weixin',
  'wechat',
  'wechatpay',
  'uppay',
  'unionpay',
  'kaixin',
  'paypal',
];

/// 一次导航的判定结果。
enum NavigationVerdict {
  /// 允许在 WebView 内加载。
  allow,

  /// 支付平台跳回 App：关闭 WebView 并开始轮询。
  returnToApp,

  /// 拦截（不加载、也不外跳）。
  block,
}

/// 支付页导航策略。
class PayUrlPolicy {
  /// payUrl 的主机（小写，去掉默认端口）。
  final String payHost;

  /// 进入支付页时的原始 payUrl（用于「返回时仍在同一页」判断，展示用）。
  final String initialUrl;

  PayUrlPolicy._(this.payHost, this.initialUrl);

  /// 从 payUrl 构造；URL 非法时 [payHost] 为空串，此时只允许拦截
  /// （调用方应在此之前校验 payUrl，见 [isUsablePayUrl]）。
  factory PayUrlPolicy.fromPayUrl(String payUrl) {
    final uri = Uri.tryParse(payUrl);
    return PayUrlPolicy._(_lowerHost(uri), payUrl);
  }

  static String _lowerHost(Uri? uri) {
    if (uri == null) return '';
    final host = uri.host;
    return host.isEmpty ? '' : host.toLowerCase();
  }

  /// payUrl 本身是否可加载：必须是带主机的 http(s) 绝对地址。
  static bool isUsablePayUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  /// 判定一次导航请求（只对主框架导航生效，子资源由 WebView 自行加载）。
  NavigationVerdict check(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return NavigationVerdict.block;
    final scheme = uri.scheme.toLowerCase();

    // 2. 支付平台回跳：只认已知 scheme，且不加载、不外跳。
    if (scheme.isNotEmpty && scheme != 'http' && scheme != 'https') {
      return paymentReturnSchemes.contains(scheme)
          ? NavigationVerdict.returnToApp
          : NavigationVerdict.block;
    }

    // 1. 同域（或子域）才放行。
    final host = uri.host.toLowerCase();
    if (host.isEmpty || payHost.isEmpty) return NavigationVerdict.block;
    if (host == payHost || host.endsWith('.$payHost')) {
      return NavigationVerdict.allow;
    }
    return NavigationVerdict.block;
  }
}
