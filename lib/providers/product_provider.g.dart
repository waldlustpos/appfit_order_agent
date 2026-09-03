// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$shopCatalogHash() => r'8138f21bc76c69236848257f78b4b11097f8e96f';

/// 매장 카탈로그(카테고리 + 상품 + 옵션 + 옵션그룹) 로드 — 서버 응답의 정본.
///
/// 상품이 0개인 카테고리는 상품 목록에 흔적이 남지 않으므로(서버 `categories[]`
/// 의 `items` 가 빈 배열), 카테고리를 상품과 분리해 함께 보존한다. 옵션그룹도
/// 같은 이유로 분리한다(옵션을 '옵션' 버킷으로 접으면 그룹명이 유실된다).
/// [productProvider], [shopCategoryListProvider], [shopOptionGroupListProvider]
/// 가 이 값에서 파생된다.
///
/// Copied from [shopCatalog].
@ProviderFor(shopCatalog)
final shopCatalogProvider = FutureProvider<
    ({
      List<ProductModel> products,
      List<ShopCategoryModel> categories,
      List<ShopOptionGroupModel> optionGroups
    })>.internal(
  shopCatalog,
  name: r'shopCatalogProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$shopCatalogHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ShopCatalogRef = FutureProviderRef<
    ({
      List<ProductModel> products,
      List<ShopCategoryModel> categories,
      List<ShopOptionGroupModel> optionGroups
    })>;
String _$shopCategoryListHash() => r'b69e8e681c058e6b22187b05f9ec1db6780cb55f';

/// 상품관리 좌측 목록의 카테고리 정본 — **상품 0개 카테고리를 포함**한다.
///
/// 상품에서 역산하면 빈 카테고리가 표현되지 않으므로 서버 목록을 그대로 쓴다.
/// 단 옵션 버킷('옵션')은 서버 카테고리가 아닌 앱의 인공 그룹이라 여기에 없다 —
/// 화면에서 상품으로부터 보충한다.
///
/// Copied from [shopCategoryList].
@ProviderFor(shopCategoryList)
final shopCategoryListProvider =
    FutureProvider<List<ShopCategoryModel>>.internal(
  shopCategoryList,
  name: r'shopCategoryListProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$shopCategoryListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ShopCategoryListRef = FutureProviderRef<List<ShopCategoryModel>>;
String _$shopOptionGroupListHash() =>
    r'fc84b5b4537119ddd1fa468276e2ff212b1e16d2';

/// 매장 옵션 그룹 목록 — 라벨 서브정보(subInfo) 설정 화면의 후보 정본.
///
/// 순서는 서버 응답 등장 순서(파서의 dedupe 삽입 순서) 그대로다. 옵션 상품에서
/// 역산하면 그룹명이 '옵션' 버킷명으로 뭉개져 후보를 이름으로 보여줄 수 없다.
///
/// Copied from [shopOptionGroupList].
@ProviderFor(shopOptionGroupList)
final shopOptionGroupListProvider =
    FutureProvider<List<ShopOptionGroupModel>>.internal(
  shopOptionGroupList,
  name: r'shopOptionGroupListProvider',
  debugGetCreateSourceHash: const bool.fromEnvironment('dart.vm.product')
      ? null
      : _$shopOptionGroupListHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

@Deprecated('Will be removed in 3.0. Use Ref instead')
// ignore: unused_element
typedef ShopOptionGroupListRef = FutureProviderRef<List<ShopOptionGroupModel>>;
String _$productHash() => r'64afbd9d73544da2ef6319d0ad768e86a60e1342';

/// See also [Product].
@ProviderFor(Product)
final productProvider =
    AsyncNotifierProvider<Product, List<ProductModel>>.internal(
  Product.new,
  name: r'productProvider',
  debugGetCreateSourceHash:
      const bool.fromEnvironment('dart.vm.product') ? null : _$productHash,
  dependencies: null,
  allTransitiveDependencies: null,
);

typedef _$Product = AsyncNotifier<List<ProductModel>>;
// ignore_for_file: type=lint
// ignore_for_file: subtype_of_sealed_class, invalid_use_of_internal_member, invalid_use_of_visible_for_testing_member, deprecated_member_use_from_same_package
