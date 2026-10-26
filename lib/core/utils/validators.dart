/// 表单校验（登录/注册/优惠码等）。
///
/// 纯函数，可单测。文案在调用处拼，这里只给判定。
library;

final RegExp _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// 邮箱格式：非空 + 含 @ 且域名带点。
bool isValidEmail(String? email) {
  if (email == null) return false;
  final v = email.trim();
  return v.isNotEmpty && _emailRe.hasMatch(v);
}

/// 密码非空（长度规则按后端口径，这里只判非空）。
bool isValidPassword(String? password) =>
    password != null && password.isNotEmpty;

/// 订阅 token 非空。
bool isValidToken(String? token) => token != null && token.trim().isNotEmpty;
