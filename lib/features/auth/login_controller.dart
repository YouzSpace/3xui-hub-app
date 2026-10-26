import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../providers/auth_providers.dart';

/// 登录提交动作（T2.4）。UI 只发事件：拿到 `ApiException?`，
/// null = 成功（守卫随即跳 /home），非 null 展示 `e.message`。
///
/// token 写盘在 repository；这里把返回的 token 同步进 [tokenProvider]，
/// 内存态一变路由守卫就跳转。
///
/// autoDispose：离开登录页自动释放。
final loginControllerProvider = Provider.autoDispose<LoginActions>(
  (ref) => LoginActions(ref),
);

class LoginActions {
  LoginActions(this._ref);

  final Ref _ref;

  bool _submitting = false;

  /// 是否提交中（按钮 loading 态）。
  bool get submitting => _submitting;

  /// 邮箱登录。
  Future<ApiException?> loginByEmail(String email, String password) =>
      _run(() =>
          _ref.read(authRepositoryProvider).loginByEmail(email, password));

  /// 订阅 token 登录。
  Future<ApiException?> loginByToken(String token) =>
      _run(() => _ref.read(authRepositoryProvider).loginByToken(token.trim()));

  Future<ApiException?> _run(Future<String> Function() action) async {
    if (_submitting) return null; // 按钮 loading 态已禁用，正常不会重入。
    _submitting = true;
    try {
      final token = await action();
      await _ref.read(tokenProvider.notifier).login(token);
      return null;
    } on ApiException catch (e) {
      return e;
    } catch (_) {
      return const ApiException(ApiException.codeParse, '登录失败，请稍后重试');
    } finally {
      _submitting = false;
    }
  }
}
