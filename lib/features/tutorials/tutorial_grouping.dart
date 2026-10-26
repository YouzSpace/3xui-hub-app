import '../../data/models/tutorial.dart';

/// 教程分组结果：一个分类名 + 该分类下的教程（保持后端顺序）。
class TutorialGroup {
  final String category;
  final List<Tutorial> items;

  const TutorialGroup({required this.category, required this.items});
}

/// 按 category 分组（T7.2）。纯函数便于单测。
///
/// 规则：
/// - 分组顺序 = 该分类**第一次出现**的顺序（后端已按 sort/id 排好，不再打乱）
/// - 分类内条目保持原相对顺序
/// - 空分类名归入「默认」（模型已兜底，这里再挡一层）
List<TutorialGroup> groupTutorials(List<Tutorial> list) {
  final order = <String>[];
  final buckets = <String, List<Tutorial>>{};
  for (final t in list) {
    final key = t.category.trim().isEmpty ? '默认' : t.category.trim();
    final bucket = buckets[key];
    if (bucket == null) {
      order.add(key);
      buckets[key] = [t];
    } else {
      bucket.add(t);
    }
  }
  return [
    for (final key in order) TutorialGroup(category: key, items: buckets[key]!),
  ];
}
