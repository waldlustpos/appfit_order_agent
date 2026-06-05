import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/services/platform_service.dart';

/// D3 MINI 전면(듀얼) 모니터 capability 를 brand slug 기준으로 조회하는 Provider.
///
/// 반환 맵: `hasSecondaryDisplay`(보조 디스플레이 부착 여부), `hasVideo`
/// (res/raw/<slug>.mp4 존재), `hasImage`(res/drawable/<slug>.png 존재).
///
/// slug 를 family 키로 받으므로 브랜드 전환 시 새로 probe 한다. Android 가 아니면
/// (Windows 등) 보조 디스플레이/콘텐츠가 없으므로 모두 false 를 반환해 설정 섹션을
/// 비노출 처리한다.
final dualMonitorCapabilityProvider =
    FutureProvider.family<Map<String, bool>, String>((ref, slug) async {
  if (!Platform.isAndroid) {
    return const {
      'hasSecondaryDisplay': false,
      'hasVideo': false,
      'hasImage': false,
    };
  }
  return PlatformService.getDualMonitorCapability(slug);
});
