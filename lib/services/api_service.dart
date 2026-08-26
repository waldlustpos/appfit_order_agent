// import 'package:flutter_dotenv/flutter_dotenv.dart'; // Removed
import 'dart:convert'; // JsonEncoder.withIndent (카테고리 원본 응답 로깅)
import 'package:appfit_order_agent/config/app_env.dart'; // AppEnv 추가
import 'package:appfit_order_agent/core/products/shop_catalog_parser.dart';
import 'package:appfit_order_agent/providers/api_health_provider.dart'; // HTTP 건강도 기록
import 'package:dio/dio.dart'; // Added for DioException
import 'package:appfit_order_agent/dev/net_fault_injector.dart';
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

  /// API 실패의 **단계**와 **소요시간**을 파일 로그로 남긴다.
  ///
  /// 코어 인터셉터의 `[API 오류] HTTP ? {method} {path}` 는 응답이 없었다는
  /// 사실만 알려줄 뿐, 그것이 DNS/연결 단계(connectionError·connectionTimeout)인지
  /// 응답 대기 단계(receiveTimeout)인지 구분하지 못한다. 이 둘은 대응이 완전히
  /// 다르다 — 전자는 per-request `Options` 로 못 줄이고 코어의 `connectTimeout`
  /// 을 손대야 한다.
  ///
  /// 2026-08-07 매장 장애에서 소켓은 DNS 실패로 59ms 만에 즉사했는데 HTTP 는
  /// 20~27초를 끌었다. 같은 "네트워크 장애"가 아니었다는 뜻이고, 그 구분 없이는
  /// 타임아웃 전략을 정할 수 없어 이 계측을 넣는다.
  void _logApiFailure(String label, Object e, Stopwatch sw) {
    final String kind;
    final int? status;
    final String cause;
    if (e is DioException) {
      kind = e.type.name;
      status = e.response?.statusCode;
      cause = e.error?.runtimeType.toString() ?? '-';
    } else {
      kind = e.runtimeType.toString();
      status = null;
      cause = '-';
    }
    logToFile(
      tag: LogTag.SYSTEM,
      message: '[API진단] $label kind=$kind status=${status ?? '-'} '
          'cause=$cause elapsed=${sw.elapsedMilliseconds}ms',
    );
  }

  /// 건강도 기록 — 주문 파이프라인의 핵심 3요청(목록/상세/상태변경)에만 건다.
  ///
  /// 목록 조회는 폴링이 60초마다 때리므로 사실상 HTTP heartbeat 구실을 하고,
  /// 상태변경은 사용자 액션이라 장애 시 카운터를 가장 빨리 채운다.
  /// 설정·상품·멤버십 등 산발적 요청까지 넣으면 신호가 흐려지므로 제외한다.
  void _recordApiSuccess() =>
      _ref.read(apiHealthNotifierProvider.notifier).recordSuccess();

  void _recordApiFailure(Object e) =>
      _ref.read(apiHealthNotifierProvider.notifier).recordFailure(e);

  /// 개발 전용 — 무장돼 있으면 지연을 소비하고 합성 실패를 던진다.
  ///
  /// 반드시 각 메서드의 `try` **안**, 실제 `dio.*` 호출 **직전**에서 부른다.
  /// - `try` 안이어야 [_logApiFailure]·[_recordApiFailure] 가 실제 장애와
  ///   똑같이 실행된다. 전신 injector 는 `try` 밖에 있어서 강제 실패를 걸어도
  ///   건강도 배너가 안 뜨고 진단 로그도 안 남았다.
  /// - `dio.*` **직전**이어야 요청 준비 코드(상태 매핑·queryParams 조립)가
  ///   검증에서 빠지지 않고, 조기 반환하는 호출이 카운터를 헛되이 소모하지 않는다.
  ///
  /// [kAllowFaultInjection] 이 `const` 이므로 릴리즈 빌드에서는 이 메서드
  /// 본문 전체가 컴파일 타임에 제거된다.
  Future<void> _maybeInjectFault(NetFaultTarget target, String path) async {
    if (!kAllowFaultInjection) return;
    final fault = NetFaultInjector.take(target, path);
    if (fault == null) return;
    // [FAULT주입] 마커는 타협 불가 — 없으면 검증하며 만든 합성 장애 로그가
    // 나중에 진짜 장애로 오독된다. 이 로그는 Slack 업로드까지 타고 나간다.
    logToFile(
      tag: LogTag.SYSTEM,
      message: '[FAULT주입] target=${target.name} path=$path '
          'delay=${fault.delay.inMilliseconds}ms '
          'error=${fault.error?.type.name ?? 'none(slowOnly)'}',
    );
    if (fault.delay > Duration.zero) {
      await Future.delayed(fault.delay);
    }
    if (fault.error != null) throw fault.error!;
  }

  /// 프로젝트 정보 조회
  ///
  /// 응답에서 복호화된 projectId/apiKey를 반환합니다.
  /// apiKey는 호출 직후 즉시 사용(예: WebSocket connect)되며, 영구 저장은
  /// 패키지 내부의 [AppFitTokenManager.saveProjectCredentials]가 담당합니다.
  ///
  /// [storeId]는 인증 인터셉터가 Authorization 헤더에 쓸 shopCode를
  /// extra로 명시하기 위함이다 — 이 엔드포인트는 경로에 shopCode가 없는
  /// 유일한 인증 필요 호출이라, 인터셉터가 PreferenceService(KEY_MID)로
  /// 폴백하는 경로에 의존하면 "아이디저장/자동로그인" 모두 OFF인 신규
  /// 매장 최초 로그인에서 KEY_MID 가 비어 있어 헤더가 아예 안 붙는다.
  Future<({String projectId, String apiKey, Map<String, dynamic> data})>
      getProjectInfo(String storeId) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      // getProjectInfo는 Project ID 헤더가 필요 없음
      final response = await dio.get(
        ApiRoutes.projectInfo,
        options: Options(extra: {'shopCode': storeId}),
      );

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
      // 진단 로그: Authorization 헤더 부착 여부를 남겨, 이후 401 재발 시
      // "헤더가 애초에 안 붙었는지(클라이언트 버그 회귀)" 와 "헤더는 붙었는데
      // 서버가 거부했는지(서버 측 문제)"를 로그만으로 즉시 구분한다.
      if (e is DioException) {
        final hasAuthHeader =
            e.requestOptions.headers.containsKey('Authorization');
        logToFile(
          tag: LogTag.API,
          message: '[AppFit API] getProjectInfo 실패 진단: storeId=$storeId '
              'status=${e.response?.statusCode} hasAuthHeader=$hasAuthHeader',
        );
      }
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
    final sw = Stopwatch()..start();
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

      await _maybeInjectFault(
          NetFaultTarget.orderUpdate, ApiRoutes.orderUpdate(orderId));
      final response = await dio.put(ApiRoutes.orderUpdate(orderId), data: {
        'action': action,
        'readyTime': parsedReadyTime,
      });

      _recordApiSuccess();
      return response.statusCode == 200;
    } catch (e, s) {
      // Dio/AppFitCore에서 이미 상세한 에러 로그를 남겼으므로, 여기서는 콘솔용 로그만 남김
      logger.i('[AppFit API] updateOrderStatus 실패: $e');
      _logApiFailure('PUT order/$orderId', e, sw);
      _recordApiFailure(e);
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
    final sw = Stopwatch()..start();
    try {
      final dio = _ref.read(appFitDioProvider);
      await _maybeInjectFault(
          NetFaultTarget.orderDetail, ApiRoutes.orderDetail(orderId));
      // AppFit: /v1/orders/{orderNo}
      final response = await dio.get(ApiRoutes.orderDetail(orderId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;

        logToFile(
          tag: LogTag.API,
          message:
              '[getOrder] orderId=$orderId 원본 응답:\n${const JsonEncoder.withIndent('  ').convert(response.data)}',
        );

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
                  // 옵션은 아이템과 필드명이 다르다 — 서버가 optionPosId 로 내려줌.
                  itemPosId: opt['optionPosId']?.toString(),
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
              itemPosId: line['itemPosId']?.toString(),
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
          // ── 상세 전용 필드 (목록 응답에는 없다) ──────────────────────────
          payments: _parsePayments(data, totalAmount - totalDiscount),
          // 할인 배열 키도 버전마다 다르다(v0: orderDiscounts, v1: discounts).
          discounts: _mapList(data['orderDiscounts'] ?? data['discounts'],
              OrderDiscountModel.fromJson),
        );

        _recordApiSuccess();
        return order;
      } else {
        throw Exception('주문 상세 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
      // Dio/AppFitCore에서 이미 로그를 남겼으므로 리스로우만 수행
      _logApiFailure('GET order/$orderId', e, sw);
      _recordApiFailure(e);
      rethrow;
    }
  }

  /// 상세 응답의 리스트 필드 공통 파서. List 가 아니거나 원소가 Map 이 아니면
  /// 조용히 스킵한다 — 메뉴 파싱과 같은 "항목별 격리" 정책으로, 결제/할인 1건이
  /// 손상됐다고 주문 전체 조회가 실패하면 안 된다.
  static List<T> _mapList<T>(
      dynamic raw, T Function(Map<String, dynamic>) fromJson) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final e in raw) {
      if (e is! Map) continue;
      try {
        out.add(fromJson(Map<String, dynamic>.from(e)));
      } catch (err, s) {
        logger.e('주문 상세 배열 항목 파싱 실패 (스킵): $e', error: err, stackTrace: s);
      }
    }
    return out;
  }

  /// `payments[]` 파싱 + 폴백.
  ///
  /// 스키마상 required 필드지만 서버 버전·주문 경로에 따라 비어 올 수 있다.
  /// 그 경우 상위 스칼라 `paymentMethod`/`paymentStatus` 로 1건을 합성해서,
  /// 최소한 기존(결제수단 1줄) 수준의 정보는 항상 보이도록 회귀를 막는다.
  /// `paymentMethod` 마저 없으면 빈 리스트 — 위젯이 섹션 자체를 숨긴다.
  static List<OrderPaymentModel> _parsePayments(
      Map<String, dynamic> data, double paymentAmount) {
    final parsed = _mapList(data['payments'], OrderPaymentModel.fromJson);
    if (parsed.isNotEmpty) return parsed;

    final method = data['paymentMethod']?.toString() ?? '';
    if (method.isEmpty) return const [];
    logger.d('[getOrder] payments 미제공 — 상위 paymentMethod($method)로 1건 합성');
    return [
      OrderPaymentModel(
        paymentMethod: method,
        amount: paymentAmount,
        status: data['paymentStatus']?.toString() ?? 'DONE',
      ),
    ];
  }

  Future<bool> cancelOrder(String orderId,
      {required OrderCancelReason reason}) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      final isJapan = AppFitConfig.environment == AppFitEnvironment.japanLive;

      final response = await dio.post(
        ApiRoutes.orderCancel(orderId),
        data: {
          'action': OrderAction.REJECT.name,
          'reason': _cancelReasonCode(reason),
        },
        options: isJapan ? Options(headers: {'Accept-Language': 'ja'}) : null,
      );
      logger.i('[AppFit API] cancelOrder ${reason.name}');

      return response.statusCode == 200;
    } catch (e, s) {
      logger.i('[AppFit API] cancelOrder 실패: $e');
      return false;
    }
  }

  /// 서버 `OrderCancelReason` enum 이 현재 승인하는 코드 화이트리스트.
  ///
  /// 앱이 서버보다 먼저 새 사유(예: ORDER_SURGE, 2026-08 기준 서버 미반영)를
  /// 추가하면 그대로 보낼 경우 서버가 JSON parse error 로 400 을 낸다. 목록에
  /// 없는 코드는 `OTHER` 로 폴백해서 보내며, 화이트리스트 밖 사유는 서버 쪽에서
  /// 구분 정보가 유실된다. 서버가 새 코드를 지원하면 이 목록에 추가한다.
  static const Set<String> _serverCancelReasonCodes = {
    'SHOP_REQUEST',
    'SHOP_CLOSED',
    'CUSTOMER_REQUEST',
    'SOLD_OUT',
    'ORDER_SURGE',
    'INGREDIENT_SHORTAGE',
    'SYSTEM_ERROR',
    'OTHER',
  };

  String _cancelReasonCode(OrderCancelReason reason) {
    final name = reason.name;
    if (_serverCancelReasonCodes.contains(name)) return name;
    logger.w('[AppFit API] cancelOrder reason $name 서버 미지원 — OTHER 로 폴백');
    return 'OTHER';
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
    final sw = Stopwatch()..start();
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

      await _maybeInjectFault(NetFaultTarget.orders, ApiRoutes.orders);
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

        _recordApiSuccess();
        return (orders, isLast);
      } else {
        throw Exception('주문 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
      _logApiFailure('GET orders(page=$page)', e, sw);
      _recordApiFailure(e);
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

  /// 매장 카테고리 + 상품 + 옵션 조회.
  ///
  /// 서버 `categories[]` 는 소속 상품(`items`)이 0개인 카테고리도 내려준다. 상품
  /// 목록으로 평탄화하면 빈 카테고리는 흔적이 남지 않아 사라지므로, 카테고리를
  /// 상품과 분리해 함께 반환한다(상품관리 좌측 목록 정본).
  ///
  /// 응답 → 모델 변환은 [parseShopCatalog] (순수 함수)가 담당한다.
  Future<({List<ProductModel> products, List<ShopCategoryModel> categories})>
      getShopCatalog(String storeId) async {
    try {
      final dio = _ref.read(appFitDioProvider);
      // AppFit: /v0/shops/{shopCode}/categories/items
      //   구 `/categories` 의 매장 전역 평면 `options[]` 대신 상품별 optionGroups
      //   중첩을 내려준다. 옵션 그룹 POS 코드가 응답에 실려 오므로 별도의
      //   `/v0/migration/options` 조인이 필요 없다.
      final response = await dio.get(ApiRoutes.shopCategoryItems(storeId));

      if (response.statusCode == 200) {
        final data = response.data['data'] as Map<String, dynamic>;

        // 서버가 실제로 내려주는 카테고리 원본 구조 확인용 로그.
        // items 는 카테고리당 다수인 데다 옵션그룹까지 중첩돼 있어, 요약(개수)만
        // 남기고 나머지 키는 그대로 찍는다.
        final rawCategories =
            (data['categories'] as List<dynamic>?) ?? const [];
        logger.i('[AppFit API] 카테고리 응답 수신: ${rawCategories.length}개\n'
            '${const JsonEncoder.withIndent('  ').convert(rawCategories.map((c) {
          if (c is! Map<String, dynamic>) return c;
          final m = Map<String, dynamic>.from(c);
          final items = m['items'] as List<dynamic>?;
          if (items != null) m['items'] = '${items.length}개 (생략)';
          return m;
        }).toList())}');

        return parseShopCatalog(data);
      } else {
        throw Exception('상품 목록 조회 실패: ${response.statusCode}');
      }
    } catch (e, s) {
      rethrow;
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

  /// 같은 타입(ITEM/OPTION) 상품 여러 건의 판매 상태를 **PUT 1회**로 변경한다.
  ///
  /// 서버 스키마는 원래 `itemIds`/`optionIds` 배열이라 벌크가 기본형인데, 앱은
  /// 1건씩 보내면서 매 호출 타입을 알아내려고 카탈로그 전체를 다시 GET 했다.
  /// 호출부가 이미 들고 있는 [internalIds]/[type] 을 그대로 받아 그 왕복을 없앴다.
  ///
  /// 상품관리의 그룹은 `(상품명, 타입)` 으로 묶여 **단일 타입**이 보장되므로
  /// 엔드포인트가 갈릴 일이 없다 — 이 전제가 깨지면 itemIds/optionIds 를 한
  /// 요청에 섞어 보내게 된다.
  ///
  /// [internalIds] 는 플랫폼 UUID(`shopItemId`/`optionId`)다. POS ID(`productId`)가
  /// 아니다.
  Future<bool> updateItemsStatus({
    required String storeId,
    required ProductType type,
    required List<String> internalIds,
    required ProductStatus status,
  }) async {
    // 빈 값은 서버가 거부하고, 중복 UUID 는 보낼 이유가 없다.
    final ids = {...internalIds.where((id) => id.isNotEmpty)}.toList();
    if (ids.isEmpty) {
      logger.w('[AppFit API] updateItemsStatus: 유효한 internalId 가 없어 호출 생략');
      return false;
    }
    if (ids.length > 50) {
      // 서버측 상한이 문서화돼 있지 않다. 실제 그룹 크기는 2~5라 청크 분할 없이
      // 로그로 감시만 한다 — 초과 사례가 나오면 그때 분할을 검토한다.
      logger.w('[AppFit API] updateItemsStatus: 대상 ${ids.length}건 — 상한 확인 필요');
    }

    try {
      final dio = _ref.read(appFitDioProvider);
      final bool isItem = type == ProductType.item;
      final String endpoint = isItem
          ? ApiRoutes.shopItemStatus(storeId)
          : ApiRoutes.shopOptionStatus(storeId);

      final Map<String, dynamic> body = {
        isItem ? 'itemIds' : 'optionIds': ids,
        'status': _reverseMapAppFitStatus(status),
      };

      final response = await dio.put(endpoint, data: body);

      if (response.statusCode == 200) {
        return true;
      } else {
        // 벌크는 일부만 반영될 여지가 있어 상태코드뿐 아니라 응답 본문도 남긴다.
        logger.e('[AppFit API] updateItemsStatus 실패: '
            '${response.statusCode} / ${response.data}');
        return false;
      }
    } catch (e, s) {
      logger.e('[AppFit API] updateItemsStatus 오류: $e');
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

  // getMigrationOptions(`/v0/migration/options`) 는 제거됨.
  //   옵션의 categoryCode(= 옵션그룹 POS 코드)를 채우려고 카탈로그 조회 뒤에
  //   한 번 더 호출하던 조인이었으나, `/categories/items` 응답이 optionGroupPosId
  //   를 직접 실어주면서 불필요해졌다. 필요해지면 git 이력에서 복원할 것.

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
