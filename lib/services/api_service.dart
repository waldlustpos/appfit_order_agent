// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed
import '../config/app_env.dart'; // AppEnv 추가
import 'package:dio/dio.dart'; // Added for DioException
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import '../models/order_model.dart';
import '../models/order_menu_model.dart';
import '../models/menu_option_model.dart';
import '../models/store_model.dart';
import '../models/product_model.dart';
import '../models/membership_model.dart';
// import 'api_service_interface.dart'; // Removed
import 'appfit/appfit_providers.dart';
import 'secure_storage_service.dart';
import 'package:appfit_core/appfit_core.dart'; // import 추가
// import 'appfit/api_routes.dart'; // Removed
import '../models/enums/order_action.dart';
import '../exceptions/api_exceptions.dart'; // Added for precise error catching

part 'api_service.g.dart';

/// AppFit API 서비스 Provider (이제 메인 ApiService)
@Riverpod(keepAlive: true)
ApiService apiService(Ref ref) {
  return ApiService(ref);
}

// Legacy 호환성을 위한 별칭 (점진적 제거 예정)
final appFitApiServiceProvider = Provider<ApiService>((ref) {
  return ref.watch(apiServiceProvider);
});

class ApiService {
  // ignore: unused_field
  final Ref _ref;

  ApiService(this._ref);

  String _encrypt(String text) {
    if (text.isEmpty) return text;
    try {
      final aesKey = AppEnv.aesKey;
      return CryptoUtils.encryptAesGcm(text, aesKey);
    } catch (e) {
      logger.e('[AppFit API] Encryption failed: $e');
      return text;
    }
  }

  // Dio get _dio => _ref.read(appFitDioProvider);

  /// 프로젝트 정보 조회
  /// 프로젝트 정보 조회
  Future<Map<String, dynamic>> getProjectInfo() async {
    try {
      final dio = _ref.read(appFitDioProvider);
      // getProjectInfo는 Project ID 헤더가 필요 없음
      final response = await dio.get(ApiRoutes.projectInfo);

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final projectId = data['projectId'] as String;
        final apiKey = data['apiKeyInfo']?['apiKey'] as String?;

        // TokenManager를 통해 Credentials 저장 (패키지 내부 로직 사용)
        final tokenManager = _ref.read(appFitTokenManagerProvider);

        String finalApiKey = apiKey ?? '';
        if (apiKey != null) {
          try {
            final aesKey = AppEnv.aesKey;
            final decryptedKey = CryptoUtils.decryptAesGcm(apiKey, aesKey);
            finalApiKey = decryptedKey;
            logger.i('[AppFit API] API Key decrypted successfully.');
          } catch (e) {
            logger.e('[AppFit API] Failed to decrypt API Key: $e');
            // 복호화 실패 시 원본 사용
          }
        }

        await tokenManager.saveProjectCredentials(projectId, finalApiKey);
        logger.i('[AppFit API] Project credentials saved via TokenManager.');
        logger.i(AppFitConfig.getConfigSummary());

        // Legacy 호환성을 위해 SecureStorageService에도 저장 (필요 시 제거 가능)
        // final secureStorage = SecureStorageService();
        // await secureStorage.write(SecureStorageService.appFitProjectId, projectId);
        // ...

        return data;
      } else {
        throw Exception('프로젝트 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<StoreModel> getStoreInfo(String storeId) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      // header에 "Waldlust-Project-ID"는 AppFitDioProvider에서 기본 설정됨
      final response = await dio.get(ApiRoutes.shopInfo(storeId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;

        // AppFit 데이터를 StoreModel로 매핑
        return StoreModel(
          storeId: data['shopCode'] as String? ?? storeId,
          name: data['name'] as String? ?? 'Unknown',
          isOpen: data['operatingStatus'] == 'OPEN',
        );
      } else {
        throw Exception('매장 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<List<OrderModel>> getNewOrders(
    String storeId, {
    String? startDate,
    String? endDate,
  }) async {
    // 폴링 시에는 'NEW' 상태의 주문만 가져오도록 필터를 적용합니다.
    return getOrders(storeId,
        startDate: startDate, endDate: endDate, orderStatus: OrderStatus.NEW);
  }

  Future<bool> updateOrderStatus(
    String storeId,
    OrderStatus status,
    String orderId, {
    String? cancelReason,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      String action = '';
      int readyTime = 0;

      switch (status) {
        case OrderStatus.PREPARING:
          action = OrderAction.ACCEPT.name;
          readyTime = int.tryParse(cancelReason ?? '0') ?? 0;
          break;
        case OrderStatus.READY:
          action = OrderAction.PICKUP_REQUEST.name;
          break;
        case OrderStatus.DONE:
          action = OrderAction.DONE.name;
          break;
        default:
          logger
              .w('[AppFit API] updateOrderStatus: 지원하지 않는 상태 변경입니다. ($status)');
          return false;
      }

      final response = await dio.put(ApiRoutes.orderUpdate(orderId), data: {
        'action': action,
        'readyTime': readyTime,
      });

      return response.statusCode == 200;
    } catch (e, s) {
      // Dio/AppFitCore에서 이미 상세한 에러 로그를 남겼으므로, 여기서는 콘솔용 로그만 남김
      logger.i('[AppFit API] updateOrderStatus 실패: $e');
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> && data['code'] == 'INVALID_ORDER_STATUS') {
          String message = data['message']?.toString() ?? '유효하지 않은 주문 상태입니다.';
          try {
            final currentOrder = await getOrder(orderId);
            message = switch (currentOrder.status) {
              OrderStatus.CANCELLED => '취소된 주문입니다.',
              OrderStatus.READY     => '이미 픽업 요청된 주문입니다.',
              OrderStatus.DONE      => '이미 완료된 주문입니다.',
              OrderStatus.PREPARING => '이미 수락된 주문입니다.',
              _                     => message,
            };
          } catch (_) {
            // 조회 실패 시 원본 서버 메시지 유지
          }
          throw ApiException(message, e, e.stackTrace);
        }
      }
      return false;
    }
  }

  Future<OrderModel> getOrder(String orderId, {String? storeId}) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      // AppFit: /v0/orders/{orderNo}
      final response = await dio.get(ApiRoutes.orderDetail(orderId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;

        // 1. 주문 기본 정보 매핑
        final totalAmount = (data['totalAmount'] as num).toDouble();
        final totalDiscount = (data['totalDiscount'] as num).toDouble();

        final orderNo = data['orderNo'].toString(); // 고유 식별자 (Long)
        final shopOrderNo = data['shopOrderNo'].toString(); // 매장 표시 번호 (Short)
        final displayOrderNo = data['displayOrderNo']?.toString() ?? ''; // 고객 표시 번호

        // 2. 메뉴 목록 (orderLines) 매핑
        List<OrderMenuModel> menuList = [];
        if (data.containsKey('orderLines') && data['orderLines'] != null) {
          final lines = data['orderLines'] as List;
          menuList = lines.map((line) {
            // 옵션 목록 (orderOptions) 매핑
            List<MenuOptionModel> optionList = [];
            if (line.containsKey('orderOptions') &&
                line['orderOptions'] != null) {
              final options = line['orderOptions'] as List;
              optionList = options.map((opt) {
                return MenuOptionModel(
                  shopOptionId: opt['shopOptionId']?.toString() ?? '',
                  optionName: opt['optionName']?.toString() ?? '',
                  optionPrice: (opt['optionPrice'] as num?)?.toDouble() ?? 0.0,
                  qty: (opt['qty'] as num?)?.toInt() ?? 0,
                );
              }).toList();
            }

            return OrderMenuModel(
              orderNo: line['orderNo']?.toString() ?? '',
              shopItemId: line['shopItemId']?.toString() ?? '',
              qty: (line['qty'] as num?)?.toInt() ?? 0,
              itemName: line['itemName']?.toString() ?? '',
              itemPrice: (line['itemPrice'] as num?)?.toDouble() ?? 0.0,
              totalAmount: (line['totalAmount'] as num?)?.toDouble() ?? 0.0,
              discPrc: (line['discPrc'] as num?)?.toDouble() ?? 0.0,
              vatPrc: (line['vatPrc'] as num?)?.toDouble() ?? 0.0,
              options: optionList,
            );
          }).toList();
        }

        final order = OrderModel(
          orderNo: orderNo, // orderNo (Long ID)
          shopOrderNo: shopOrderNo, // shopOrderNo (Short ID)
          displayOrderNo: displayOrderNo,
          orderStatus: data['orderStatus'] as String,
          orderedAt: data['createdAt'] != null
              ? DateTime.parse(data['createdAt'])
              : DateTime.now(),
          totalAmount: totalAmount,
          status: _mapAppFitOrderStatus(data['orderStatus'] as String),
          storeId: data['shopCode'] as String? ?? storeId ?? '',
          userId: data['userId']?.toString() ?? '',
          ordererName: data['orderName'] as String? ?? '주문',
          orderCount: (data['totalQty'] as num).toString(),
          paymentAmount: totalAmount - totalDiscount,
          discountAmount: totalDiscount,
          paymentType: data['paymentMethod'] as String? ?? 'CARD',
          paymentCode: '1',
          menus: menuList,
          userName: data['userNickname'] as String?,
          tel: data['userPhone'] as String?,
          note: data['note'] as String?,
          orderType: data['orderType'] as String? ?? 'IN_SHOP',
          kdsOrderType: 0,
          kioskId: '',
        );

        return order;
      } else {
        throw Exception('주문 상세 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      // Dio/AppFitCore에서 이미 로그를 남겼으므로 리스로우만 수행
      rethrow;
    }
  }

  Future<bool> cancelOrder(String orderId) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      final response = await dio.post(ApiRoutes.orderCancel(orderId), data: {
        'action': OrderAction.REJECT.name,
        'reason': 'SHOP_REQUEST',
        'message': '상점 요청으로 취소되었습니다.',
      });

      return response.statusCode == 200;
    } catch (e) {
      logger.i('[AppFit API] cancelOrder 실패: $e');
      return false;
    }
  }

  Future<List<OrderModel>> getOrders(
    String storeId, {
    String? startDate,
    String? endDate,
    OrderStatus? orderStatus,
  }) async {
    const int pageSize = 500; // TEST: 페이지네이션 검증용 소형 사이즈
    int currentPage = 0;
    final List<OrderModel> allOrders = [];

    while (true) {
      final (orders, isLast) = await _getOrdersPage(storeId,
          startDate: startDate,
          endDate: endDate,
          orderStatus: orderStatus,
          page: currentPage,
          size: pageSize);

      allOrders.addAll(orders);
      logger.i('[getOrders] 페이지 $currentPage 조회완료: ${orders.length}건 수신 (누적: ${allOrders.length}건)');

      if (isLast) break;
      currentPage++;
    }

    logger.i('[getOrders] 전체 주문 로딩 완료: 총 ${allOrders.length}건, ${currentPage + 1}페이지');
    return allOrders;
  }

  /// 내부 전용: 단일 페이지 조회 + slice.last 반환
  Future<(List<OrderModel>, bool)> _getOrdersPage(
    String storeId, {
    String? startDate,
    String? endDate,
    OrderStatus? orderStatus,
    int page = 0,
    int size = 5,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final Map<String, dynamic> queryParams = {
        'shopCode': storeId,
        'page': page,
        'size': size,
        'sortBy': 'CreatedAtDesc',
      };

      if (startDate != null) queryParams['from'] = startDate;

      // endDate가 날짜 형식(yyyy-MM-dd)인지 확인 (폴링 시 시퀀스 번호가 올 수 있음)
      if (endDate != null && endDate.contains('-')) {
        queryParams['to'] = endDate;
      }

      if (orderStatus != null) queryParams['status'] = [orderStatus.name];

      // AppFit: /v0/orders
      final response =
          await dio.get(ApiRoutes.orders, queryParameters: queryParams);

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final content = data['content'] as List<dynamic>;

        final List<OrderModel> orders = content.map((item) {
          final paymentAmount = (item['paymentAmount'] as num).toDouble();
          final totalAmount = (item['totalAmount'] as num).toDouble();
          final totalDiscount = (item['totalDiscount'] as num).toDouble();
          final String orderId = item['orderNo'].toString(); // 내부 식별용
          final String shopOrderNo = item['shopOrderNo'].toString(); // 표시용
          final String displayOrderNo = item['displayOrderNo']?.toString() ?? ''; // 고객 표시 번호

          return OrderModel(
            orderNo: orderId,
            shopOrderNo: shopOrderNo,
            displayOrderNo: displayOrderNo,
            orderStatus: item['status'] as String,
            orderedAt: item['createdAt'] != null
                ? DateTime.parse(item['createdAt'])
                : DateTime.now(),
            totalAmount: totalAmount,
            status: _mapAppFitOrderStatus(item['status'] as String),
            storeId: item['shopCode'] as String,
            userId: item['userId']?.toString() ?? '',
            ordererName: item['orderName'] as String? ?? '주문',
            orderCount: (item['totalQty'] as num).toString(),
            paymentAmount: paymentAmount,
            discountAmount: totalDiscount,
            paymentType: item['paymentMethod'] as String? ?? 'CARD',
            paymentCode: '1',
            menus: [], // 목록에서는 상세 메뉴 없음
            orderType: item['orderType'] as String? ?? 'IN_SHOP',
            kdsOrderType: 0,
            kioskId: '',
            userName: item['userName'] as String?,
            tel: item['userContact'] as String?,
          );
        }).toList();

        final slice = data['slice'] as Map<String, dynamic>?;
        final isLast = slice?['last'] as bool? ?? true;
        logger.i('[getOrders] 페이지 $page 응답: ${orders.length}건, isLast=$isLast, isEmpty=${slice?['empty']}');

        return (orders, isLast);
      } else {
        throw Exception('주문 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// AppFit 전용: 페이징 지원 주문 목록 조회 (단일 페이지)
  Future<List<OrderModel>> getOrdersPaged(
    String storeId, {
    String? startDate,
    String? endDate,
    OrderStatus? orderStatus,
    int page = 0,
    int size = 500,
  }) async {
    final (orders, _) = await _getOrdersPage(storeId,
        startDate: startDate,
        endDate: endDate,
        orderStatus: orderStatus,
        page: page,
        size: size);
    return orders;
  }

  OrderStatus _mapAppFitOrderStatus(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING':
      case 'NEW':
        return OrderStatus.NEW;
      case 'ACCEPTED':
      case 'PREPARING':
        return OrderStatus.PREPARING;
      case 'READY':
        return OrderStatus.READY;
      case 'DONE':
      case 'COMPLETED':
        return OrderStatus.DONE;
      case 'CANCELED':
      case 'CANCELLED':
      case 'FAILED':
        return OrderStatus.CANCELLED;
      default:
        return OrderStatus.CANCELLED;
    }
  }

  Future<bool> updateShopOperatingStatus(String storeId, bool isOn) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final String status = isOn ? 'OPEN' : 'CLOSED';

      final response =
          await dio.put(ApiRoutes.shopOperatingStatus(storeId), data: {
        'shopOperatingStatus': status,
      });

      return response.statusCode == 200;
    } catch (e) {
      logger.e('[AppFit API] updateSaleStatus 오류: $e');
      _handleError(e, '매장 상태 업데이트에 실패했습니다.');
    }
  }

  Future<List<ProductModel>> getShopCategories(String storeId) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      // AppFit: /v0/shops/{shopCode}/categories
      final response = await dio.get(ApiRoutes.shopCategories(storeId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final List<ProductModel> allProducts = [];

        // 1. 카테고리별 상품(items) 처리
        if (data.containsKey('categories')) {
          final categories = data['categories'] as List<dynamic>;
          for (var category in categories) {
            final categoryName = category['categoryName'] as String;
            final categoryCode = category['categoryPosId'] as String;
            final items = category['items'] as List<dynamic>;

            for (var item in items) {
              allProducts.add(ProductModel(
                productId: item['itemPosId'] as String, // prdId용 (POS ID)
                internalId: item['shopItemId'] as String, // API용 (UUID)
                productName: item['itemName'] as String,
                categoryName: categoryName,
                categoryCode: categoryCode,
                menuPrice: (item['salePrice'] as num).toInt(),
                status: _mapAppFitStatus(item['status'] as String),
                type: ProductType.item,
              ));
            }
          }
        }

        // 2. 상위 레벨 옵션(options) 처리
        if (data.containsKey('options')) {
          final options = data['options'] as List<dynamic>;
          for (var option in options) {
            allProducts.add(ProductModel(
              productId: option['optionPosId'] as String, // prdId용 (POS ID)
              internalId: option['optionId'] as String, // API용 (UUID)
              productName: option['optionName'] as String,
              categoryName: '옵션', // 옵션 전용 카테고리명
              categoryCode: (option['categoryCode'] ??
                      option['optionCategoryId'] ??
                      option['categoryPosId'] ??
                      '')
                  .toString(),
              menuPrice: (option['salePrice'] as num).toInt(),
              status: _mapAppFitStatus(option['status'] as String),
              type: ProductType.option,
            ));
          }
        }

        return allProducts;
      } else {
        throw Exception('상품 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// AppFit 상태 코드를 ProductStatus로 매핑
  ProductStatus _mapAppFitStatus(String appFitStatus) {
    switch (appFitStatus.toUpperCase()) {
      case 'ON_SALE':
      case 'SALE':
        return ProductStatus.sale; // OS
      case 'SOLD_OUT':
        return ProductStatus.soldOut; // SO
      case 'DISCONTINUED':
      case 'HIDDEN':
      case 'PENDING':
      default:
        return ProductStatus.hidden; // HD
    }
  }

  /// ProductStatus를 AppFit 상태 코드로 매핑
  String _reverseMapAppFitStatus(ProductStatus status) {
    switch (status) {
      case ProductStatus.sale:
        return 'ON_SALE';
      case ProductStatus.soldOut:
        return 'SOLD_OUT';
      case ProductStatus.hidden:
        return 'DISCONTINUED';
    }
  }

  Future<bool> updateItemStatus(
    String productId,
    String storeId,
    ProductStatus status,
  ) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      // 1. 현재 상품 목록에서 타입을 찾아야 함
      final products = await getShopCategories(storeId);
      final product = products.firstWhere(
        (p) => p.productId == productId,
        orElse: () => throw Exception('상품을 찾을 수 없습니다: $productId'),
      );

      final String appFitStatus = _reverseMapAppFitStatus(status);
      final bool isItem = product.type == ProductType.item;
      final String endpoint = isItem
          ? ApiRoutes.shopItemStatus(storeId)
          : ApiRoutes.shopOptionStatus(storeId);

      final Map<String, dynamic> body = isItem
          ? {
              'itemIds': [
                product.internalId
              ], // productId(POS ID) 대신 internalId(UUID) 사용
              'status': appFitStatus,
            }
          : {
              'optionIds': [
                product.internalId
              ], // productId(POS ID) 대신 internalId(UUID) 사용
              'status': appFitStatus,
            };

      final response = await dio.put(endpoint, data: body);

      if (response.statusCode == 200) {
        return true;
      } else {
        logger.e('[AppFit API] updateProductStatus 실패: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      logger.e('[AppFit API] updateProductStatus 오류: $e');
      _handleError(e, '상품 상태 업데이트에 실패했습니다.');
    }
  }

  Future<MembershipInfo> getMembershipInfoByPhone(
    String phone,
    String storeId,
  ) async {
    logger.w('[AppFit API] getMembershipInfoByPhone - 아직 구현되지 않았습니다.');
    // TODO: 신규 플랫폼 API 구현
    throw UnimplementedError(
        'AppFit API getMembershipInfoByPhone은 아직 구현되지 않았습니다.');
  }

  // getRewardHistory deprecated - use new individual methods in provider

  Future<bool> cancelCoupon(
    String couponId,
    String storeId,
    String orderId,
  ) async {
    try {
      await cancelCouponUse(couponId, storeId);
      return true;
    } catch (e) {
      logger.e('[AppFit API] cancelCoupon 오류: $e');
      return false;
    }
  }

  Future<bool> useCouponWithUserID(
    String couponId,
    String storeId,
    String orderId,
  ) async {
    try {
      // AppFit: items가 필요하므로 빈 리스트 또는 기본값 전달
      // 실제 주문 시에는 validateCoupon/useCoupon을 직접 사용하므로
      // 여기서는 회원 조회 화면에서의 개별 사용을 가정 (AppFit 정책에 따라 다를 수 있음)
      final result = await useCoupon(couponId, storeId, items: []);
      return result.isNotEmpty;
    } catch (e) {
      logger.e('[AppFit API] useCouponWithUserID 오류: $e');
      _handleError(e, '쿠폰 사용에 실패했습니다.');
    }
  }

  Future<bool> useCouponWithoutUserID(String couponId, String storeId) async {
    logger.w('[AppFit API] useCouponWithoutUserID - 아직 구현되지 않았습니다.');
    // TODO: 신규 플랫폼 API 구현
    throw UnimplementedError(
        'AppFit API useCouponWithoutUserID는 아직 구현되지 않았습니다.');
  }

  // Removed unused point methods

  Future<bool> earnStamp(
    String userId,
    String storeId,
    String orderId,
    int stampCount,
  ) async {
    try {
      final encryptedUserNo = _encrypt(userId);
      final dio = _ref.read(appFitDioProvider);
      final secureStorage = SecureStorageService();
      final projectId =
          await secureStorage.read(SecureStorageService.appFitProjectId);

      final response = await dio.post(ApiRoutes.stampEarn, data: {
        'projectId': projectId,
        'shopCode': storeId,
        'userSearchNo': encryptedUserNo,
        'stampCount': stampCount,
        'orderId': orderId,
        'requestSource': 'AGENT',
        'items': [], // 필요 시 주문 아이템 목록 전달 가능
      });
      return response.statusCode == 200;
    } catch (e) {
      logger.e('[AppFit API] saveStamp 오류: $e');
      _handleError(e, '스탬프 적립에 실패했습니다.');
    }
  }

  // savePoint REMOVED

  Future<Map<String, dynamic>> getStampHistory(
    String userSearchNo,
    String storeId, {
    int page = 0,
    int size = 50,
  }) async {
    try {
      final encryptedUserNo = _encrypt(userSearchNo);
      final dio = _ref.read(appFitDioProvider);

      final response = await dio.get(ApiRoutes.stampHistory, queryParameters: {
        'shopCode': storeId,
        'userSearchNo': encryptedUserNo,
        'page': page,
        'size': size,
      });

      if (response.statusCode == 200) {
        return response.data['data'] as Map<String, dynamic>;
      } else {
        throw Exception('스탬프 내역 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] getStampHistory 오류: $e');
      _handleError(e, '스탬프 내역 조회에 실패했습니다.');
    }
  }

  Future<bool> cancelStamp(String rewardId) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final response = await dio.post(ApiRoutes.stampCancel, data: {
        'rewardId': rewardId,
      });
      return response.statusCode == 200;
    } catch (e) {
      logger.e('[AppFit API] cancelSavedStamp 오류: $e');
      _handleError(e, '스탬프 적립 취소에 실패했습니다.');
    }
  }

  Future<Map<String, dynamic>> validateCoupon(
    String couponNo,
    String storeId, {
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final secureStorage = SecureStorageService();
      final projectId =
          await secureStorage.read(SecureStorageService.appFitProjectId);

      final response =
          await dio.post(ApiRoutes.couponValidate(couponNo), data: {
        'projectId': projectId,
        'shopCode': storeId,
        'requestSource': 'AGENT',
        'items': items,
      });

      if (response.statusCode == 200) {
        return response.data['data'] as Map<String, dynamic>;
      } else {
        throw Exception('쿠폰 검증 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] validateCoupon 오류: $e');
      _handleError(e, '쿠폰 검증에 실패했습니다.');
    }
  }

  Future<Map<String, dynamic>> useCoupon(
    String couponNo,
    String storeId, {
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final secureStorage = SecureStorageService();
      final projectId =
          await secureStorage.read(SecureStorageService.appFitProjectId);

      final response = await dio.post(ApiRoutes.couponUse(couponNo), data: {
        'projectId': projectId,
        'shopCode': storeId,
        'requestSource': 'AGENT',
        'items': items,
      });

      if (response.statusCode == 200) {
        return response.data['data'] as Map<String, dynamic>;
      } else {
        throw Exception('쿠폰 사용 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] useCoupon 오류: $e');
      _handleError(e, '쿠폰 사용에 실패했습니다.');
    }
  }

  Future<void> cancelCouponUse(
    String couponNo,
    String storeId,
  ) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final secureStorage = SecureStorageService();
      final projectId =
          await secureStorage.read(SecureStorageService.appFitProjectId);

      final response =
          await dio.put(ApiRoutes.couponUseCancel(couponNo), data: {
        'projectId': projectId,
        'shopCode': storeId,
        'requestSource': 'AGENT',
      });

      if (response.statusCode != 200) {
        throw Exception('쿠폰 사용 취소 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] cancelCouponUse 오류: $e');
      _handleError(e, '쿠폰 사용 취소에 실패했습니다.');
    }
  }

  Future<Map<String, dynamic>> getCouponHistory(
    String storeId,
    String userSearchNo, {
    int page = 0,
    int size = 10,
  }) async {
    try {
      final encryptedUserNo = _encrypt(userSearchNo);
      final dio = _ref.read(appFitDioProvider);

      final response = await dio.get(ApiRoutes.couponHistory, queryParameters: {
        'shopCode': storeId,
        'userSearchNo': encryptedUserNo,
        'page': page,
        'size': size,
      });

      if (response.statusCode == 200) {
        return response.data['data'] as Map<String, dynamic>;
      } else {
        throw Exception('쿠폰 내역 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] getCouponHistory 오류: $e');
      _handleError(e, '쿠폰 내역 조회에 실패했습니다.');
    }
  }

  Future<Map<String, dynamic>> getUserProfile(
    String storeId,
    String userSearchNo,
  ) async {
    try {
      final encryptedUserNo = _encrypt(userSearchNo);
      final dio = _ref.read(appFitDioProvider);
      final response = await dio.get(ApiRoutes.userProfile, queryParameters: {
        'shopCode': storeId,
        'userSearchNo': encryptedUserNo,
      });

      if (response.statusCode == 200) {
        return response.data;
      } else {
        throw Exception('회원 프로필 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] getUserProfile 오류: $e');
      _handleError(e, '회원 정보를 가져오는데 실패했습니다.');
    }
  }

  Future<Map<String, dynamic>> bulkCompleteOrders(
    String storeId, {
    required String from,
    required String to,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final response = await dio.put(
        ApiRoutes.bulkOrdersDone,
        data: {
          'shopCode': storeId,
          'from': from,
          'to': to,
        },
      );
      logger.i('[AppFit API] 일괄 주문 완료 처리 성공: $storeId ($from ~ $to)');
      return response.data;
    } catch (e, s) {
      logger.e('[AppFit API] 일괄 주문 완료 처리 중 오류 발생: $storeId',
          error: e, stackTrace: s);
      _handleError(e, '일괄 주문 완료 처리에 실패했습니다.');
    }
  }

  Future<List<Map<String, dynamic>>> getMigrationOptions({
    required String type,
    String? shopCode,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final Map<String, dynamic> queryParams = {
        'type': type,
      };
      if (shopCode != null) queryParams['shopCode'] = shopCode;

      final response = await dio.get(ApiRoutes.migrationOptions,
          queryParameters: queryParams);

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data['data'] as List<dynamic>;
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('옵션 마이그레이션 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e) {
      logger.e('[AppFit API] getMigrationOptions 오류: $e');
      rethrow;
    }
  }

  /// AppFit API 공통 에러 핸들링
  /// 서버에서 반환한 구체적인 에러 메시지가 있다면 이를 포함하여 ApiException 발생
  Never _handleError(dynamic e, String defaultMessage) {
    if (e is DioException) {
      final responseData = e.response?.data;
      if (responseData is Map<String, dynamic> &&
          responseData.containsKey('message')) {
        final serverMessage = responseData['message'].toString();
        logger.w('[AppFit API Error] Server message: $serverMessage');
        throw ApiException(serverMessage, e, e.stackTrace);
      }
    }
    throw ApiException(defaultMessage, e, e is Error ? e.stackTrace : null);
  }
}
