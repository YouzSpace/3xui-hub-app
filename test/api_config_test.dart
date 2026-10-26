import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:controlhub_app/core/config/api_config.dart';

void main() {
  setUp(() {
    // 每个用例隔离持久化：空 mock 表 → prefs 里没有 override。
    SharedPreferences.setMockInitialValues({});
  });

  test('默认值生效：未设置 override 时 base 为内置地址', () async {
    await ApiConfig.loadOverride();
    expect(ApiConfig.base, kDefaultApiBase);
  });

  test('override 生效：设置后 base 被覆盖', () async {
    await ApiConfig.setOverride('https://override.example.com');
    await ApiConfig.loadOverride();
    expect(ApiConfig.base, 'https://override.example.com');
  });

  test('清空恢复默认：setOverride(null) 后 base 回到内置地址', () async {
    await ApiConfig.setOverride('https://override.example.com');
    await ApiConfig.setOverride(null);
    await ApiConfig.loadOverride();
    expect(ApiConfig.base, kDefaultApiBase);
  });

  test('validate 失败返回 false：ping 不通的目标', () async {
    // 用本地未监听端口构造连接失败，2s 超时由 ApiConfig 内部控制。
    final ok = await ApiConfig.validate('http://127.0.0.1:1');
    expect(ok, false);
  });
}
