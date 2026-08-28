/// 자동접수 시 서버에 보낼 준비시간(분).
///
/// 수동접수는 주문 상세 팝업에서 점주가 고른 값을 그대로 보내지만, 자동접수는
/// 선택 UI 가 없어 이 기본값을 보낸다. (이전에는 미지정 → 0 분으로 나갔다.)
const int kAutoAcceptReadyTimeMinutes = 15;

/// 라벨 출력 및 주문 처리 시 사용되는 상품 카테고리 코드 정의
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

  /// 상품 카테고리 - 디저트  (현재 와플만)
  static const Set<String> waffleCategoryCodes = {'TKP1006'};

  //세트상품 상품코드
  static const Set<String> setItemCodes = {'TKP0051', 'TKP0052'};

  OrderCategoryCodes._();
}
