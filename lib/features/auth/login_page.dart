import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/spacing.dart';
import '../../core/ui/motion.dart';
import '../../core/utils/validators.dart';
import '../../providers/auth_providers.dart';
import '../announcements/site_content_providers.dart';
import 'login_controller.dart';

/// 登录页（T2.4）：logo/站点名 + 邮箱密码 + 登录 + 订阅链接登录。
/// 布局严格按 tasks/02_auth.md T2.4 的间距表。
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  int _cooldownLeft = 0;
  bool _expiredShown = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  /// 401 被踢回登录页：弹一次「登录已过期」（T2.5）。
  void _showExpiredIfNeeded() {
    if (_expiredShown) return;
    if (!ref.read(sessionExpiredProvider)) return;
    _expiredShown = true;
    // 状态重置必须放到 build 之后：build 期间同步改 provider 会触发
    // Riverpod「modify provider while building」异常（切站点后 token 失效 401 即踩中）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(sessionExpiredProvider.notifier).state = false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('登录已过期，请重新登录')),
      );
    });
  }

  bool get _cooling => _cooldownLeft > 0;

  Future<void> _submit() async {
    if (_submitting || _cooling) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    final err = await ref.read(loginControllerProvider).loginByEmail(
          _emailCtrl.text.trim(),
          _pwdCtrl.text,
        );
    if (!mounted) return;
    setState(() => _submitting = false);
    _handleResult(err);
  }

  Future<void> _submitToken() async {
    final token = _tokenCtrl.text.trim();
    if (!isValidToken(token)) return;
    Navigator.of(context).pop(); // 关对话框
    setState(() => _submitting = true);
    final err = await ref.read(loginControllerProvider).loginByToken(token);
    if (!mounted) return;
    setState(() => _submitting = false);
    _handleResult(err);
  }

  void _handleResult(ApiException? err) {
    if (err == null) return; // 成功：守卫自动跳 /home。
    if (err.code == 429) {
      _startCooldown();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(err.message)),
    );
  }

  /// 429：按钮禁用 60 秒倒计时（T2.4）。
  void _startCooldown() {
    setState(() => _cooldownLeft = 60);
    Future.doWhile(() async {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() => _cooldownLeft -= 1);
      return _cooldownLeft > 0;
    });
  }

  String? _validateEmail(String? v) =>
      isValidEmail(v) ? null : '请输入正确的邮箱地址';

  String? _validatePassword(String? v) =>
      isValidPassword(v) ? null : '请输入密码';

  @override
  Widget build(BuildContext context) {
    _showExpiredIfNeeded();
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final site = ref.watch(siteContentProvider).valueOrNull;
    final siteTitle = (site?.siteTitle ?? '').trim();
    final siteLogo = (site?.siteLogo ?? '').trim();
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: Sp.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 96),
                if (siteLogo.isEmpty)
                  Icon(Icons.shield, size: 64, color: cs.primary)
                else
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: CachedNetworkImage(
                        imageUrl: siteLogo,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) =>
                            Icon(Icons.shield, size: 64, color: cs.primary),
                      ),
                    ),
                  ),
                const SizedBox(height: Sp.base),
                Text(siteTitle,
                    textAlign: TextAlign.center,
                    style: text.headlineMedium),
                const SizedBox(height: Sp.sm),
                Text('登录后开始使用', textAlign: TextAlign.center,
                    style: text.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: Sp.xl),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  validator: _validateEmail,
                  enabled: !_submitting && !_cooling,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                const SizedBox(height: Sp.base),
                TextFormField(
                  controller: _pwdCtrl,
                  obscureText: _obscure,
                  textInputAction: TextInputAction.done,
                  validator: _validatePassword,
                  enabled: !_submitting && !_cooling,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: '密码',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: Sp.lg),
                _LoginButton(
                  submitting: _submitting,
                  cooldownLeft: _cooldownLeft,
                  onPressed: _submit,
                ),
                const SizedBox(height: Sp.base),
                TextButton(
                  onPressed: _submitting ? null : _showTokenDialog,
                  child: const Text('用订阅链接登录'),
                ),
                SizedBox(height: Sp.lg + Sp.xs),
                Text(
                  'v1.0.0',
                  textAlign: TextAlign.center,
                  style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 订阅链接登录对话框（extraLarge 圆角 28dp，design-tokens §9）。
  void _showTokenDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        title: const Text('用订阅链接登录'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('在网站个人中心复制订阅链接里的 token',
                style: Theme.of(dialogContext)
                    .textTheme
                    .bodySmall
                    ?.copyWith(
                        color: Theme.of(dialogContext)
                            .colorScheme
                            .onSurfaceVariant)),
            const SizedBox(height: Sp.md),
            TextField(
              controller: _tokenCtrl,
              autofocus: true,
              maxLines: 3,
              minLines: 1,
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
              decoration: const InputDecoration(
                labelText: '订阅 token',
                hintText: '粘贴订阅链接末尾的 token',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: _submitToken,
            child: const Text('登录'),
          ),
        ],
      ),
    );
  }
}

/// 登录按钮：loading / 429 倒计时两态（lg 高度、撑满宽度）。
class _LoginButton extends StatelessWidget {
  final bool submitting;
  final int cooldownLeft;
  final VoidCallback onPressed;

  const _LoginButton({
    required this.submitting,
    required this.cooldownLeft,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = submitting || cooldownLeft > 0;
    final label = cooldownLeft > 0
        ? '请 $cooldownLeft 秒后重试'
        : '登录';
    return AnimatedOpacity(
      duration: Motion.small,
      curve: Motion.easeOut,
      opacity: disabled ? 0.85 : 1,
      child: FilledButton(
        onPressed: disabled ? null : onPressed,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        child: submitting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(label),
      ),
    );
  }
}
