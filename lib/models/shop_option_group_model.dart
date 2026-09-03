/// 매장 옵션 그룹 (`/v0/shops/{shopCode}/categories/items` 응답의
/// `categories[].items[].optionGroups[]` 항목).
///
/// 서버 응답에서 옵션 그룹은 **상품마다 반복 등장**하고, 앱의 상품 목록은 평면이라
/// 옵션은 인공 '옵션' 버킷(`kOptionBucketCategoryName`)으로 접힌다. 그 과정에서
/// 그룹의 **표시명이 유실**된다 — 옵션 `ProductModel.categoryName` 은 버킷명
/// 고정이고 `categoryCode` 에만 그룹 POS 코드가 남는다.
///
/// 라벨 서브정보(subInfo) 설정 화면이 "어느 옵션 그룹을 라벨에 찍을지"를 점주에게
/// 물으려면 사람이 읽는 그룹명이 필요하므로, 카테고리와 같은 방식으로 그룹 자체를
/// 분리해 보존한다.
class ShopOptionGroupModel {
  /// 옵션 그룹 POS 코드 (응답 키 `optionGroupPosId`, 예: `TKP001`).
  ///
  /// 주문 응답의 [MenuOptionModel.optionGroupPosId] 와 **같은 네임스페이스**라
  /// 라벨 분류의 조인 키가 된다. 빈 값은 조인이 불가능하므로 파서가 스킵한다.
  final String groupCode;

  /// 화면에 노출되는 그룹명 (응답 키 `name`, 예: `온도를 선택하세요`).
  final String groupName;

  /// 서버 응답의 `displayOrder`. 그룹 정렬은 **응답 등장 순서**를 쓰므로
  /// (카테고리와 같은 규약) 참고용으로만 보존한다.
  final int displayOrder;

  const ShopOptionGroupModel({
    required this.groupCode,
    required this.groupName,
    required this.displayOrder,
  });

  /// 표시용 이름. 서버가 이름을 안 주면 코드라도 보여야 점주가 고를 수 있다.
  String get displayName => groupName.isNotEmpty ? groupName : groupCode;

  Map<String, dynamic> toJson() => {
        'optionGroupPosId': groupCode,
        'name': groupName,
        'displayOrder': displayOrder,
      };

  ShopOptionGroupModel copyWith({
    String? groupCode,
    String? groupName,
    int? displayOrder,
  }) {
    return ShopOptionGroupModel(
      groupCode: groupCode ?? this.groupCode,
      groupName: groupName ?? this.groupName,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopOptionGroupModel &&
          other.groupCode == groupCode &&
          other.groupName == groupName &&
          other.displayOrder == displayOrder;

  @override
  int get hashCode => Object.hash(groupCode, groupName, displayOrder);

  @override
  String toString() => 'ShopOptionGroupModel(groupCode: $groupCode, '
      'groupName: $groupName, displayOrder: $displayOrder)';
}
