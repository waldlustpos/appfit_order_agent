/// 자동접수 시 서버에 보낼 준비시간(분).
///
/// 수동접수는 주문 상세 팝업에서 점주가 고른 값을 그대로 보내지만, 자동접수는
/// 선택 UI 가 없어 이 기본값을 보낸다. (이전에는 미지정 → 0 분으로 나갔다.)
const int kAutoAcceptReadyTimeMinutes = 15;

/// 라벨 sub-info(원두/온도/사이즈) 분류에 쓰이는 **TPCP 매장 전용** 옵션그룹 POS 코드.
///
/// 매장이 설정 화면에서 직접 고르게 하는 안을 검토했다가 접었다 — 점주가 옵션
/// 그룹을 골라야 하는 조작 부담이 크고, 그룹 이름·구성이 매장마다 제각각이라
/// 무엇을 골라야 할지 화면만 보고는 알기 어렵다. 라벨에 무엇을 크게 찍을지는
/// 브랜드 운영 정책에 가깝다고 판단해 코드에 남긴다.
/// (상품 카테고리 필터는 반대 판단 — 매장 설정이다. `LabelOutputPolicy` 참조.)
class OrderCategoryCodes {
  /// 옵션카테고리 - 원두 타입 (예: 다크, 산미)
  static const Set<String> beanTypeCodes = {'TKP012'};

  /// 온도 (예: HOT, ICED)
  static const Set<String> temperatureCodes = {'TKP001', 'TKP002', 'TKP003'};

  /// 사이즈 (예: Regular, Large)
  static const Set<String> sizeOptionCodes = {
    'TKP004',
    'TKP009',
    'TKP010',
    'TKP011',
    'TKP013',
  };

  OrderCategoryCodes._();
}
