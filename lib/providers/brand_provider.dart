import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/services/preference_service.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';

/// 현재 로그인 매장의 [BrandMeta] 를 즉석에서 해석하는 무상태 헬퍼.
///
/// 호출 시점마다 [PreferenceService] 의 매장 ID 를 읽어 [BrandRegistry.resolveOrNull]
/// 하므로 항상 최신이다. 미로그인/기타(kokonut) 매장은 **null** — capability 가
/// 하나도 없는 상태로 다뤄야 하므로 자산용 fallback(tpcp)을 쓰지 않는다.
/// ref 가 없는 서비스/모델 계층에서 사용한다.
BrandMeta? currentBrandMeta() =>
    BrandRegistry.resolveOrNull(PreferenceService().getId());

/// 현재 브랜드 [BrandMeta]? 를 노출하는 Riverpod Provider (미지의 매장은 null).
///
/// 무상태 [currentBrandMeta] 를 감싸기만 한다. 브랜드는 세션당 안정적이며
/// (로그인 시 1회 결정), 로그아웃/서버전환은 위젯 트리를 재구성하므로 별도
/// invalidation 후크가 필요 없다. 상태를 보유하지 않으므로 `Auth.logout()`/
/// `disconnect()` 이후 dependency 가 outdated 되는 문제(서버 전환 재로그인 크래시)와
/// 무관하다.
final currentBrandProvider = Provider<BrandMeta?>((ref) => currentBrandMeta());
