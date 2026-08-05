/// 매장 상품 카테고리 (`/v0/shops/{shopCode}/categories` 응답의 `categories[]` 항목).
///
/// 서버는 소속 상품(`items`)이 0개인 카테고리도 내려주지만, 응답을 `ProductModel`
/// 목록으로 평탄화하면 빈 카테고리는 흔적이 남지 않아 사라진다. 상품관리 좌측
/// 목록이 "상품 0개 카테고리"까지 표시할 수 있도록 카테고리 자체를 상품과 분리해
/// 보존하기 위한 모델이다.
class ShopCategoryModel {
  /// 화면에 노출되는 카테고리명 (예: `테스트_대커피`).
  final String categoryName;

  /// POS 카테고리 코드 (예: `DX0000`, `EC0001`). 응답 키는 `categoryPosId`.
  final String categoryCode;

  /// 서버가 지정한 표시 순서 (응답 키 `displayOrder`). "각 카테고리 및 상품은
  /// displayOrder로 정렬"이 서버 계약이라, 응답 배열 순서가 아니라 이 필드로
  /// 정렬해야 한다.
  final int displayOrder;

  const ShopCategoryModel({
    required this.categoryName,
    required this.categoryCode,
    required this.displayOrder,
  });

  /// 카테고리명은 화면 식별자이자 상품 그룹핑 키라 누락 시 표시가 불가능하므로,
  /// silent 기본값 대신 [FormatException] 을 던져 호출부가 항목을 스킵하게 한다.
  factory ShopCategoryModel.fromJson(Map<String, dynamic> json) {
    final name = json['categoryName']?.toString();
    if (name == null || name.isEmpty) {
      throw const FormatException(
          'ShopCategoryModel: categoryName 누락 (categories[] 항목)');
    }
    return ShopCategoryModel(
      categoryName: name,
      categoryCode: json['categoryPosId']?.toString() ?? '',
      displayOrder: (json['displayOrder'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'categoryName': categoryName,
        'categoryPosId': categoryCode,
        'displayOrder': displayOrder,
      };

  ShopCategoryModel copyWith({
    String? categoryName,
    String? categoryCode,
    int? displayOrder,
  }) {
    return ShopCategoryModel(
      categoryName: categoryName ?? this.categoryName,
      categoryCode: categoryCode ?? this.categoryCode,
      displayOrder: displayOrder ?? this.displayOrder,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShopCategoryModel &&
          other.categoryName == categoryName &&
          other.categoryCode == categoryCode &&
          other.displayOrder == displayOrder;

  @override
  int get hashCode => Object.hash(categoryName, categoryCode, displayOrder);

  @override
  String toString() =>
      'ShopCategoryModel(categoryName: $categoryName, categoryCode: $categoryCode, displayOrder: $displayOrder)';
}
