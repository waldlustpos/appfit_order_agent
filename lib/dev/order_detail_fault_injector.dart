import 'package:dio/dio.dart';

/// 주입할 상세조회 실패 유형.
enum OrderDetailFaultKind {
  /// 5xx (transient → 재시도 대상) — 503 Service Unavailable
  serverError,

  /// 4xx (non-transient → 재시도 안 함) — 404 Not Found
  notFound,

  /// 네트워크 타임아웃 (transient → 재시도 대상)
  timeout,
}

/// 디버그 전용 — 주문 상세조회(ApiService.getOrder)를 인위적으로 실패시키는
/// fault injector.
///
/// 실기기에서 "서버오류/인터넷 불안정으로 상세조회 실패" 상황을 결정론적으로
/// 재현하기 위한 테스트 보조 장치. ApiService.getOrder 가 kDebugMode 게이트
/// 안에서만 [maybeThrow] 를 호출하므로 release 빌드/프로덕션 경로에는 영향이 없다.
///
/// [arm] 으로 다음 N 건을 실패시키도록 무장하면, getOrder 호출마다 카운터가
/// 1 씩 줄며 지정한 예외를 throw 한다. 카운터가 0 이 되면 자동 해제된다.
///
/// 검증 시나리오 예:
///   - serverError × 2 : 재시도 2회 실패 후 3회차 성공 → 누락 없이 정상 출력
///   - serverError × 99: 재시도 소진 → refreshOrders 복구 + 부분영수증 차단
///   - notFound × 1    : 4xx 는 재시도 없이 즉시 실패
class OrderDetailFaultInjector {
  OrderDetailFaultInjector._();

  static int _remaining = 0;
  static OrderDetailFaultKind _kind = OrderDetailFaultKind.serverError;

  static int get remaining => _remaining;
  static OrderDetailFaultKind get kind => _kind;
  static bool get isActive => _remaining > 0;

  /// 다음 [count] 건의 getOrder 를 [kind] 로 실패시키도록 무장한다.
  static void arm(int count, OrderDetailFaultKind kind) {
    _remaining = count < 0 ? 0 : count;
    _kind = kind;
  }

  /// 강제 실패를 즉시 해제한다.
  static void clear() {
    _remaining = 0;
  }

  /// getOrder 진입부에서 호출. 무장돼 있으면 카운터를 1 줄이고 해당 예외를 throw.
  static void maybeThrow(String orderId) {
    if (_remaining <= 0) return;
    _remaining--;
    final options = RequestOptions(path: '/v0/orders/$orderId');
    switch (_kind) {
      case OrderDetailFaultKind.serverError:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 503),
        );
      case OrderDetailFaultKind.notFound:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 404),
        );
      case OrderDetailFaultKind.timeout:
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
    }
  }
}
