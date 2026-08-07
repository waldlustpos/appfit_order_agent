import 'dart:async';
import 'dart:io' show OSError, SocketException;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// 장애 주입 허용 여부 — 릴리즈 유출 방지 게이트.
///
/// **반드시 `const` 로 유지할 것.** const 이면 릴리즈 빌드에서
/// `if (kAllowFaultInjection) { ... }` 블록 자체가 컴파일 타임에 제거된다
/// (`kDebugMode` 와 동일한 보증). getter 로 바꾸면 AOT tree-shaking 보증이
/// 약해져 주입 코드가 매장 출고본에 남을 수 있다.
///
/// `!kReleaseMode` 를 앞에 둔 이유: 실수로 릴리즈 빌드에
/// `--dart-define=FAULT_INJECTION=true` 를 붙여도 무조건 false 가 된다.
///
/// `kDebugMode` 단독이 아닌 이유: profile 빌드는 `AppEnv.showInternalUi`
/// (=`!kReleaseMode`)가 true 인데 `kDebugMode` 는 false 라, 성능이 현실적인
/// 상태로 장애를 재현하려 할 때 "개발자 옵션은 보이는데 버튼만 죽어 있는"
/// 함정이 생긴다. define 으로 명시적 opt-in 을 열어두되 릴리즈는 원천 차단.
///
/// **`AppEnv` 에 두지 않은 이유**: `lib/config/app_env.dart` 는 gitignored
/// 머신별 로컬 파일이라(.gitignore) 여기에 신규 멤버를 추가하면 커밋되지 않아
/// 다른 머신·CI 의 stale 사본에서 컴파일이 깨진다. 게이트는 tracked 파일에 둔다.
const bool kAllowFaultInjection =
    !kReleaseMode && (kDebugMode || bool.fromEnvironment('FAULT_INJECTION'));

/// 주입 대상 엔드포인트.
///
/// 전역 하나가 아니라 대상을 고르게 한 이유는 세 가지다.
/// - 검증 항목이 엔드포인트별로 다르다: 배너는 [orders], KDS 스피너·in-flight
///   락·이벤트 억제 해제는 [orderUpdate], 재시도 백오프는 [orderDetail].
/// - 전역 하나만 두고 무제한 무장하면 목록이 죽어 화면이 비고, 그 상태로
///   설정 화면까지 걸어가서 해제해야 한다. 탈출 경로가 막힌다.
/// - 그럼에도 "매장 장애 재현" 은 셋이 동시에 죽는 게 맞다 → 프리셋이 한 번에 켠다.
enum NetFaultTarget {
  /// GET /v1/orders — 폴링(60초)이 때리므로 사실상 HTTP heartbeat.
  orders,

  /// GET /v1/orders/{id} — 소켓 상세조회. 재시도 래퍼가 붙어 있다.
  orderDetail,

  /// PUT /v0/order/{id} — 사용자 액션(접수/픽업요청/완료).
  orderUpdate,
}

/// 주입할 실패 유형.
///
/// [slowOnly] 를 뺀 나머지는 전부 `isTransientNetworkError` 가 true 로 보는
/// 종류다 — [notFound] 만 예외이며, 그건 의도된 것이다(4xx = 서버가 정상
/// 응답했다는 뜻이라 건강도 카운터가 **리셋**되는 계약을 검증한다).
enum NetFaultKind {
  /// 지연만 걸고 실제 요청은 통과시킨다.
  ///
  /// 2026-08-07 장애의 본질은 "전멸" 이 아니라 "20~30초 끌다가 되기도 함"
  /// 이었다. 전부 하드 실패시키면 2회 만에 배너가 떠버려서, 정작 **배너를
  /// 못 만들면서 UI 만 25초 얼어붙는 구간** 을 재현할 수 없다 — 그 구간이
  /// 바로 in-flight 락과 버튼 스피너가 존재하는 이유다.
  ///
  /// 덤으로 "이때 배너가 뜨면 버그" 라는 오탐 검증이 된다.
  slowOnly,

  /// DNS 조회 실패. 2026-08-07 2구간 16:36:41 과 같은 모양
  /// (`SocketException: Failed host lookup ... errno = 7`).
  dnsFailure,

  /// TCP 연결 수립 실패(SYN 드롭 계열). NAT 세션 고갈·방화벽 DROP 재현.
  connectTimeout,

  /// 연결은 됐는데 응답이 안 옴. 업링크 포화 재현.
  receiveTimeout,

  /// 요청 전송 중 타임아웃.
  sendTimeout,

  /// 5xx (transient) — 503 Service Unavailable.
  serverError,

  /// 4xx (non-transient) — 404 Not Found.
  notFound,
}

/// 현재 무장 상태. 수동 작성 모델(freezed 미사용 — 프로젝트 규약).
class NetFaultConfig {
  /// 빈 Set 이면 비무장.
  final Set<NetFaultTarget> targets;
  final NetFaultKind kind;
  final Duration delay;

  /// 남은 주입 횟수. null 이면 무제한.
  final int? remaining;

  const NetFaultConfig({
    this.targets = const <NetFaultTarget>{},
    this.kind = NetFaultKind.dnsFailure,
    this.delay = Duration.zero,
    this.remaining,
  });

  static const NetFaultConfig disarmed = NetFaultConfig();

  bool get isActive =>
      targets.isNotEmpty && (remaining == null || remaining! > 0);

  NetFaultConfig copyWith({int? remaining}) => NetFaultConfig(
        targets: targets,
        kind: kind,
        delay: delay,
        remaining: remaining ?? this.remaining,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetFaultConfig &&
          setEquals(other.targets, targets) &&
          other.kind == kind &&
          other.delay == delay &&
          other.remaining == remaining;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(targets), kind, delay, remaining);

  @override
  String toString() => isActive
      ? 'NetFaultConfig(${targets.map((t) => t.name).join("+")}, '
          '${kind.name}, ${delay.inSeconds}s, '
          'remaining=${remaining ?? "∞"})'
      : 'NetFaultConfig(disarmed)';
}

/// [NetFaultInjector.take] 가 돌려주는 "이번 호출에 무엇을 할지".
class NetFault {
  final Duration delay;

  /// null 이면 지연만 걸고 실제 요청을 진행한다([NetFaultKind.slowOnly]).
  final DioException? error;

  const NetFault({required this.delay, this.error});
}

/// 개발 전용 — 네트워크 장애를 인위적으로 주입한다.
///
/// **순수하게 유지한다**: throw 도 로깅도 지연도 하지 않고 "무엇을 할지" 만
/// 돌려준다. 그래야 (a) 단위 테스트가 의존성 0 이고 (b) 로깅이 ApiService 한
/// 곳에 모이며 (c) 지연을 호출부가 제어한다.
///
/// 호출부는 반드시 [kAllowFaultInjection] 게이트 안에 두어야 한다.
/// 그 상수가 `const` 이므로 릴리즈 빌드에서는 호출 블록 전체가
/// 컴파일 타임에 제거된다.
///
/// 전신인 `OrderDetailFaultInjector` 는 네 가지 이유로 이번 검증에 쓸 수
/// 없었다: 주입점이 `try` 밖이라 건강도/진단 로그를 우회했고, `getOrder`
/// 하나만 덮었고, DNS 실패 종류가 없었고, 즉시 throw 라 지연을 못 만들었다.
class NetFaultInjector {
  NetFaultInjector._();

  /// 무장 자동 만료. 무제한 무장인 채로 매장에 나가는 것을 막는 마지막 방어선.
  ///
  /// `DateTime.now()` 비교가 아니라 순수 [Timer] 인 이유는 fakeAsync 로
  /// 검증하기 위해서다 (docs/TESTING.md).
  static const Duration maxArmDuration = Duration(minutes: 10);

  /// UI 가 무장 상태·잔여 카운트를 실시간으로 보려면 listenable 이어야 한다.
  /// (기존 static 카운터의 진짜 공백이 여기였다)
  static final ValueNotifier<NetFaultConfig> state =
      ValueNotifier<NetFaultConfig>(NetFaultConfig.disarmed);

  static Timer? _expiry;

  static NetFaultConfig get config => state.value;

  /// 무장. 이미 무장돼 있으면 덮어쓰고 만료 타이머를 재설정한다.
  static void arm(NetFaultConfig cfg) {
    _expiry?.cancel();
    state.value = cfg;
    if (cfg.isActive) {
      _expiry = Timer(maxArmDuration, clear);
    }
  }

  /// 즉시 해제.
  static void clear() {
    _expiry?.cancel();
    _expiry = null;
    state.value = NetFaultConfig.disarmed;
  }

  /// 이번 호출에 주입할 것이 있으면 돌려주고 카운터를 소모한다.
  ///
  /// 카운터를 **지연 전에** 소모하는 이유: 상세조회는 `Future.wait` 로 병렬
  /// 호출되므로(order_provider `_fetchDetailsForVisibleOrders`), 지연 후에
  /// 소모하면 여러 호출이 같은 슬롯을 잡는다.
  ///
  /// [path] 는 로그/Sentry 에서 실제 요청과 같은 경로로 보이도록 호출부가
  /// `ApiRoutes.*` 값을 그대로 넘긴다. (전신은 `/v0/orders/{id}` 를
  /// 하드코딩했는데 실제 라우트 셋 중 어느 것과도 달랐다)
  static NetFault? take(NetFaultTarget target, String path) {
    final cfg = state.value;
    if (!cfg.isActive || !cfg.targets.contains(target)) return null;

    final left = cfg.remaining;
    if (left != null) {
      state.value = cfg.copyWith(remaining: left - 1);
    }

    return NetFault(
      delay: cfg.delay,
      error: cfg.kind == NetFaultKind.slowOnly ? null : _build(cfg.kind, path),
    );
  }

  static DioException _build(NetFaultKind kind, String path) {
    final options = RequestOptions(path: path);
    switch (kind) {
      case NetFaultKind.slowOnly:
        throw StateError('unreachable: slowOnly 는 error 를 만들지 않는다');
      case NetFaultKind.dnsFailure:
        // cause 가 SocketException 으로 찍혀야 실제 장애 로그
        // ([API진단] ... cause=SocketException) 와 문자열이 일치한다.
        return DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
          error: const SocketException(
            'Failed host lookup: (fault injection)',
            osError: OSError('No address associated with hostname', 7),
          ),
        );
      case NetFaultKind.connectTimeout:
        return DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      case NetFaultKind.receiveTimeout:
        return DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );
      case NetFaultKind.sendTimeout:
        return DioException(
          requestOptions: options,
          type: DioExceptionType.sendTimeout,
        );
      case NetFaultKind.serverError:
        return DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 503),
        );
      case NetFaultKind.notFound:
        return DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: options, statusCode: 404),
        );
    }
  }
}
