class StoreModel {
  final String storeId;
  final String name;
  final bool isOpen;
  late final String? rewardType;

  /// 매장 전화번호 (`/v0/shop` 응답의 `shopContact`).
  final String? phone;

  /// 사업자번호. /v0/shop 응답에 현재 미포함. 백엔드 추가 후 매핑 예정.
  final String? businessNumber;

  StoreModel({
    required this.storeId,
    required this.name,
    required this.isOpen,
    this.rewardType = '',
    this.phone,
    this.businessNumber,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) {
    return StoreModel(
      storeId: json['strId'] as String,
      name: json['name'] as String,
      isOpen: json['orderStatus'] == 8 ? true : false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': storeId,
      'name': name,
      'isOpen': isOpen,
      'phone': phone,
      'businessNumber': businessNumber,
    };
  }

  StoreModel copyWith({
    String? storeId,
    String? name,
    bool? isOpen,
    String? rewardType,
    String? phone,
    String? businessNumber,
  }) {
    return StoreModel(
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      isOpen: isOpen ?? this.isOpen,
      rewardType: rewardType ?? this.rewardType,
      phone: phone ?? this.phone,
      businessNumber: businessNumber ?? this.businessNumber,
    );
  }
}
