import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/services/platform_service.dart'; // apiServiceProvider를 위해 필요
import 'package:appfit_order_agent/services/local_server_service.dart'; // LocalServerService를 위해 필요
import 'package:appfit_order_agent/providers/providers.dart'; // storeProvider를 위해 필요
import 'package:appfit_order_agent/utils/logger.dart'; // logger import 추가

part 'product_provider.g.dart';

/// 매장 카탈로그(카테고리 + 상품 + 옵션) 로드 — 서버 응답의 정본.
///
/// 상품이 0개인 카테고리는 상품 목록에 흔적이 남지 않으므로(서버 `categories[]`
/// 의 `items` 가 빈 배열), 카테고리를 상품과 분리해 함께 보존한다.
/// [productProvider] 와 [shopCategoryListProvider] 가 이 값에서 파생된다.
@Riverpod(keepAlive: true)
Future<({List<ProductModel> products, List<ShopCategoryModel> categories})>
    shopCatalog(Ref ref) async {
  logger.i('ShopCatalog build() 시작');

  // 매장 ID가 준비될 때까지 대기.
  // 로딩 중 AsyncValue.value 는 이전(다른) 매장 값을 유지할 수 있으므로 settle 되지
  // 않은 상태에서는 조회하지 않는다(매장 전환 시 이전 매장으로의 stale 카탈로그 조회
  // = 404 NOT_FOUND_SHOP 방지). storeProvider 가 settle 되면 watch 로 자동 재빌드되어
  // 올바른 매장으로 조회한다.
  //  - 최초 로딩(이전 값 없음): future 가 첫 settled 값까지 대기 → 정상 조회.
  //  - 전환 로딩(이전 매장 잔존): future 가 이전 값으로 즉시 완료될 수 있어, 재확인 후
  //    아직 로딩이면 조회를 보류한다.
  var storeAsync = ref.watch(storeProvider);
  if (storeAsync.isLoading) {
    await ref.read(storeProvider.future);
    storeAsync = ref.read(storeProvider);
    if (storeAsync.isLoading) {
      logger.d('ShopCatalog build: store 미settle — 조회 보류');
      return (products: <ProductModel>[], categories: <ShopCategoryModel>[]);
    }
  }
  final finalStoreId = storeAsync.value?.storeId;

  logger.d('ShopCatalog build: StoreId $finalStoreId');

  if (finalStoreId == null || finalStoreId.isEmpty) {
    logger.d('ShopCatalog build: StoreId not ready.');
    return (products: <ProductModel>[], categories: <ShopCategoryModel>[]);
  }

  logger.i(
      'ShopCatalog build: StoreId ready ($finalStoreId). Loading products...');
  final apiService = ref.read(apiServiceProvider);
  try {
    // 카탈로그(카테고리 + 상품 + 옵션) 로드 — 실패하면 치명적.
    // 옵션의 categoryCode(= 옵션그룹 POS 코드)는 응답에 함께 실려 오므로
    // 별도의 마이그레이션 조회/병합 단계가 없다.
    final catalog = await apiService.getShopCatalog(finalStoreId);
    final products = catalog.products;

    logger.i('ShopCatalog build: Loaded ${products.length} products and '
        '${catalog.categories.length} categories.');

    // LocalServerService 캐시 업데이트
    try {
      final localServer = LocalServerService.instance;
      if (localServer != null) {
        localServer.updateProductCache(products);
      }
    } catch (e, s) {
      logger.w('LocalServerService 캐시 업데이트 실패', error: e);
    }

    return (products: products, categories: catalog.categories);
  } catch (e, stackTrace) {
    logger.e('ShopCatalog build: Error loading products',
        error: e, stackTrace: stackTrace);
    return (products: <ProductModel>[], categories: <ShopCategoryModel>[]);
  }
}

/// 상품관리 좌측 목록의 카테고리 정본 — **상품 0개 카테고리를 포함**한다.
///
/// 상품에서 역산하면 빈 카테고리가 표현되지 않으므로 서버 목록을 그대로 쓴다.
/// 단 옵션 버킷('옵션')은 서버 카테고리가 아닌 앱의 인공 그룹이라 여기에 없다 —
/// 화면에서 상품으로부터 보충한다.
@Riverpod(keepAlive: true)
Future<List<ShopCategoryModel>> shopCategoryList(Ref ref) async =>
    (await ref.watch(shopCatalogProvider.future)).categories;

@Riverpod(keepAlive: true)
class Product extends _$Product {
  @override
  Future<List<ProductModel>> build() async =>
      (await ref.watch(shopCatalogProvider.future)).products;

  // 상품 목록 새로고침 (카탈로그 원본을 무효화 → 파생 프로바이더가 함께 재빌드)
  Future<void> refresh() async {
    logger.i('Product refresh: 새로고침 시작');
    ref.invalidate(shopCatalogProvider);
  }

  /// 동일 상품명 그룹의 일괄 상태 변경.
  ///
  /// 서버 API 가 이미 벌크 스키마라 그룹당 PUT 1회로 끝난다.
  ///
  /// **낙관적 갱신은 `internalId` 로 매칭한다.** 그룹 멤버는 productId(POS ID)가
  /// 서로 다르고, 같은 상품이 여러 카테고리에 등록돼 있으면 목록에 사본이 여러 개
  /// 존재한다 — productId 매칭으로는 사본 일부가 옛 상태로 남아 좌측 카운트와
  /// 카드 표기가 어긋난다.
  ///
  /// UI 파생 타입(`ProductGroup`)에 의존하지 않도록 원시값으로 받는다.
  Future<bool> updateProductsStatus({
    required ProductType type,
    required List<String> internalIds,
    required ProductStatus newStatus,
  }) async {
    if (!state.hasValue) {
      logger.w('상품 상태 변경 불가: 상품 목록 미로드 (state: $state)');
      return false;
    }
    final currentProducts = state.value!;

    // storeId 는 build 와 독립적으로 실행되므로 storeProvider 의 현재 값을 읽는다.
    final storeAsyncValue = ref.read(storeProvider);
    final storeId = storeAsyncValue.value?.storeId ?? '';
    if (!storeAsyncValue.hasValue || storeId.isEmpty) {
      logger.e('상품 상태 변경 불가: storeId 없음 (state: $storeAsyncValue)');
      return false;
    }

    final targets = {...internalIds.where((id) => id.isNotEmpty)};
    if (targets.isEmpty) {
      logger.w('상품 상태 변경 불가: 유효한 internalId 없음');
      return false;
    }

    logger.i('상품 일괄 상태 변경: ${targets.length}건(${type.code}) '
        '→ $newStatus / $storeId');

    try {
      final apiService = ref.read(apiServiceProvider);
      final success = await apiService.updateItemsStatus(
        storeId: storeId,
        type: type,
        internalIds: targets.toList(),
        status: newStatus,
      );

      if (!success) {
        logger.e('서버가 일괄 상태 변경을 거부: ${targets.length}건 → $newStatus');
        return false;
      }

      logToFile(
          tag: LogTag.UI_ACTION,
          message: '상품상태 일괄 변경 성공: ${targets.length}건(${type.code}) '
              '→ $newStatus');

      // internalId 매칭 + 타입 확인(UUID 네임스페이스 충돌 방어).
      // 같은 internalId 를 가진 카테고리 사본도 함께 갱신된다.
      final updatedProducts = [
        for (final product in currentProducts)
          (targets.contains(product.internalId) && product.type == type)
              ? product.copyWith(status: newStatus)
              : product,
      ];
      state = AsyncData(updatedProducts);

      // LocalServerService 캐시 동기화 — 옛 상태로 남으면 키오스크가 품절 상품을
      // 계속 판다.
      try {
        LocalServerService.instance?.updateProductCache(updatedProducts);
      } catch (e) {
        logger.w('LocalServerService 캐시 업데이트 실패', error: e);
      }

      return true;
    } catch (error, stackTrace) {
      logger.e('상품 일괄 상태 변경 API 오류 (${targets.length}건)',
          error: error, stackTrace: stackTrace);
      return false;
    }
  }
}
