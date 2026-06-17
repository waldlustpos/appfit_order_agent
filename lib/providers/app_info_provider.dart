import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:appfit_order_agent/services/platform_service.dart';

/// Provides application package information asynchronously.
final appInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return await PackageInfo.fromPlatform();
});

/// Sunmi 내장 스캐너(멤버십 화면 바코드 스캔 버튼) 가용 여부.
/// Android 가 아니면(Windows 등) 내장 스캐너가 없으므로 false → 버튼 미노출.
final hasBuiltinScannerProvider = FutureProvider<bool>((ref) async {
  if (!Platform.isAndroid) return false;
  return PlatformService.hasBuiltinScanner();
});
