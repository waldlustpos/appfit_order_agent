import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/config/build_brand.dart';
import 'package:appfit_order_agent/providers/preference_provider.dart';
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
/// [currentBrandMeta] 와 동일한 해석을 [preferenceServiceProvider] 경유로 수행한다
/// (테스트 override 가능). 브랜드는 세션당 안정적이며 (로그인 시 1회 결정),
/// 로그아웃/서버전환은 위젯 트리를 재구성하므로 별도 invalidation 후크가 필요
/// 없다. 상태를 보유하지 않으므로 `Auth.logout()`/`disconnect()` 이후
/// dependency 가 outdated 되는 문제(서버 전환 재로그인 크래시)와 무관하다.
final currentBrandProvider = Provider<BrandMeta?>((ref) =>
    BrandRegistry.resolveOrNull(ref.read(preferenceServiceProvider).getId()));

/// 설치된 아티팩트와 로그인한 매장의 브랜드가 맞는지에 대한 판정.
enum BrandInstallMismatch {
  /// 일치하거나, 판단할 근거가 없다(미로그인·미등록 매장). 안내하지 않는다.
  none,

  /// 맘모스 매장인데 공통 앱이 깔려 있다 → 전용 앱 설치 안내.
  needsDedicatedApp,

  /// 맘모스 전용 앱인데 타 브랜드 매장으로 로그인했다 → 잘못 깔린 단말 경고.
  wrongDedicatedApp,
}

/// 빌드된 아티팩트의 브랜드와 로그인 매장의 브랜드가 어긋났는지 판정한다.
///
/// **차단하지 않는다.** 브랜드 시스템이 전부 런타임(`BrandRegistry`)이라 어느
/// 조합이든 기능은 정상 동작한다 — 실패 모드가 "깨짐"이 아니라 "런처 아이콘·
/// 이름이 브랜드와 다름"이다. 그래서 안내만 하고 사용을 막지 않는다.
///
/// 미등록 매장(kokonut 등)에서는 [BrandInstallMismatch.none] 이다. 브랜드를
/// 모르는 상태에서 "잘못 설치됐다"고 말할 근거가 없기 때문이다.
final brandInstallMismatchProvider = Provider<BrandInstallMismatch>((ref) {
  final brand = ref.watch(currentBrandProvider);
  if (brand == null) return BrandInstallMismatch.none;

  final storeIsMammoth = brand.key == BrandKey.mammoth;
  if (BuildBrand.isMammoth) {
    return storeIsMammoth
        ? BrandInstallMismatch.none
        : BrandInstallMismatch.wrongDedicatedApp;
  }
  return storeIsMammoth
      ? BrandInstallMismatch.needsDedicatedApp
      : BrandInstallMismatch.none;
});
