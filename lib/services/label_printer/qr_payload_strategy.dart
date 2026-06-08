import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:appfit_order_agent/providers/brand_provider.dart';
import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/utils/brand_registry.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 라벨 QR 페이로드 생성을 캡슐화하는 브랜드별 전략.
///
/// 게이팅(어느 브랜드가 어떤 포맷을 쓰는지)은 [qrPayloadStrategyProvider] 가
/// [BrandKey] 로 결정한다. 전략 자체는 "QR 에 무엇을 담는가"라는 동작만 담는다.
/// 기존 [LabelFilterStrategy]/[SoundGraphHook] 와 동일한 패턴.
abstract class QrPayloadStrategy {
  const QrPayloadStrategy();

  /// 라벨 1장의 QR 페이로드를 생성한다.
  /// 메뉴 × qty 반복마다(라벨마다) 한 번 호출된다.
  String buildPayload(
    LabelOrderInfo orderInfo,
    LabelMenuInfo menuInfo,
    int labelIndex,
    int labelTotal,
  );
}

/// 기본 QR 페이로드 전략 (현재 코드의 포맷). 별도 포맷을 쓰는 브랜드가 없으면 이걸 사용.
///
/// 포맷: "{OrderNo}-{ShopItemId}-{CupIdx}".
/// 참고(미사용/주석): full 포맷은
///   "{OrderNo}-{ShopItemId}-{CupIdx}-{ShopCode}-{YYYYMMDD}-{DisplayNo}".
///   예: ORD-123456-M1-0-SHOP001-20260520-0795
///
/// - OrderNo   : 주문 식별자
/// - ShopItemId: 메뉴 식별자
/// - CupIdx    : 같은 메뉴 안에서 0-based 라벨 sequence (중복 스캔 방지)
/// - ShopCode  : storeId
/// - YYYYMMDD  : orderedAt 의 날짜 (별도 영업일 필드가 없어 주문 시각 기준)
/// - DisplayNo : display no 4자리 (LabelOrderInfo.displayNum)
class DefaultQrPayloadStrategy extends QrPayloadStrategy {
  const DefaultQrPayloadStrategy();

  @override
  String buildPayload(
    LabelOrderInfo orderInfo,
    LabelMenuInfo menuInfo,
    int labelIndex,
    int labelTotal,
  ) {
    final cupIdx = menuInfo.labelSeq - 1; // 1-based labelSeq → 0-based cupIdx
    final payload = '${orderInfo.orderNo}-${menuInfo.shopItemId}-$cupIdx';
    // full 포맷(미적용, 클래스 doc 참고): payload 뒤에
    //   '-${orderInfo.storeId}-{yyyyMMdd(orderedAt)}-${orderInfo.displayNum}' 추가.
    logger.d('[Label][QR] $labelIndex/$labelTotal'
        ' ${menuInfo.itemName} (${menuInfo.labelSeq}/${menuInfo.qty})'
        ' → $payload');
    return payload;
  }
}

/// 현재 브랜드에 맞는 [QrPayloadStrategy] 를 제공한다.
///
/// 현재는 모든 브랜드가 [DefaultQrPayloadStrategy] 를 쓴다. 다른 포맷이 필요한
/// 브랜드가 도입되면 아래 switch 에 `case BrandKey.xxxx: return const XxxxQrPayloadStrategy();`
/// 를 추가한다. `default:` 대신 모든 [BrandKey] 를 명시해, 새 브랜드 추가 시
/// analyzer 가 QR 포맷 결정을 강제하도록 한다.
final qrPayloadStrategyProvider = Provider<QrPayloadStrategy>((ref) {
  final brand = ref.watch(currentBrandProvider);
  switch (brand?.key) {
    // 미래 브랜드 override 지점:
    // case BrandKey.xxxx: return const XxxxQrPayloadStrategy();
    case BrandKey.tpcp:
    case BrandKey.mhst:
    case BrandKey.mata:
    case BrandKey.paik:
    case null:
      return const DefaultQrPayloadStrategy();
  }
});
