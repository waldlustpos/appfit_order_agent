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

  @override
  String toString() {
    return 'MenuOptionModel: $shopOptionId : $optionName : $optionPrice : $qty';
  }
}
