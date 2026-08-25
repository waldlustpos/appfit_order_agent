class MenuOptionModel {
  final String shopOptionId;
  final String optionName;
  final double optionPrice;
  final int qty;

  /// 옵션 그룹(= 옵션 카테고리) 정보. **v1 주문상세 응답에만 존재**하므로 nullable.
  ///
  /// [optionGroupPosId] 가 라벨 sub-info 분류(원두/온도/사이즈)의 정본이다
  /// (`OrderCategoryCodes` 와 같은 네임스페이스: TKP001/TKP004/TKP012 …).
  /// 과거에는 상품마스터의 categoryCode 를 조인해 얻었으나, 서버가 상품 경로로
  /// 옵션 카테고리를 더 이상 내려주지 않아 주문 응답 기반으로 전환했다.
  final String? optionGroupId;
  final String? optionGroupPosId;
  final String? optionGroupName;

  /// POS 상품코드(예: 'M009000'). **v1 주문상세 응답에만 존재**하므로 nullable.
  final String? itemPosId;

  MenuOptionModel({
    required this.shopOptionId,
    required this.optionName,
    required this.optionPrice,
    required this.qty,
    this.optionGroupId,
    this.optionGroupPosId,
    this.optionGroupName,
    this.itemPosId,
  });

  factory MenuOptionModel.fromJson(Map<String, dynamic> json) {
    return MenuOptionModel(
      shopOptionId: json['shopOptionId'] as String? ?? '',
      optionName: json['optionName'] as String? ?? '',
      optionPrice:
          double.tryParse(json['optionPrice']?.toString() ?? '0') ?? 0.0,
      qty: int.tryParse(json['qty']?.toString() ?? '0') ?? 0,
      optionGroupId: json['optionGroupId'] as String?,
      optionGroupPosId: json['optionGroupPosId'] as String?,
      optionGroupName: json['optionGroupName'] as String?,
      itemPosId: json['itemPosId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'shopOptionId': shopOptionId,
      'optionName': optionName,
      'optPrdNm': optionName, // Sunmi 호환용 추가
      'optionPrice': optionPrice,
      'optPrdPrc': optionPrice, // Sunmi 호환용 추가
      'qty': qty,
      'optPrdCnt': qty, // Sunmi 호환용 추가
      // 캐시 왕복(fromJson) 시 라벨 분류 정보가 유실되지 않도록 함께 보존.
      if (optionGroupId != null) 'optionGroupId': optionGroupId,
      if (optionGroupPosId != null) 'optionGroupPosId': optionGroupPosId,
      if (optionGroupName != null) 'optionGroupName': optionGroupName,
      if (itemPosId != null) 'itemPosId': itemPosId,
    };
  }

  Map<String, dynamic> toJsonForSoundGraph() {
    return {
      'optSku': shopOptionId,
      'optTitle': optionName,
      'optCnt': qty,
      'optPrice': (optionPrice * qty).toInt(),
    };
  }

  @override
  String toString() {
    return 'MenuOptionModel: $shopOptionId : $optionName : $optionPrice : $qty'
        '${optionGroupPosId != null ? ' (group=$optionGroupPosId)' : ''}';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MenuOptionModel &&
        shopOptionId == other.shopOptionId &&
        optionName == other.optionName &&
        optionPrice == other.optionPrice &&
        qty == other.qty &&
        optionGroupId == other.optionGroupId &&
        optionGroupPosId == other.optionGroupPosId &&
        optionGroupName == other.optionGroupName &&
        itemPosId == other.itemPosId;
  }

  @override
  int get hashCode => Object.hash(shopOptionId, optionName, optionPrice, qty,
      optionGroupId, optionGroupPosId, optionGroupName, itemPosId);
}
