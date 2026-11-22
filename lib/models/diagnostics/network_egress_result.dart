/// 出口网络 IP 与地理位置查询结果数据模型
class NetworkEgressResult {
  const NetworkEgressResult({
    required this.at,
    this.ip = '',
    this.country = '',
    this.countryCode = '',
    this.region = '',
    this.city = '',
    this.provider = '',
    this.error = '',
  });

  final DateTime at;
  final String ip;
  final String country;
  final String countryCode;
  final String region;
  final String city;
  final String provider;
  final String error;

  static const notice = 'IP 归属地由查询服务估算；代理分流时可能与红果接口出口不同，不能单独证明风控。';

  String get location {
    final values = [country, region, city].where((value) => value.isNotEmpty);
    return values.isEmpty ? '归属地未知' : values.join(' · ');
  }

  String get summary => ip.isEmpty
      ? '出口 IP：检测失败（$error）'
      : '出口 IP：$ip · $location${countryCode.isEmpty ? '' : ' [$countryCode]'}';

  List<String> get reportLines => [
    '  - 出口 IP: ${ip.isEmpty ? '未取得' : ip}',
    '  - IP 归属地区: $location${countryCode.isEmpty ? '' : ' [$countryCode]'}',
    '  - IP 查询来源: $provider',
    '  - IP 检测时间: ${at.toUtc().toIso8601String()}',
    if (error.isNotEmpty) '  - IP 检测状态: $error',
    '  - IP 说明: $notice',
  ];
}
