class StoreModel {
  final String storeId;
  final String name;
  final bool isOpen;
  late final String? rewardType;

  StoreModel({
    required this.storeId,
    required this.name,
    required this.isOpen,
    this.rewardType = '',
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
    };
  }

  StoreModel copyWith({
    String? storeId,
    String? name,
    bool? isOpen,
    String? rewardType,
  }) {
    return StoreModel(
      storeId: storeId ?? this.storeId,
      name: name ?? this.name,
      isOpen: isOpen ?? this.isOpen,
      rewardType: rewardType ?? this.rewardType,
    );
  }
}
