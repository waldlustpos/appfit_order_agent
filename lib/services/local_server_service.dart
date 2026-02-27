import 'dart:io';
import 'dart:convert';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kokonut_order_agent/models/product_model.dart';
import 'package:kokonut_order_agent/utils/logger.dart';
import 'package:kokonut_order_agent/providers/product_provider.dart';

class LocalServerService {
  final WidgetRef _ref;
  HttpServer? _server;
  bool _isRunning = false;
  int _port = 8080;
  String? _localIp;
  List<ProductModel>? _cachedProducts;

  // 전역 인스턴스 관리
  static LocalServerService? _instance;
  static LocalServerService? get instance => _instance;

  LocalServerService(this._ref) {
    _instance = this;
  }

  /// 로컬 IP 주소 가져오기
  Future<String?> _getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      logger.d('LocalServerService - 네트워크 인터페이스 개수: ${interfaces.length}');

      for (var interface in interfaces) {
        logger.d(
            'LocalServerService - 인터페이스: ${interface.name}, 주소 개수: ${interface.addresses.length}');
        for (var addr in interface.addresses) {
          logger.d(
              'LocalServerService - 주소: ${addr.address}, 타입: ${addr.type}, 루프백: ${addr.isLoopback}');
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            logger.i('LocalServerService - 선택된 IP 주소: ${addr.address}');
            return addr.address;
          }
        }
      }
      logger.w('LocalServerService - 사용 가능한 IPv4 주소를 찾을 수 없음');
    } catch (e) {
      logger.e('로컬 IP 주소 가져오기 실패', error: e);
    }
    return null;
  }

  /// 서버 시작
  Future<void> startServer(
      {int port = 8080, List<ProductModel>? products}) async {
    if (_isRunning) {
      logger.w('로컬 서버가 이미 실행 중입니다.');
      return;
    }

    try {
      _port = port;
      _localIp = await _getLocalIpAddress();
      logger.d('LocalServerService - IP 주소 가져오기 결과: $_localIp');

      // 상품 데이터 캐시 (직접 전달된 데이터 또는 Provider에서 읽기)
      if (products != null) {
        _cachedProducts = List.from(products);
        logger.i(
            'LocalServerService - 전달받은 상품 데이터 캐시 완료: ${_cachedProducts!.length}개');
      } else {
        _cacheProducts();
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _isRunning = true;

      logger.i('로컬 서버 시작: http://0.0.0.0:$port');
      if (_localIp != null) {
        logger.i('로컬 IP 주소: $_localIp');
        logger.i('서버 URL: http://$_localIp:$port');
      }
      logger.i('사용 가능한 API:');
      logger.i('  GET http://10.0.2.15:8080/api/product/AL0016 - 상품 판매상태 조회');

      // 서버 이벤트 루프를 백그라운드에서 실행
      _startEventLoop();
    } catch (e, stackTrace) {
      logger.e('서버 시작 실패', error: e, stackTrace: stackTrace);
      _isRunning = false;
    }
  }

  /// 서버 이벤트 루프 시작 (백그라운드에서 실행)
  void _startEventLoop() {
    _server!.listen((HttpRequest request) {
      _handleRequest(request);
    }).onError((error) {
      logger.e('서버 이벤트 루프 오류', error: error);
    });
  }

  /// 서버 중지
  Future<void> stopServer() async {
    if (_server != null) {
      await _server!.close();
      _server = null;
      _isRunning = false;
      logger.i('로컬 서버 중지');
    }
  }

  /// 서버 상태 확인
  bool get isRunning => _isRunning;
  int get port => _port;
  String? get localIp => _localIp;

  /// 서버 URL 가져오기
  String? get serverUrl {
    if (_localIp != null) {
      return 'http://$_localIp:$_port';
    }
    return null;
  }

  /// 상품 캐시 업데이트 (상품 상태 변경 시 호출)
  void updateProductCache(List<ProductModel> products) {
    _cachedProducts = List.from(products);
    logger.d('LocalServerService - 상품 캐시 업데이트: ${_cachedProducts!.length}개');
  }

  /// 상품 데이터 캐시
  void _cacheProducts() {
    try {
      final productState = _ref.read(productProvider);

      logger.d('LocalServerService - 상품 데이터 캐시 시도:');
      logger.d('  - hasValue: ${productState.hasValue}');
      logger.d('  - isLoading: ${productState.isLoading}');
      logger.d('  - hasError: ${productState.hasError}');

      if (productState.hasValue && productState.value != null) {
        logger.d('  - value length: ${productState.value!.length}');
        logger.d('  - value type: ${productState.value.runtimeType}');
        logger.d(
            '  - first few items: ${productState.value!.take(3).map((p) => '${p.productId}:${p.productName}').toList()}');

        _cachedProducts = List.from(productState.value!);
        logger.i(
            'LocalServerService - 상품 데이터 캐시 완료: ${_cachedProducts!.length}개');
      } else {
        logger.w('LocalServerService - 캐시할 상품 데이터가 없습니다.');
        logger.w('  - hasValue: ${productState.hasValue}');
        logger.w('  - value is null: ${productState.value == null}');
        _cachedProducts = null;
      }
    } catch (e, stackTrace) {
      logger.e('LocalServerService - 상품 데이터 캐시 실패',
          error: e, stackTrace: stackTrace);
      _cachedProducts = null;
    }
  }

  /// HTTP 요청 처리
  void _handleRequest(HttpRequest request) {
    try {
      // CORS 헤더 설정 (키오스크에서 접근 가능하도록)
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.headers
          .add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
      request.response.headers
          .add('Access-Control-Allow-Headers', 'Content-Type, Authorization');
      request.response.headers
          .add('Content-Type', 'application/json; charset=utf-8');

      // OPTIONS 요청 처리 (CORS preflight)
      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.ok;
        request.response.close();
        return;
      }

      final path = request.uri.path;
      final method = request.method;

      logger.d('요청 수신: $method $path');

      // 라우팅 처리
      if (method == 'GET' && path.startsWith('/api/product/')) {
        _handleGetProductStatus(request);
      } else {
        _sendError(request, HttpStatus.notFound, 'API not found');
      }
    } catch (e, stackTrace) {
      logger.e('요청 처리 중 오류', error: e, stackTrace: stackTrace);
      _sendError(
          request, HttpStatus.internalServerError, 'Internal server error');
    }
  }

  /// 상품 판매상태 조회 API
  Future<void> _handleGetProductStatus(HttpRequest request) async {
    String? productId;
    try {
      final path = request.uri.path;
      final segments = path.split('/');

      if (segments.length != 4 ||
          segments[1] != 'api' ||
          segments[2] != 'product') {
        _sendError(request, HttpStatus.badRequest,
            'Invalid URL format. Use: /api/product/{productId}');
        return;
      }

      productId = segments[3];
      if (productId.isEmpty) {
        _sendError(request, HttpStatus.badRequest, 'Product ID is required');
        return;
      }

      // ✅ 캐시된 상품 데이터 사용
      logger.d('LocalServerService - 캐시된 상품 데이터 사용:');
      logger.d('  - 캐시된 상품 개수: ${_cachedProducts?.length ?? 0}');

      // 캐시된 데이터에서 상품 찾기
      final product = _cachedProducts!.firstWhere(
        (p) => p.productId == productId,
        orElse: () => throw Exception('Product not found'),
      );

      // ✅ 성공 응답
      _sendJsonResponse(request, {
        'success': true,
        'data': {
          'productId': product.productId,
          'productName': product.productName,
          'status': product.status.code,
          'statusName': product.status == ProductStatus.sale ? '판매중' : '품절',
        },
        'timestamp': DateTime.now().toIso8601String(),
      });

      logger.d('상품 상태 조회 완료: ${product.productName} - ${product.status}');
    } catch (e, stackTrace) {
      if (e.toString().contains('Product not found')) {
        logger.w('상품을 찾을 수 없습니다: $productId');
        _sendJsonResponse(
          request,
          {
            'success': false,
            'error': 'Product not found',
            'productId': productId,
            'timestamp': DateTime.now().toIso8601String(),
          },
          HttpStatus.notFound,
        );
      } else {
        logger.e('상품 상태 조회 중 오류', error: e, stackTrace: stackTrace);
        _sendError(request, HttpStatus.internalServerError,
            'Failed to get product status');
      }
    }
  }

  /// JSON 응답 전송
  void _sendJsonResponse(HttpRequest request, Map<String, dynamic> data,
      [int statusCode = HttpStatus.ok]) {
    request.response
      ..statusCode = statusCode
      ..write(jsonEncode(data))
      ..close();
  }

  /// 에러 응답 전송
  void _sendError(HttpRequest request, int statusCode, String message) {
    _sendJsonResponse(
        request,
        {
          'success': false,
          'error': message,
          'timestamp': DateTime.now().toIso8601String(),
        },
        statusCode);
  }
}
