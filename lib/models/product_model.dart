enum ProductStatus {
  sale('OS'),
  soldOut('SO'),
  hidden('HD');

  final String code;
  const ProductStatus(this.code);

  factory ProductStatus.fromCode(String code) {
    switch (code) {
      case 'OS':
        return ProductStatus.sale;
      case 'SO':
        return ProductStatus.soldOut;
      case 'HD':
        return ProductStatus.hidden;

      default:
        return ProductStatus.sale;
    }
  }
}

enum ProductType {
  item('ITEM'),
  option('OPTION');

  final String code;
  const ProductType(this.code);

  factory ProductType.fromCode(String code) {
    switch (code.toUpperCase()) {
      case 'ITEM':
        return ProductType.item;
      case 'OPTION':
        return ProductType.option;
      default:
        return ProductType.item;
    }
  }
}

class ProductModel {
  final String productId;
  final String productName;
  final String categoryName;
  final String categoryCode; // [NEW] 카테고리 코드 (예: TKP009)
  final int menuPrice;
  final ProductStatus status;
  final ProductType type; // [NEW] 상품과 옵션 구분
  final String internalId; // [NEW] 플랫폼 고유 UUID (shopItemId/optionId)

  ProductModel({
    required this.productId,
    required this.productName,
    required this.categoryName,
    required this.categoryCode,
    required this.menuPrice,
    required this.status,
    required this.type,
    required this.internalId,
  });

  ProductModel copyWith({
    String? productId,
    String? productName,
    String? categoryName,
    String? categoryCode,
    int? menuPrice,
    ProductStatus? status,
    ProductType? type,
    String? internalId,
  }) {
    return ProductModel(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      categoryName: categoryName ?? this.categoryName,
      categoryCode: categoryCode ?? this.categoryCode,
      menuPrice: menuPrice ?? this.menuPrice,
      status: status ?? this.status,
      type: type ?? this.type,
      internalId: internalId ?? this.internalId,
    );
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      productId: json['prdId'] ?? '',
      productName: json['prdNm'] ?? '',
      categoryName: json['ctgNm'] ?? '',
      categoryCode:
          (json['ctgCd'] ?? json['categoryCode'] ?? json['categoryPosId']) ??
              '',
      menuPrice: int.tryParse(json['salePrc']?.toString() ?? '0') ??
          0, // toString() 추가로 안정성 확보
      status: ProductStatus.fromCode(json['prdSaleCd'] ?? 'OS'),
      type: ProductType.fromCode(json['type'] ?? 'ITEM'),
      internalId: json['internalId'] ?? '',
    );
  }

  @override
  String toString() {
    return 'ProductModel: $productName : $productId ($internalId) : $menuPrice : $status ($type)';
  }
}
