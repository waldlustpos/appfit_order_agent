import 'package:appfit_order_agent/services/label_printer/label_print_data.dart';
import 'package:appfit_order_agent/utils/logger.dart';

/// 라벨 QR 페이로드 생성을 캡슐화하는 전략.
///
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

/// QR 페이로드 전략(전 브랜드 고정). 포맷: "{DisplayNum}-{CupIdx}" (예: 0795-0).
///
/// - DisplayNum: display no 4자리 (LabelOrderInfo.displayNum, 이미 zero-pad)
/// - CupIdx    : 주문 전체를 관통하는 0-based 라벨 sequence (labelIndex - 1).
///   ShopItemId 를 담지 않으므로, 메뉴별로 리셋되는 [LabelMenuInfo.labelSeq] 를
///   쓰면 서로 다른 메뉴의 첫 라벨끼리 모두 "-0" 으로 충돌한다. 라벨 인쇄
///   텍스트("{주문번호}-{순번}", output_service.dart 의 data.orderIndex)와
///   동일하게 주문 전체 누적 인덱스인 [labelIndex] 를 써야 라벨마다 유일하다.
class DisplayNumIndexQrPayloadStrategy extends QrPayloadStrategy {
  const DisplayNumIndexQrPayloadStrategy();

  @override
  String buildPayload(
    LabelOrderInfo orderInfo,
    LabelMenuInfo menuInfo,
    int labelIndex,
    int labelTotal,
  ) {
    final cupIdx = labelIndex - 1; // 1-based labelIndex(주문 전체) → 0-based cupIdx
    final payload = '${orderInfo.displayNum}-$cupIdx';
    logger.d('[Label][QR] $labelIndex/$labelTotal'
        ' ${menuInfo.itemName} (${menuInfo.labelSeq}/${menuInfo.qty})'
        ' → $payload');
    return payload;
  }
}
