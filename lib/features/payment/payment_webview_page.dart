import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/spacing.dart';
import '../../core/ui/state_views.dart';
import '../../data/models/money.dart';
import '../../providers/auth_providers.dart';
import '../plans/plans_provider.dart';
import '../plans/plans_routes.dart';
import 'pay_url_policy.dart';
import 'payment_poller.dart';

/// 支付页入参。
class PaymentPageArgs {
  final String orderNo;
  final String payUrl;
  final Money amount;

  const PaymentPageArgs({
    required this.orderNo,
    required this.payUrl,
    required this.amount,
  });
}

/// 支付页（T6.4 + T6.5）。
///
/// 生命周期：
/// 1. 加载 payUrl（只允许同域 + 支付平台回跳 scheme，见 [PayUrlPolicy]）；
/// 2. 主框架加载失败（HTTP 错误 / 资源错误）→ [ErrorView] + 重试；
/// 3. 用户点关闭、或支付平台跳回自定义 scheme、或加载成功后用户按返回
///    → 关闭 WebView 并开始轮询状态；
/// 4. 轮询（2s × 最多 30 次）：paid → 刷新 userProvider + 提示 + 回首页；
///    expired/cancelled → 提示订单已关闭；超时 → 提示去订单记录。
///
/// **安全铁律**：不注入 JS（不调 `runJavaScript`）、不读页面内容、不放行外部域名。
/// WebView 只负责把支付平台的收银台显示出来，到账与否一律以后端
/// `GET /api/payment/status` 为准 —— 页面里的一切都不可信。
class PaymentWebviewPage extends ConsumerStatefulWidget {
  /// 深链直达时（没有 extra）为 null。
  final PaymentPageArgs? args;

  const PaymentWebviewPage({super.key, this.args});

  @override
  ConsumerState<PaymentWebviewPage> createState() => _PaymentWebviewPageState();
}

class _PaymentWebviewPageState extends ConsumerState<PaymentWebviewPage> {
  WebViewController? _controller;
  PayUrlPolicy? _policy;

  /// 首屏是否还在加载（顶部 LinearProgressIndicator）。
  bool _loading = true;

  /// 页面是否已经成功渲染过（决定「关闭时是否要轮询」）。
  bool _pageLoaded = false;

  /// 加载失败原因（非空时整页显示 ErrorView）。
  String? _loadError;

  /// 是否已经进入「确认支付结果」阶段（WebView 已关闭，显示轮询态）。
  bool _checking = false;

  /// 轮询进度文案（`正在确认支付结果…（12/30）`）。
  String _pollingHint = '正在确认支付结果…';

  PaymentPoller? _poller;

  /// 防止 `_finish` 被重复触发（关闭按钮 + 系统返回 + 回跳 scheme）。
  bool _finishing = false;

  /// `didChangeDependencies` 会因主题/媒体变化被多次调用，用这个闸门只建一次。
  bool _controllerBuilt = false;

  /// 被允许作为主框架加载过的 URL（判断 HTTP 错误是不是「支付页本身打不开」）。
  final Set<String> _mainFrameUrls = {};

  @override
  void initState() {
    super.initState();
    final args = widget.args;
    if (args == null || !PayUrlPolicy.isUsablePayUrl(args.payUrl)) {
      // 深链直达或后端给了非 http(s) 的 payUrl：不建 WebView，直接报错。
      _loadError =
          args == null ? '订单参数缺失，请返回套餐页重新下单' : '支付地址无效，请返回重新下单';
      _loading = false;
      return;
    }
    _policy = PayUrlPolicy.fromPayUrl(args.payUrl);
    _mainFrameUrls.add(args.payUrl);
    // 注意：控制器必须在 didChangeDependencies 里建 ——
    // 这里若读 Theme.of(context) 会触发
    // 「dependOnInheritedWidgetOfExactType was called before initState completed」断言。
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controllerBuilt || _policy == null) return;
    _controllerBuilt = true;
    final args = widget.args!;
    _controller = WebViewController()
      // 不注入 JS：支付平台页面按自身需要执行脚本，App 侧不 eval、不读页面内容。
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Theme.of(context).colorScheme.surface)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: (progress) {
            if (!mounted) return;
            if (progress == 100) {
              setState(() => _loading = false);
            } else if (!_pageLoaded) {
              setState(() => _loading = true);
            }
          },
          onPageFinished: (_) {
            if (!mounted) return;
            setState(() {
              _loading = false;
              _pageLoaded = true;
              _loadError = null;
            });
          },
          onWebResourceError: (error) {
            // 主框架错误才算「支付页打不开」；图片/统计脚本等子资源失败不打扰用户。
            if (!mounted) return;
            if (error.isForMainFrame != true) return;
            setState(() {
              _loading = false;
              _loadError = _describeLoadError(error);
            });
          },
          onHttpError: (error) {
            if (!mounted) return;
            final status = error.response?.statusCode ?? 0;
            if (status < 400) return;
            // onHttpError 不带 isForMainFrame，只能按 URL 判断：
            // 只有「我们自己导航过的支付页地址」出错才整页报错，
            // 否则一张 404 的图片/Banner 会把好端端的收银台换成错误页。
            final failed = error.response?.uri?.toString() ?? '';
            if (!_mainFrameUrls.contains(failed)) return;
            setState(() {
              _loading = false;
              _loadError = '支付页加载失败（HTTP $status），请重试';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(args.payUrl));
  }

  @override
  void dispose() {
    _poller?.stop();
    super.dispose();
  }

  String _describeLoadError(WebResourceError error) {
    switch (error.errorType) {
      case WebResourceErrorType.connect:
      case WebResourceErrorType.hostLookup:
        return '无法连接支付服务器，请检查网络后重试';
      case WebResourceErrorType.timeout:
        return '支付页加载超时，请重试';
      case WebResourceErrorType.failedSslHandshake:
        return '支付页证书校验失败，请重试';
      default:
        // 不把平台原始 description 直接给用户（可能是英文栈信息）。
        return '支付页加载失败，请重试';
    }
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    // 只接管主框架导航；iframe / 子资源交给 WebView。
    if (!request.isMainFrame) return NavigationDecision.navigate;
    final verdict = _policy?.check(request.url) ?? NavigationVerdict.block;
    switch (verdict) {
      case NavigationVerdict.allow:
        _mainFrameUrls.add(request.url);
        return NavigationDecision.navigate;
      case NavigationVerdict.returnToApp:
        // 支付平台已把用户引导回 App：不加载该 scheme，直接进入到账确认。
        _finish();
        return NavigationDecision.prevent;
      case NavigationVerdict.block:
        // 别的域名（广告、客服、跳 App 商店…）：不加载、也不外跳。
        return NavigationDecision.prevent;
    }
  }

  /// 关闭 WebView 并开始轮询；已是确认态则直接返回。
  ///
  /// 两个入口共用：用户点关闭 / 按返回，以及支付平台跳回自定义 scheme。
  Future<void> _finish() async {
    if (_finishing || !mounted) return;
    _finishing = true;

    if (!_pageLoaded) {
      // 页面根本没打开过 → 不存在「已付款」的可能，直接离开，不浪费 60 秒。
      _leave(PaymentOutcome.aborted);
      return;
    }

    // 把 router/messenger 提前取出并交给轮询回调：用户可能在确认态按返回键
    // 离开页面，那时 `context` 已失效，但「到账了要提示 + 刷新套餐」仍然必须发生
    // （钱已经付了，不能因为没有页面就静默吞掉结果）。
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _checking = true;
      _pollingHint = '正在确认支付结果…';
    });

    final outcome = await _runPoller();
    await _handleOutcome(outcome, router: router, messenger: messenger);
  }

  /// 离开支付页（已确认 / 用户放弃）。
  ///
  /// 优先 pop（保住返回栈上原本的页面），兜底 go 套餐页 —— 直接深链进
  /// `/payment` 时栈里没有上一页，pop 会失败。用 `canPop` 判断，避免先试后抛。
  void _leave(PaymentOutcome outcome) {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop(outcome);
    } else {
      router.go(PlansRoutes.plans);
    }
  }

  Future<PaymentOutcome> _runPoller() async {
    final args = widget.args!;
    final poller = PaymentPoller(
      query: (orderNo) => ref.read(orderRepositoryProvider).queryStatus(orderNo),
      onTick: (attempt, result) {
        if (!mounted) return;
        setState(() {
          _pollingHint = result == null
              ? '网络波动，正在重试…（$attempt/${PaymentPoller.maxAttempts}）'
              : '正在确认支付结果…（$attempt/${PaymentPoller.maxAttempts}）';
        });
      },
    );
    _poller = poller;
    return poller.start(args.orderNo);
  }

  /// 处理轮询结果。
  ///
  /// [router]/[messenger] 由调用方在建轮询前捕获，因此本方法可以在页面已经被
  /// 返回键关掉（`mounted == false`）之后继续安全执行。
  Future<void> _handleOutcome(
    PaymentOutcome outcome, {
    required GoRouter router,
    required ScaffoldMessengerState messenger,
  }) async {
    switch (outcome) {
      case PaymentOutcome.paid:
        // 到账：刷新用户套餐（首页/我的会跟着变），提示后回首页。
        await ref.read(userProvider.notifier).refresh();
        ref.invalidate(plansProvider);
        ref.invalidate(ordersProvider);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(content: Text('支付成功，套餐已到账')));
        router.go('/home');
      case PaymentOutcome.timeout:
        ref.invalidate(ordersProvider);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('支付结果确认中，可在订单记录查看')),
          );
        // 直接落到订单记录（订单页 AppBar 有返回首页的口子）。
        router.go(PlansRoutes.orders);
      case PaymentOutcome.closed:
        ref.invalidate(ordersProvider);
        if (!mounted) {
          // 页面已被返回键关掉：用一个提示告诉用户「这单不用再等了」。
          messenger.showSnackBar(const SnackBar(content: Text('订单已关闭')));
          return;
        }
        final reorder = await _showClosedDialog();
        // 「重新下单」回套餐页挑套餐；「知道了」退回上一页。
        if (reorder) {
          router.go(PlansRoutes.plans);
        } else if (router.canPop()) {
          router.pop(PaymentOutcome.closed);
        } else {
          router.go(PlansRoutes.plans);
        }
      case PaymentOutcome.aborted:
        _leave(PaymentOutcome.aborted);
    }
  }

  /// 订单已关闭：返回 true = 用户选择「重新下单」。
  Future<bool> _showClosedDialog() async {
    final reorder = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('订单已关闭'),
        content: const Text('这笔订单已过期或被取消，需要重新下单。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('重新下单'),
          ),
        ],
      ),
    );
    return reorder ?? false;
  }

  /// 关闭按钮：支付可能已完成，先二次确认。
  Future<void> _confirmClose() async {
    if (_checking) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('离开支付'),
        content: const Text('支付还没完成，确定离开？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('继续支付'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确定离开'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      await _finish();
    }
  }

  void _retryLoad() {
    final args = widget.args;
    if (args == null) return;
    setState(() {
      _loadError = null;
      _loading = true;
      _finishing = false;
    });
    _mainFrameUrls.add(args.payUrl);
    _controller?.loadRequest(Uri.parse(args.payUrl));
  }

  @override
  Widget build(BuildContext context) {
    final args = widget.args;
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      // 确认阶段不允许返回键打断轮询；WebView 阶段交给 AppBar 关闭按钮
      // （返回键同样走「二次确认」，见 onPopInvoked）。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_checking) return;
        _confirmClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('支付'),
          leading: IconButton(
            tooltip: '关闭',
            icon: const Icon(Icons.close),
            onPressed: _checking ? null : _confirmClose,
          ),
          bottom: _loading && _loadError == null
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: _buildBody(args, cs),
      ),
    );
  }

  Widget _buildBody(PaymentPageArgs? args, ColorScheme cs) {
    if (_checking) {
      return _CheckingView(
        amount: args?.amount,
        orderNo: args?.orderNo ?? '',
        hint: _pollingHint,
      );
    }
    if (_loadError != null) {
      return ErrorView(message: _loadError!, onRetry: _retryLoad);
    }
    final controller = _controller;
    if (controller == null) {
      // 兜底（正常路径已在上面的 _loadError 处理）：同样不走共享 EmptyView。
      return Center(
        child: Text(
          '支付地址不可用',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return WebViewWidget(controller: controller);
  }
}

/// 确认态：转圈 + 金额 + 订单号 + 进度文案。
class _CheckingView extends StatelessWidget {
  final Money? amount;
  final String orderNo;
  final String hint;

  const _CheckingView({
    required this.amount,
    required this.orderNo,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Sp.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: Sp.lg),
            Text('正在确认支付结果', style: textTheme.titleMedium),
            const SizedBox(height: Sp.sm),
            if (amount != null && !amount!.isZero)
              Text(
                amount!.display,
                style: textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            const SizedBox(height: Sp.sm),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (orderNo.isNotEmpty) ...[
              const SizedBox(height: Sp.xs),
              Text(
                '订单号 $orderNo',
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
