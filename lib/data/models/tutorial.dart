import '../../core/network/api_exception.dart';

/// 教程（system-design §3.9）。
///
/// 列表 `GET /api/tutorials` 返回 `{id,title,category,content,created_at}`；
/// 详情 `GET /api/tutorials/{id}` 少一个 `category`（后端只输出四个字段），
/// 所以 category 必须是可缺省字段。
class Tutorial {
  final int id;
  final String title;

  /// 分组名；后端为空时会补「默认」，这里再兜一次底防止分组出现空标题。
  final String category;
  final String content;
  final DateTime? createdAt;

  const Tutorial({
    required this.id,
    required this.title,
    required this.category,
    required this.content,
    required this.createdAt,
  });

  factory Tutorial.fromJson(Map<String, dynamic> json) {
    final idRaw = json['id'];
    if (idRaw == null) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    final category = _toStr(json['category']).trim();
    return Tutorial(
      id: _toInt(idRaw),
      title: _toStr(json['title']),
      category: category.isEmpty ? '默认' : category,
      content: _toStr(json['content']),
      createdAt: _toDateTime(json['created_at']),
    );
  }

  /// 列表解析：跳过非对象/坏行，不让一条脏数据毁掉整页。
  static List<Tutorial> listFromJson(dynamic data) {
    if (data is! List) {
      throw const ApiException(ApiException.codeParse, '服务响应异常，请稍后重试');
    }
    final out = <Tutorial>[];
    for (final item in data) {
      if (item is Map) {
        try {
          out.add(Tutorial.fromJson(Map<String, dynamic>.from(item)));
        } on ApiException {
          continue;
        }
      }
    }
    return out;
  }
}

String _toStr(dynamic v) => v is String ? v : (v == null ? '' : '$v');

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

DateTime? _toDateTime(dynamic v) {
  if (v is! String || v.isEmpty) return null;
  // 后端是 Eloquent 的 6 位微秒格式（2026-07-01T15:42:57.000000Z），
  // DateTime.parse 支持；解析失败只丢时间，不影响正文展示。
  return DateTime.tryParse(v);
}
