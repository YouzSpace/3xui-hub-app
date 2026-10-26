import '../../core/network/api_client.dart';
import '../models/invite_info.dart';

/// 邀请仓库（T7.1）：唯一能碰 ApiClient 的邀请入口。
class InviteRepository {
  InviteRepository({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// GET /api/invite/me（Bearer 由拦截器自动加）。
  Future<InviteInfo> fetchMe() async {
    final data = await _client.request('/api/invite/me');
    return parseInviteInfo(data);
  }
}
