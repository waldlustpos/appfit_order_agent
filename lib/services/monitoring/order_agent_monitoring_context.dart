import 'package:appfit_core/appfit_core.dart';

/// order_agent용 MonitoringContext 구현체
class OrderAgentMonitoringContext implements MonitoringContext {
  @override
  final String storeId;

  @override
  final String storeName;

  @override
  String get appType => 'ORDER_AGENT';

  @override
  final String appVersion;

  @override
  final String buildNumber;

  @override
  final String deviceModel;

  @override
  final String deviceManufacturer;

  @override
  final String environment;

  const OrderAgentMonitoringContext({
    this.storeId = '',
    this.storeName = '',
    required this.appVersion,
    required this.buildNumber,
    required this.deviceModel,
    required this.deviceManufacturer,
    required this.environment,
  });

  OrderAgentMonitoringContext copyWith({
    String? storeId,
    String? storeName,
    String? appVersion,
    String? buildNumber,
    String? deviceModel,
    String? deviceManufacturer,
    String? environment,
  }) {
    return OrderAgentMonitoringContext(
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      appVersion: appVersion ?? this.appVersion,
      buildNumber: buildNumber ?? this.buildNumber,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceManufacturer: deviceManufacturer ?? this.deviceManufacturer,
      environment: environment ?? this.environment,
    );
  }
}
