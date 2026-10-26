import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// access_token 的加密存储（T1.5）。
///
/// 铁律：token 只存 flutter_secure_storage（Keystore 加密），
/// 绝不写 SharedPreferences、日志、崩溃上报。
class TokenStore {
  static const _storage = FlutterSecureStorage();
  static const String _key = 'access_token';

  static Future<String?> read() => _storage.read(key: _key);

  static Future<void> write(String token) =>
      _storage.write(key: _key, value: token);

  static Future<void> clear() => _storage.delete(key: _key);
}
