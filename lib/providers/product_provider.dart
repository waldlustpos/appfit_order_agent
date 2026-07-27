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

/// 매장 카탈로그(카테고리 + 상품) 로드 — 서버 응답의 정본.
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
    // 1. 상품 카테고리/상품 목록 로드 (카탈로그 본체 — 실패하면 치명적)
    final catalog = await apiService.getShopCatalog(finalStoreId);

    // 2. 옵션 마이그레이션 데이터는 **보조 정보**라 실패를 삼킨다.
    //    라벨 sub-info 분류는 주문 응답의 optionGroupPosId 가 정본이 되어
    //    이 값에 의존하지 않는다. 과거에는 이 호출이 timeout 되면 catch 로
    //    빠지면서 상품 목록 전체가 빈 배열이 됐다(카탈로그 통째 유실).
    List<Map<String, dynamic>> migrationOptions = const [];
    try {
      migrationOptions = await apiService.getMigrationOptions(
          type: 'SHOP', shopCode: finalStoreId);
    } catch (e) {
      logger.w('ShopCatalog build: 옵션 마이그레이션 조회 실패 — 카탈로그는 유지', error: e);
    }

    final baseProducts = catalog.products;

    logger.i('ShopCatalog build: Loaded ${baseProducts.length} base products, '
        '${catalog.categories.length} categories and ${migrationOptions.length} migration options.');

    // 3. 마이그레이션 데이터를 맵으로 변환 (ID -> posCategoryId)
    final migrationMap = {
      for (var item in migrationOptions)
        item['id'].toString(): item['posCategoryId']?.toString() ?? ''
    };

    // 4. 기존 상품 목록과 병합 (옵션 상품의 카테고리 코드 보완)
    int mergedCount = 0;
    final products = baseProducts.map((product) {
      if (product.type == ProductType.option) {
        final migrationCategoryCode = migrationMap[product.productId.trim()];
        if (migrationCategoryCode != null && migrationCategoryCode.isNotEmpty) {
          mergedCount++;
          return product.copyWith(categoryCode: migrationCategoryCode);
        }
      }
      return product;
    }).toList();

    logger.i(
        'ShopCatalog build: Merged $mergedCount options with migration data. Total products: ${products.length}');

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

  // 상품 상태 업데이트 (기존 로직과 거의 동일, storeId 가져오는 부분만 확인)
  Future<bool> updateProductStatus(
      String productId, ProductStatus newStatus) async {
    // 현재 Product provider의 상태를 먼저 확인
    if (!state.hasValue) {
      logger.w(
          'Cannot update product status: Product list not loaded yet (current state: ${state.toString()}).');
      return false;
    }

    final currentProducts = state.value!; // 이미 로드된 상품 목록

    // storeId는 storeProvider에서 최신 값을 읽어옴
    // updateProductStatus는 build와 독립적으로 실행되므로, storeProvider의 현재 값을 읽는 것이 적절
    final storeAsyncValue = ref.read(storeProvider);
    if (!storeAsyncValue.hasValue ||
        storeAsyncValue.value == null ||
        storeAsyncValue.value!.storeId.isEmpty) {
      logger.e(
          'Cannot update product status: Store ID not available from storeProvider. StoreState: ${storeAsyncValue.toString()}');
      return false;
    }
    final storeId = storeAsyncValue.value!.storeId;

    logger.i(
        'Updating product status for product $productId to $newStatus in store $storeId');

    try {
      final apiService = ref.read(apiServiceProvider);
      final success =
          await apiService.updateItemStatus(productId, storeId, newStatus);

      if (success) {
        logToFile(
            tag: LogTag.UI_ACTION,
            message: '상품상태 업데이트 성공: $productId : $newStatus');
        final updatedProducts = currentProducts.map((product) {
          if (product.productId == productId) {
            return product.copyWith(status: newStatus);
          }
          return product;
        }).toList();
        state = AsyncData(updatedProducts); // 새 데이터로 상태 업데이트

        // LocalServerService 캐시 업데이트
        try {
          final localServer = LocalServerService.instance;
          if (localServer != null) {
            localServer.updateProductCache(updatedProducts);
          }
        } catch (e, s) {
          logger.w('LocalServerService 캐시 업데이트 실패', error: e);
        }

        logger.i(
            'Product status updated successfully locally: $productId to $newStatus');
        return true;
      } else {
        logger.e(
            'Server failed to update product status for $productId (API call was successful but server returned failure).');
        return false;
      }
    } catch (error, stackTrace) {
      logger.e('Error calling updateProductStatus API for $productId',
          error: error, stackTrace: stackTrace);
      // 필요하다면 여기서 state를 이전 상태로 롤백하거나 에러 상태로 만들 수 있습니다.
      // 예: state = AsyncError(error, stackTrace).copyWithPrevious(AsyncData(currentProducts));
      return false;
    }
  }
}
