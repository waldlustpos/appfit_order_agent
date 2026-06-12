class MenuOptionModel {
  final String shopOptionId;
  final String optionName;
  final double optionPrice;
  final int qty;

  MenuOptionModel({
    required this.shopOptionId,
    required this.optionName,
    required this.optionPrice,
    required this.qty,
  });

  factory MenuOptionModel.fromJson(Map<String, dynamic> json) {
    return MenuOptionModel(
      shopOptionId: json['shopOptionId'] as String? ?? '',
      optionName: json['optionName'] as String? ?? '',
      optionPrice:
          double.tryParse(json['optionPrice']?.toString() ?? '0') ?? 0.0,
      qty: int.tryParse(json['qty']?.toString() ?? '0') ?? 0,
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
    return 'MenuOptionModel: $shopOptionId : $optionName : $optionPrice : $qty';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MenuOptionModel &&
        shopOptionId == other.shopOptionId &&
        optionName == other.optionName &&
        optionPrice == other.optionPrice &&
        qty == other.qty;
  }

  @override
  int get hashCode => Object.hash(shopOptionId, optionName, optionPrice, qty);
}
