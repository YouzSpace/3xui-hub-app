/// API 错误（system-design §7）。
///
/// 统一错误对象：`code` 是后端业务码或约定的负值，`message` 直接可展示给用户。
/// UI 层只展示 `ApiException.message`，禁止展示 `e.toString()`。
class ApiException implements Exception {
  /// 后端 code（code !== 0），或约定的负值（见下方常量）。
  final int code;

  /// 直接可展示的中文文案。
  final String message;

  const ApiException(this.code, this.message);

  /// 网络超时 / 无网络。
  static const int codeNetwork = -1;

  /// JSON 解析失败。
  static const int codeParse = -2;

  @override
  String toString() => message;
}
