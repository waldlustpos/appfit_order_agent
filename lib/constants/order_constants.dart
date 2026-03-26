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

  OrderCategoryCodes._();
}
