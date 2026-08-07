// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product_provider.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

String _$shopCatalogHash() => r'c4108674eadedeb130bf4bcd5f670fdfbca6d63b';

/// 매장 카탈로그(카테고리 + 상품) 로드 — 서버 응답의 정본.
///
/// 상품이 0개인 카테고리는 상품 목록에 흔적이 남지 않으므로(서버 `categories[]`
/// 의 `items` 가 빈 배열), 카테고리를 상품과 분리해 함께 보존한다.
/// [productProvider] 와 [shopCategoryListProvider] 가 이 값에서 파생된다.
///
/// Copied from [shopCatalog].
@ProviderFor(shopCatalog)
final shopCatalogProvider = FutureProvider<
    ({
      List<ProductModel> products,
      List<ShopCategoryModel> categories
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
    ({List<ProductModel> products, List<ShopCategoryModel> categories})>;
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
String _$productHash() => r'870c0f498b53d9159aca973176e7bcda4939fe76';

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
