import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../data/models/tutorial.dart';
import '../../data/repositories/tutorial_repository.dart';

/// 教程列表数据源（T7.2）。列表已含 content，详情页优先复用，
/// 避免点一次教程多打一次网络（后端列表本来就把正文带回来了）。
final tutorialRepositoryProvider = Provider<TutorialRepository>(
  (ref) => TutorialRepository(),
);

final tutorialsProvider =
    AsyncNotifierProvider<TutorialListNotifier, List<Tutorial>>(
  TutorialListNotifier.new,
);

class TutorialListNotifier extends AsyncNotifier<List<Tutorial>> {
  @override
  Future<List<Tutorial>> build() =>
      ref.read(tutorialRepositoryProvider).fetchAll();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(tutorialRepositoryProvider).fetchAll(),
    );
  }
}

/// 详情数据源：先看列表缓存命中，未命中再请求 /api/tutorials/{id}。
final tutorialDetailProvider =
    FutureProvider.autoDispose.family<Tutorial, int>((ref, id) async {
  final list = ref.watch(tutorialsProvider).valueOrNull;
  if (list != null) {
    for (final t in list) {
      if (t.id == id) return t;
    }
  }
  return ref.read(tutorialRepositoryProvider).fetchById(id);
});

/// 错误文案：只对外暴露 ApiException.message。
String tutorialErrorText(Object error) {
  if (error is ApiException) return error.message;
  return '加载失败，请稍后重试';
}
