import 'money.dart';

/// 套餐（T6.1，system-design §3.5 / `GET /api/plans`）。
///
/// 字段口径逐字对齐 `server/internal/handler/api/handler.go:handlePlans`：
/// `price` 是**元**（phpFloat），三个流量字段是 `int|null`。
class Plan {
  final int id;
  final String name;

  /// 价格（元）。免费套餐为 0，下单后后端直接置 paid。
  final Money price;

  /// `period`（周期套餐）或 `total`（总量套餐）。
  final String type;

  /// 周期套餐的月数；总量套餐通常为 null → 归 0。
  final int months;

  /// 每月流量上限（字节）。总量套餐为 null。
  final int? monthlyTraffic;

  /// 周期总流量上限（字节），后端自动算；纯第三方套餐为 0。
  final int? periodTraffic;

  /// 总量流量上限（字节）。周期套餐为 null。
  final int? totalTraffic;

  /// 订阅是否包含本站（本地）节点。
  final bool includeLocal;

  /// 注入的第三方订阅 ID（纯第三方套餐非空）。
  final List<int> thirdPartySubIds;

  const Plan({
    required this.id,
    required this.name,
    required this.price,
    required this.type,
    required this.months,
    required this.monthlyTraffic,
    required this.periodTraffic,
    required this.totalTraffic,
    required this.includeLocal,
    required this.thirdPartySubIds,
  });

  /// 是否为周期套餐（`type == 'period'`）。
  bool get isPeriod => type == 'period';

  /// 纯第三方套餐：不含本地节点、但挂了第三方线路。
  ///
  /// 口径对齐前端 `admin/Plans.vue` 的 `pureThird`：这类套餐第三方只管时间
  /// 不管流量，后端建单时已把流量字段清零 —— App 侧**不显示流量**，
  /// 改显示「流量随用随充」。
  bool get isPureThirdParty => !includeLocal && thirdPartySubIds.isNotEmpty;

  /// 周期套餐的价格单位文案：`/月` `/季` `/年` `/6个月`。
  ///
  /// 与 `user/Shop.vue` 的 months 分支一致（1/3/12 有专名，其余按数字）。
  String get priceUnitLabel {
    if (!isPeriod) return '一次性';
    switch (months) {
      case 1:
        return '/月';
      case 3:
        return '/季';
      case 12:
        return '/年';
      default:
        return months > 0 ? '/$months个月' : '';
    }
  }

  /// 类型 chip 文案。
  ///
  /// 任务书 T6.3 写的是「月付/季付/年付/流量包」，但后端 `type` 只有
  /// `period` / `total` 两种，月/季/年由 `months` 决定 —— 按真实契约取，
  /// 周期套餐再细分月付/季付/年付，总量套餐即「总量」。
  String get typeChipLabel {
    if (!isPeriod) return '总量';
    switch (months) {
      case 1:
        return '月付';
      case 3:
        return '季付';
      case 12:
        return '年付';
      default:
        return months > 0 ? '$months 个月' : '周期';
    }
  }

  /// 周期套餐的「折合每月」金额（用于 >1 个月的套餐展示性价比）。
  Money get monthlyEquivalent {
    if (!isPeriod || months <= 0) return price;
    return Money.fromCents((price.cents / months).round());
  }

  factory Plan.fromJson(Map<String, dynamic> json) {
    final id = jsonIntOrNull(json['id']);
    if (id == null) throwParseError();
    final rawThirdParty = json['third_party_sub_ids'];
    final thirdParty = <int>[];
    if (rawThirdParty is List) {
      for (final v in rawThirdParty) {
        final parsed = jsonIntOrNull(v);
        if (parsed != null) thirdParty.add(parsed);
      }
    }
    return Plan(
      id: id,
      name: jsonStr(json['name']),
      price: Money.parse(json['price']),
      type: jsonStr(json['type']),
      months: jsonInt(json['months']),
      // 三个流量字段都可能是 null（system-design §3.5 特别提示 total_traffic）。
      monthlyTraffic: jsonIntOrNull(json['monthly_traffic']),
      periodTraffic: jsonIntOrNull(json['period_traffic']),
      totalTraffic: jsonIntOrNull(json['total_traffic']),
      // 后端 include_local 是 PHP bool；缺失时按 true（对齐 (bool)($p->include_local ?? true)）。
      includeLocal: json['include_local'] != false,
      thirdPartySubIds: thirdParty,
    );
  }

  /// 列表解析：整体不是数组时抛 codeParse（而不是静默返回空列表，
  /// 免得把「接口挂了」伪装成「暂无套餐」）。
  static List<Plan> listFromJson(dynamic data) {
    if (data is! List) throwParseError();
    return [
      for (final item in data)
        if (item is Map<String, dynamic>)
          Plan.fromJson(item)
        else if (item is Map)
          Plan.fromJson(item.cast<String, dynamic>())
        else
          throwParseError(),
    ];
  }
}
