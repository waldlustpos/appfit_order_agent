import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'dart:async';
import '../models/product_model.dart';
import '../services/platform_service.dart'; // apiServiceProvider를 위해 필요
import '../services/local_server_service.dart'; // LocalServerService를 위해 필요
import 'providers.dart'; // storeProvider를 위해 필요
import 'package:appfit_order_agent/utils/logger.dart'; // logger import 추가

part 'product_provider.g.dart';

@Riverpod(keepAlive: true)
class Product extends _$Product {
  @override
  Future<List<ProductModel>> build() async {
    logger.i('Product build() 시작');

    // 매장 ID가 준비될 때까지 기다림
    final storeAsyncValue = ref.watch(storeProvider);
    final storeId = storeAsyncValue.value?.storeId;

    logger.d('Product build: StoreId $storeId');

    String? finalStoreId = storeId;
    if (finalStoreId == null || finalStoreId.isEmpty) {
      logger.d('Product build: StoreId not ready, waiting...');
      await ref.read(storeProvider.future);
      final updatedStoreId = ref.read(storeProvider).value?.storeId;
      if (updatedStoreId == null || updatedStoreId.isEmpty) {
        logger.e('Product build: StoreId still not available after wait.');
        return [];
      }
      finalStoreId = updatedStoreId;
    }

    logger
        .i('Product build: StoreId ready ($finalStoreId). Loading products...');
    final apiService = ref.read(apiServiceProvider);
    try {
      // 1. 상품 카테고리/상품 목록과 옵션 마이그레이션 데이터를 병렬로 로드
      final results = await Future.wait([
        apiService.getShopCategories(finalStoreId),
        apiService.getMigrationOptions(type: 'SHOP', shopCode: finalStoreId),
      ]);

      final List<ProductModel> baseProducts = results[0] as List<ProductModel>;
      final List<Map<String, dynamic>> migrationOptions =
          results[1] as List<Map<String, dynamic>>;

      logger.i(
          'Product build: Loaded ${baseProducts.length} base products and ${migrationOptions.length} migration options.');

      // 2. 마이그레이션 데이터를 맵으로 변환 (ID -> posCategoryId)
      final migrationMap = {
        for (var item in migrationOptions)
          item['id'].toString(): item['posCategoryId']?.toString() ?? ''
      };

      // 3. 기존 상품 목록과 병합 (옵션 상품의 카테고리 코드 보완)
      int mergedCount = 0;
      final products = baseProducts.map((product) {
        if (product.type == ProductType.option) {
          final migrationCategoryCode = migrationMap[product.productId.trim()];
          if (migrationCategoryCode != null &&
              migrationCategoryCode.isNotEmpty) {
            mergedCount++;
            return product.copyWith(categoryCode: migrationCategoryCode);
          }
        }
        return product;
      }).toList();

      logger.i(
          'Product build: Merged $mergedCount options with migration data. Total products: ${products.length}');

      // LocalServerService 캐시 업데이트
      try {
        final localServer = LocalServerService.instance;
        if (localServer != null) {
          localServer.updateProductCache(products);
        }
      } catch (e) {
        logger.w('LocalServerService 캐시 업데이트 실패', error: e);
      }

      return products;
    } catch (e, stackTrace) {
      logger.e('Product build: Error loading products',
          error: e, stackTrace: stackTrace);
      return [];
    }
  }

  // 상품 목록 새로고침 (invalidate 사용으로 변경)
  Future<void> refresh() async {
    logger.i('Product refresh: 새로고침 시작');
    // ref.invalidateSelf()를 사용하여 Provider를 무효화하고 재빌드
    ref.invalidateSelf();
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
        } catch (e) {
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
