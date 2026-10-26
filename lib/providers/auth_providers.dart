import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../core/storage/token_store.dart';
import '../data/models/user_profile.dart';
import '../data/repositories/auth_repository.dart';

/// 全局容器：main() 里先建、先用、再交给 UncontrolledProviderScope，
/// 保证 runApp 前就能完成 token 回填（GoRouter 首次 redirect 拿到持久化值）。
final ProviderContainer providerContainer = ProviderContainer();

/// 仓库 Provider：测试时可 override 注入 mock。
final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository());

/// access_token 状态（T2.3）：内存同步持有，TokenStore 是持久层。
///
/// 写入口只有 [TokenNotifier.setToken]：null 即登出（清 TokenStore），
/// 登录写 TokenStore；保证内存与磁盘永远一致。
final tokenProvider = NotifierProvider<TokenNotifier, String?>(
  TokenNotifier.new,
);

class TokenNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  /// 启动回填（不经 setToken，避免重复写盘）。
  void restore(String token) => state = token;

  /// 登录：写 TokenStore 并更新内存。
  Future<void> login(String token) async {
    await TokenStore.write(token);
    state = token;
  }

  /// 登出 / 401：清 TokenStore 并更新内存。
  Future<void> clear() async {
    await TokenStore.clear();
    state = null;
  }
}

/// 启动时调用一次：从 TokenStore 读出 token 回填 [tokenProvider]。
///
/// main() 里 await 完成再 runApp；读失败不阻塞启动（视为未登录）。
Future<void> initTokenState() async {
  try {
    final token = await TokenStore.read();
    if (token != null && token.isNotEmpty) {
      providerContainer.read(tokenProvider.notifier).restore(token);
    }
  } catch (_) {
    // secure storage 读失败：按未登录处理，用户重新登录即可。
  }
}

/// 会话是否因 401 失效（登录页读一次弹「登录已过期」，读完复位）。
final sessionExpiredProvider = StateProvider<bool>((ref) => false);

/// userProvider（T2.3）：有 token → fetchMe；401 → 清 token 返回 null；
/// refresh() 重拉。首页在 data == null && 无错误时显示骨架屏。
final userProvider =
    AsyncNotifierProvider<UserNotifier, UserProfile?>(UserNotifier.new);

class UserNotifier extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final token = ref.watch(tokenProvider);
    if (token == null || token.isEmpty) return null;
    try {
      return await ref.read(authRepositoryProvider).fetchMe();
    } on ApiException catch (e) {
      if (e.code == 401) {
        // token 失效：打标 + 清掉，路由守卫随后跳 /login。
        ref.read(sessionExpiredProvider.notifier).state = true;
        await ref.read(tokenProvider.notifier).clear();
        return null;
      }
      rethrow;
    }
  }

  /// 重新拉 /api/me（外部调用的刷新入口）。
  Future<void> refresh() async {
    ref.invalidateSelf();
  }
}
