import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/invite_info.dart';
import '../../data/repositories/invite_repository.dart';

/// 邀请页数据源（T7.1）。refresh() 重拉，供页面重试按钮使用。
final inviteRepositoryProvider = Provider<InviteRepository>(
  (ref) => InviteRepository(),
);

final inviteInfoProvider = AsyncNotifierProvider<InviteNotifier, InviteInfo>(
  InviteNotifier.new,
);

class InviteNotifier extends AsyncNotifier<InviteInfo> {
  @override
  Future<InviteInfo> build() =>
      ref.read(inviteRepositoryProvider).fetchMe();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(inviteRepositoryProvider).fetchMe(),
    );
  }
}

/// 把加载异常转成可展示文案（UI 只展示 message，不展示 toString）。
String inviteErrorText(Object error) {
  if (error is ApiException) return error.message;
  return '加载失败，请稍后重试';
}
