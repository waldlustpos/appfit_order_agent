// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed
import 'package:appfit_order_agent/config/app_env.dart'; // AppEnv 추가
import 'package:dio/dio.dart'; // Added for DioException
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:appfit_order_agent/dev/order_detail_fault_injector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:appfit_order_agent/utils/logger.dart';
import 'package:appfit_order_agent/models/order_model.dart';
import 'package:appfit_order_agent/models/order_menu_model.dart';
import 'package:appfit_order_agent/models/menu_option_model.dart';
import 'package:appfit_order_agent/models/store_model.dart';
import 'package:appfit_order_agent/models/product_model.dart';
import 'package:appfit_order_agent/models/shop_category_model.dart';
import 'package:appfit_order_agent/models/membership_model.dart';
// import 'api_service_interface.dart'; // Removed
import 'package:appfit_order_agent/services/appfit/appfit_providers.dart';
import 'package:appfit_order_agent/services/secure_storage_service.dart';
import 'package:appfit_core/appfit_core.dart'; // import 추가
// import 'appfit/api_routes.dart'; // Removed
import 'package:appfit_order_agent/models/enums/order_action.dart';
import 'package:appfit_order_agent/models/enums/order_cancel_reason.dart';
import 'package:appfit_order_agent/exceptions/api_exceptions.dart'; // Added for precise error catching
import 'package:appfit_order_agent/exceptions/api_error_mapper.dart'; // DioException → 친화 ApiException 변환
import 'package:appfit_order_agent/services/platform_service.dart'; // logToFile, LogTag 사용 위해 추가

part 'api_service.g.dart';

/// AppFit API 서비스 Provider (이제 메인 ApiService)
@Riverpod(keepAlive: true)
ApiService apiService(Ref ref) {
  return ApiService(ref);
}

class ApiService {
  // ignore: unused_field
  final Ref _ref;

  ApiService(this._ref);

  String _encrypt(String text) {
    if (text.isEmpty) return text;
    try {
      final aesKey = AppEnv.aesKey;
      return CryptoUtils.encryptAesGcm(text, aesKey);
    } catch (e, s) {
      logger.e('[AppFit API] Encryption failed: $e');
      return text;
    }
  }

  // Dio get _dio => _ref.read(appFitDioProvider);

  /// 프로젝트 정보 조회
  ///
  /// 응답에서 복호화된 projectId/apiKey를 반환합니다.
  /// apiKey는 호출 직후 즉시 사용(예: WebSocket connect)되며, 영구 저장은
  /// 패키지 내부의 [AppFitTokenManager.saveProjectCredentials]가 담당합니다.
  Future<({String projectId, String apiKey, Map<String, dynamic> data})>
      getProjectInfo() async {
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
          } catch (e, s) {
            logger.e('[AppFit API] Failed to decrypt API Key: $e');
            // 복호화 실패 시 원본 사용
          }
        }

        await tokenManager.saveProjectCredentials(projectId, finalApiKey);
        logger.i('[AppFit API] Project credentials saved via TokenManager.');
        logToFile(
          tag: LogTag.API,
          message:
              '[AppFit API] saveProjectCredentials 완료: projectId.len=${projectId.length} apiKey.len=${finalApiKey.length}',
        );
        logger.i(AppFitConfig.getConfigSummary());

        return (projectId: projectId, apiKey: finalApiKey, data: data);
      } else {
        throw Exception('프로젝트 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
      // 서버가 내려준 친화 message(서버별 로케일)를 추출해 ApiException 으로
      // 변환한다. raw DioException.toString() 의 긴 영문이 다이얼로그까지
      // 노출되던 문제를 차단(서버 응답 body 없으면 i18n 폴백).
      throw mapDioErrorToApiException(e, s, context: '프로젝트 정보 조회');
    }
  }

  Future<StoreModel> getStoreInfo(String storeId) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      // header에 "Waldlust-Project-ID"는 AppFitDioProvider에서 기본 설정됨
      final response = await dio.get(ApiRoutes.shopInfo(storeId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;

        // AppFit 데이터를 StoreModel로 매핑.
        // - phone: shopContact (영수증/주문서 헤더 표시용)
        // - businessNumber: /v0/shop 응답에 아직 없음. 백엔드 추가 후 매핑 예정.
        return StoreModel(
          storeId: data['shopCode'] as String? ?? storeId,
          name: data['name'] as String? ?? 'Unknown',
          isOpen: data['operatingStatus'] == 'OPEN',
          phone: (data['shopContact'] as String?)?.trim().isNotEmpty == true
              ? (data['shopContact'] as String).trim()
              : null,
        );
      } else {
        throw Exception('매장 정보 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
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
    String? readyTime,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      String action = '';
      // 미지정(자동접수) 시 0으로 폴백
      int parsedReadyTime = int.tryParse(readyTime ?? '0') ?? 0;

      switch (status) {
        case OrderStatus.PREPARING:
          action = OrderAction.ACCEPT.name;
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
        'readyTime': parsedReadyTime,
      });

      return response.statusCode == 200;
    } catch (e, s) {
      // Dio/AppFitCore에서 이미 상세한 에러 로그를 남겼으므로, 여기서는 콘솔용 로그만 남김
      logger.i('[AppFit API] updateOrderStatus 실패: $e');
      if (e is DioException) {
        final data = e.response?.data;
        if (data is Map<String, dynamic> &&
            data['code'] == 'INVALID_ORDER_STATUS') {
          // 이 메서드 고유 비즈니스 로직: 현재 주문 상태를 재조회해 더 구체적인
          // 한국어 메시지로 보강한다(서버 message 추출/breadcrumb 은 매퍼 위임).
          String? overrideMsg;
          try {
            final currentOrder = await getOrder(orderId);
            overrideMsg = switch (currentOrder.status) {
              OrderStatus.CANCELLED => '취소된 주문입니다.',
              OrderStatus.READY => '이미 픽업 요청된 주문입니다.',
              OrderStatus.DONE => '이미 완료된 주문입니다.',
              OrderStatus.PREPARING => '이미 수락된 주문입니다.',
              _ => null,
            };
          } catch (_) {
            // 조회 실패 시 매퍼가 추출한 서버 메시지 사용
          }
          // 공통 매퍼로 서버 message 추출 + breadcrumb 기록. core 인터셉터가
          // 이 400 을 양성(benign)으로 분류해 issue 는 만들지 않으므로, 매퍼가
          // 사람이 읽기 쉬운 메시지를 breadcrumb 으로 보강해 추적 맥락을 제공한다.
          final apiEx = mapDioErrorToApiException(e, s, context: '주문 상태 변경');
          throw ApiException(overrideMsg ?? apiEx.message, e, s);
        }
      }
      return false;
    }
  }

  Future<OrderModel> getOrder(String orderId, {String? storeId}) async {
    // [DEBUG] 상세조회 강제 실패 주입 — release 빌드에서는 게이트로 비활성.
    // 개발자 옵션의 "상세조회 강제 실패" 토글로 무장. 프로덕션 영향 없음.
    if (kDebugMode) OrderDetailFaultInjector.maybeThrow(orderId);
    try {
      final dio = _ref.read(appFitDioProvider);
      // AppFit: /v1/orders/{orderNo}
      final response = await dio.get(ApiRoutes.orderDetail(orderId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;

        // 1. 주문 기본 정보 매핑
        // 사용자 정보는 v0 가 평면(userNickname/userPhone/userId), v1 이 중첩
        // (user.nickname/user.phone/user.userId) 이라 양쪽을 모두 본다.
        final userMap = data['user'] as Map<String, dynamic>?;
        final totalAmount = (data['totalAmount'] as num).toDouble();
        final totalDiscount = (data['totalDiscount'] as num).toDouble();

        final orderNo = data['orderNo'].toString(); // 고유 식별자 (Long)
        final shopOrderNo = data['shopOrderNo'].toString(); // 매장 표시 번호 (Short)
        final displayOrderNo =
            data['displayOrderNo']?.toString() ?? ''; // 고객 표시 번호

        // 2. 메뉴 목록 (orderLines) 매핑
        List<OrderMenuModel> menuList = [];
        if (data.containsKey('orderLines') && data['orderLines'] != null) {
          final lines = data['orderLines'] as List;
          menuList = lines.map((line) {
            // 옵션 목록 매핑 — 배열 키가 버전마다 다르다(v0: orderOptions, v1: options).
            List<MenuOptionModel> optionList = [];
            final rawOptions = line['orderOptions'] ?? line['options'];
            if (rawOptions is List) {
              optionList = rawOptions.map((opt) {
                return MenuOptionModel(
                  shopOptionId: opt['shopOptionId']?.toString() ?? '',
                  optionName: opt['optionName']?.toString() ?? '',
                  optionPrice: (opt['optionPrice'] as num?)?.toDouble() ?? 0.0,
                  qty: (opt['qty'] as num?)?.toInt() ?? 0,
                  // v1 전용 — 라벨 sub-info 분류(원두/온도/사이즈)의 정본.
                  optionGroupId: opt['optionGroupId']?.toString(),
                  optionGroupPosId: opt['optionGroupPosId']?.toString(),
                  optionGroupName: opt['optionGroupName']?.toString(),
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
          userId: (data['userId'] ?? userMap?['userId'])?.toString() ?? '',
          ordererName: data['orderName'] as String? ?? '주문',
          orderCount: (data['totalQty'] as num).toString(),
          paymentAmount: totalAmount - totalDiscount,
          discountAmount: totalDiscount,
          paymentType: data['paymentMethod'] as String? ?? 'CARD',
          paymentCode: '1',
          menus: menuList,
          userName: (data['userNickname'] ?? userMap?['nickname']) as String?,
          tel: (data['userPhone'] ?? userMap?['phone']) as String?,
          note: data['note'] as String?,
          orderType: data['orderType'] as String? ?? 'TAKE_OUT',
          kdsOrderType: 0,
          kioskId: '',
          source: data['orderSource'] as String? ?? '',
          // 할인 배열 키도 버전마다 다르다(v0: orderDiscounts, v1: discounts).
          discountTypes: ((data['orderDiscounts'] ?? data['discounts'])
                      as List? ??
                  const [])
              .map((e) =>
                  (e as Map<String, dynamic>)['discountType']?.toString() ?? '')
              .where((t) => t.isNotEmpty)
              .toSet()
              .toList(),
        );

        return order;
      } else {
        throw Exception('주문 상세 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
      // Dio/AppFitCore에서 이미 로그를 남겼으므로 리스로우만 수행
      rethrow;
    }
  }

  Future<bool> cancelOrder(String orderId,
      {required OrderCancelReason reason}) async {
    try {
      final dio = _ref.read(appFitDioProvider);

      final response = await dio.post(ApiRoutes.orderCancel(orderId), data: {
        'action': OrderAction.REJECT.name,
        'reason': reason.name,
        'message': _cancelReasonMessage(reason),
      });
      logger.i('[AppFit API] cancelOrder message 안보내기 ${reason.name}');

      return response.statusCode == 200;
    } catch (e, s) {
      logger.i('[AppFit API] cancelOrder 실패: $e');
      return false;
    }
  }

  String _cancelReasonMessage(OrderCancelReason reason) {
    switch (reason) {
      case OrderCancelReason.SHOP_REQUEST:
        return '매장 사정으로 취소되었습니다.';
      case OrderCancelReason.SHOP_CLOSED:
        return '매장 마감/휴무로 취소되었습니다.';
      case OrderCancelReason.CUSTOMER_REQUEST:
        return '고객 요청으로 취소되었습니다.';
      case OrderCancelReason.SOLD_OUT:
        return '품절로 취소되었습니다.';
      case OrderCancelReason.INGREDIENT_SHORTAGE:
        return '재료 소진으로 취소되었습니다.';
      case OrderCancelReason.SYSTEM_ERROR:
        return '시스템 오류로 취소되었습니다.';
      case OrderCancelReason.OTHER:
        return '기타 사유로 취소되었습니다.';
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
      logger.i(
          '[getOrders] 페이지 $currentPage 조회완료: ${orders.length}건 수신 (누적: ${allOrders.length}건)');

      if (isLast) break;
      currentPage++;
    }

    logger.i(
        '[getOrders] 전체 주문 로딩 완료: 총 ${allOrders.length}건, ${currentPage + 1}페이지');
    return allOrders;
  }

  /// 날짜(`yyyy-MM-dd`)를 v1 목록 API 가 요구하는 일시로 확장한다.
  /// 이미 일시(`T` 포함)면 그대로 둔다.
  static String _asDayStart(String v) => v.contains('T') ? v : '${v}T00:00:00';
  static String _asDayEnd(String v) => v.contains('T') ? v : '${v}T23:59:59';

  /// 내부 전용: 단일 페이지 조회 + slice.last 반환
  Future<(List<OrderModel>, bool)> _getOrdersPage(
    String storeId, {
    String? startDate,
    String? endDate,
    OrderStatus? orderStatus,
    int page = 0,
    int size = 500,
  }) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final Map<String, dynamic> queryParams = {
        'shopCode': storeId,
        'page': page,
        'size': size,
        'sortBy': 'CreatedAtDesc',
      };

      // v1 은 from/to 가 날짜(yyyy-MM-dd)가 아니라 일시(yyyy-MM-dd'T'HH:mm:ss)다.
      // 호출부는 날짜만 넘기므로 하루 전체(00:00:00~23:59:59)로 확장해 v0 의
      // "해당 날짜 전체" 의미를 보존한다. 날짜만 보내면 400 INVALID_REQUEST.
      if (startDate != null) queryParams['from'] = _asDayStart(startDate);

      // endDate가 날짜 형식(yyyy-MM-dd)인지 확인 (폴링 시 시퀀스 번호가 올 수 있음)
      if (endDate != null && endDate.contains('-')) {
        queryParams['to'] = _asDayEnd(endDate);
      }

      if (orderStatus != null) queryParams['status'] = [orderStatus.name];

      // AppFit: /v1/orders — 응답 스키마는 v0 과 동일(SliceResponse<ReadAllOrderResponse>).
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
          final String displayOrderNo =
              item['displayOrderNo']?.toString() ?? ''; // 고객 표시 번호

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
            orderType: item['orderType'] as String? ?? 'TAKE_OUT',
            kdsOrderType: 0,
            kioskId: '',
            source: item['orderSource'] as String? ?? '',
            userName: item['userName'] as String?,
            tel: item['userContact'] as String?,
          );
        }).toList();

        final slice = data['slice'] as Map<String, dynamic>?;
        final isLast = slice?['last'] as bool? ?? true;
        logger.i(
            '[getOrders] 페이지 $page 응답: ${orders.length}건, isLast=$isLast, isEmpty=${slice?['empty']}');

        return (orders, isLast);
      } else {
        throw Exception('주문 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
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
        // 미지의 상태값은 CANCELLED 로 떨어진다 — 주문이 조용히 취소로 표시되는
        // 무증상 실패라 경고를 남겨 즉시 드러나게 한다(warning 이상은 파일 기록).
        // 서버 스키마에 실재하는 'UNKNOWN' 이 대표적인 미매핑 케이스다.
        logger.w('[AppFit API] 알 수 없는 주문 상태 "$status" → CANCELLED 로 처리됨');
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
    } catch (e, s) {
      logger.e('[AppFit API] updateSaleStatus 오류: $e');
      _handleError(e, '매장 상태 업데이트에 실패했습니다.');
    }
  }

  /// 상품 목록만 필요한 호출부용 축약 (상태 변경 등).
  ///
  /// 카테고리 목록까지 필요하면 [getShopCatalog] 를 쓴다.
  Future<List<ProductModel>> getShopCategories(String storeId) async =>
      (await getShopCatalog(storeId)).products;

  /// 매장 카테고리 + 상품 조회.
  ///
  /// 서버 `categories[]` 는 소속 상품(`items`)이 0개인 카테고리도 내려준다. 상품
  /// 목록으로 평탄화하면 빈 카테고리는 흔적이 남지 않아 사라지므로, 카테고리를
  /// 상품과 분리해 함께 반환한다(상품관리 좌측 목록 정본).
  Future<({List<ProductModel> products, List<ShopCategoryModel> categories})>
      getShopCatalog(String storeId) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      // AppFit: /v0/shops/{shopCode}/categories
      final response = await dio.get(ApiRoutes.shopCategories(storeId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;
        final List<ProductModel> allProducts = [];
        final List<ShopCategoryModel> shopCategories = [];

        // 1. 카테고리별 상품(items) 처리
        if (data.containsKey('categories')) {
          final categories = data['categories'] as List<dynamic>;
          for (var category in categories) {
            // 항목별 격리 — 1건 손상 시 해당 카테고리만 스킵하고 나머지는 유지.
            final ShopCategoryModel shopCategory;
            try {
              shopCategory =
                  ShopCategoryModel.fromJson(category as Map<String, dynamic>);
            } catch (e) {
              logger.e('[AppFit API] 카테고리 파싱 실패 — 해당 항목 스킵', error: e);
              continue;
            }
            shopCategories.add(shopCategory);

            final categoryName = shopCategory.categoryName;
            final categoryCode = shopCategory.categoryCode;
            final items = (category['items'] as List<dynamic>?) ?? const [];

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
                displayOrder: (item['displayOrder'] as num).toInt(),
              ));
            }
          }
        }

        // 2. 상위 레벨 옵션(options) 처리
        if (data.containsKey('options')) {
          final options = data['options'] as List<dynamic>;
          // options 는 서버 스키마에 displayOrder 가 없어 응답 배열 순서를
          // 대신 쓰되, 큰 오프셋을 더해 아이템(실제 displayOrder) 뒤로 보낸다.
          var optionOrder = 0;
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
              displayOrder: 1000000 + optionOrder++,
            ));
          }
        }

        return (products: allProducts, categories: shopCategories);
      } else {
        throw Exception('상품 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
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
    } catch (e, s) {
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
    } catch (e, s) {
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
      final result = await useCoupon(couponId, storeId);
      return result.isNotEmpty;
    } catch (e, s) {
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
      });
      return response.statusCode == 200;
    } catch (e, s) {
      logger.e('[AppFit API] saveStamp 오류: $e');
      _handleError(e, '스탬프 적립에 실패했습니다.');
    }
  }

  // savePoint REMOVED

  /// 스탬프 내역 전체 조회. `slice.last`까지 페이지를 순회해 누적 반환한다.
  Future<List<StampInfo>> getStampHistory(
    String userSearchNo,
    String storeId,
  ) async {
    const int pageSize = 500;
    int currentPage = 0;
    final List<StampInfo> all = [];

    try {
      while (true) {
        final (stamps, isLast) = await _getStampHistoryPage(
          userSearchNo,
          storeId,
          page: currentPage,
          size: pageSize,
        );
        all.addAll(stamps);
        logger.i(
            '[getStampHistory] 페이지 $currentPage 조회완료: ${stamps.length}건 수신 (누적: ${all.length}건)');
        if (isLast) break;
        currentPage++;
      }
      logger.i(
          '[getStampHistory] 전체 스탬프 내역 로딩 완료: 총 ${all.length}건, ${currentPage + 1}페이지');
      return all;
    } catch (e, s) {
      logger.e('[AppFit API] getStampHistory 오류: $e');
      _handleError(e, '스탬프 내역 조회에 실패했습니다.');
    }
  }

  Future<(List<StampInfo>, bool)> _getStampHistoryPage(
    String userSearchNo,
    String storeId, {
    int page = 0,
    int size = 500,
  }) async {
    final encryptedUserNo = _encrypt(userSearchNo);
    final dio = _ref.read(appFitDioProvider);

    final response = await dio.get(ApiRoutes.stampHistory, queryParameters: {
      'shopCode': storeId,
      'userSearchNo': encryptedUserNo,
      'page': page,
      'size': size,
    });

    if (response.statusCode != 200) {
      throw Exception('스탬프 내역 조회 실패: ${response.statusCode}');
    }

    final data = response.data['data'] as Map<String, dynamic>;
    final content = data['content'] as List<dynamic>? ?? [];
    final stamps = content
        .map((s) => StampInfo.fromAppFitJson(s as Map<String, dynamic>))
        .toList();

    final slice = data['slice'] as Map<String, dynamic>?;
    final isLast = slice?['last'] as bool? ?? true;
    logger
        .i('[getStampHistory] 페이지 $page 응답: ${stamps.length}건, isLast=$isLast');
    return (stamps, isLast);
  }

  Future<bool> cancelStamp(String rewardId) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final response = await dio.post(ApiRoutes.stampCancel, data: {
        'rewardId': rewardId,
      });
      return response.statusCode == 200;
    } catch (e, s) {
      logger.e('[AppFit API] cancelSavedStamp 오류: $e');
      _handleError(e, '스탬프 적립 취소에 실패했습니다.');
    }
  }

  Future<Map<String, dynamic>> useCoupon(
    String couponNo,
    String storeId,
  ) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final secureStorage = SecureStorageService();
      final projectId =
          await secureStorage.read(SecureStorageService.appFitProjectId);

      // use-without-item 엔드포인트: items 없이 쿠폰을 즉시 사용한다.
      final response = await dio.post(ApiRoutes.couponUse(couponNo), data: {
        'projectId': projectId,
        'shopCode': storeId,
        'requestSource': 'AGENT',
      });

      if (response.statusCode == 200) {
        return response.data['data'] as Map<String, dynamic>;
      } else {
        throw Exception('쿠폰 사용 실패: ${response.statusCode}');
      }
    } catch (e, s) {
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
    } catch (e, s) {
      logger.e('[AppFit API] cancelCouponUse 오류: $e');
      _handleError(e, '쿠폰 사용 취소에 실패했습니다.');
    }
  }

  /// 쿠폰 내역 전체 조회 (ISSUED/USED/EXPIRED/CANCELLED 모두 포함).
  /// `slice.last`까지 페이지를 순회해 누적 반환한다.
  Future<List<CouponHistoryInfo>> getCouponHistory(
    String storeId,
    String userSearchNo,
  ) async {
    const int pageSize = 500;
    int currentPage = 0;
    final List<CouponHistoryInfo> all = [];

    try {
      while (true) {
        final (coupons, isLast) = await _getCouponHistoryPage(
          storeId,
          userSearchNo,
          page: currentPage,
          size: pageSize,
        );
        all.addAll(coupons);
        logger.i(
            '[getCouponHistory] 페이지 $currentPage 조회완료: ${coupons.length}건 수신 (누적: ${all.length}건)');
        if (isLast) break;
        currentPage++;
      }
      logger.i(
          '[getCouponHistory] 전체 쿠폰 내역 로딩 완료: 총 ${all.length}건, ${currentPage + 1}페이지');
      return all;
    } catch (e, s) {
      logger.e('[AppFit API] getCouponHistory 오류: $e');
      _handleError(e, '쿠폰 내역 조회에 실패했습니다.');
    }
  }

  Future<(List<CouponHistoryInfo>, bool)> _getCouponHistoryPage(
    String storeId,
    String userSearchNo, {
    int page = 0,
    int size = 500,
  }) async {
    final encryptedUserNo = _encrypt(userSearchNo);
    final dio = _ref.read(appFitDioProvider);

    final response = await dio.get(ApiRoutes.couponHistory, queryParameters: {
      'shopCode': storeId,
      'userSearchNo': encryptedUserNo,
      'page': page,
      'size': size,
    });

    if (response.statusCode != 200) {
      throw Exception('쿠폰 내역 조회 실패: ${response.statusCode}');
    }

    final data = response.data['data'] as Map<String, dynamic>;
    final content = data['content'] as List<dynamic>? ?? [];
    final coupons = content
        .map((c) => CouponHistoryInfo.fromAppFitJson(c as Map<String, dynamic>))
        .toList();

    final slice = data['slice'] as Map<String, dynamic>?;
    final isLast = slice?['last'] as bool? ?? true;
    logger.i(
        '[getCouponHistory] 페이지 $page 응답: ${coupons.length}건, isLast=$isLast');
    return (coupons, isLast);
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
    } catch (e, s) {
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
    } catch (e, s) {
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
