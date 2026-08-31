import 'package:appfit_core/appfit_core.dart';

/// "예상된" 서버 오류를 Sentry 이슈에서 빼고 파일/콘솔 로그로만 흘리는 래퍼.
///
/// ## 왜 필요한가
///
/// Dio 오류는 `getUserProfile` 의 catch 절보다 **먼저** core 의
/// `_AppFitLogInterceptor.onError` 를 지나며, 거기서 무조건
/// `logger.error(...)` 로 Sentry 에 올라간다. 즉 앱의 예외 분기만으로는
/// Sentry 전송을 막을 수 없다.
///
/// 멤버십 화면이 미가입 번호도 접수하게 되면서 `404 NOT_FOUND_USER` 는
/// **일상 동작**이 됐다. 그대로 두면 조회 한 건마다 브랜드 Slack 채널
/// (docs/SENTRY_ALERTS.md 의 `when: "every"` 룰)이 울린다.
///
/// core 에도 같은 목적의 [SentryAppFitLogger.benignServerCodes] 가 있지만
/// 거기에 넣으려면 core 릴리즈(태그 + pubspec ref 범프)가 필요하다. 이 래퍼는
/// 앱 쪽에서 같은 일을 하며, core 에 반영되면 통째로 지우면 된다.
///
/// ## 무엇을 거르지 않는가
///
/// 판정은 **HTTP status + 서버 code + 경로** 셋이 모두 맞아야 통과다. 코드만
/// 보면 스탬프 적립·쿠폰 사용이 `NOT_FOUND_USER` 로 실패하는 경우까지
/// 조용해지는데, 그건 정반대로 **꼭 봐야 하는** 신호다 — 서버가 미가입 번호의
/// 적립을 거부한다는 뜻이고, 이 기능이 통째로 무력하다는 얘기가 된다.
///
/// ## 로그 레벨
///
/// 걸러진 건은 [AppFitLogger.error] 가 아니라 [AppFitLogger.log] 로 흘린다.
/// 그러지 않으면 파일 로그에 `[E] ... ERROR ...` 로 남는데, 그 파일은 Slack·
/// 로그서버로 나가고 장애 조사 때 사람이 읽는다. 기록은 유지된다 — core 가 주는
/// 메시지에 `[API 오류]` 가 들어 있어 `logger.dart` 의 `[API]`+`오류` 화이트리스트를
/// 그대로 통과한다(레벨만 INFO 로 내려간다).
class BenignApiLogFilter implements AppFitLogger {
  BenignApiLogFilter({required this.sentry, required this.plain});

  /// 평소 경로 — Sentry 전송을 포함한 로거.
  final AppFitLogger sentry;

  /// 우회 경로 — 파일/콘솔에만 남기는 로거.
  final AppFitLogger plain;

  /// Sentry 를 건너뛸 (서버 code → 경로 조각들). 경로는
  /// [ApiHttpException.path](템플릿화된 경로)에 대한 부분 일치다.
  ///
  /// ⚠️ **여기에 경로를 추가할 때의 기준**: 그 경로에서 그 코드가 나오는 게
  /// 정상 운영의 일부여야 한다. 하나라도 넓히면 진짜 장애가 조용해진다.
  ///
  /// 특히 아래는 같은 `NOT_FOUND_USER` 라도 **넣으면 안 된다**:
  /// - `/stamps/history`, `/coupons/history` — 미가입이면 애초에 호출하지
  ///   않으므로(`Membership._enterUnregistered`), 여기서 이 코드가 나온다는
  ///   것은 프로필 조회는 성공했는데 내역은 유저가 없다고 답한 서버 불일치다.
  /// - `/stamp/earn` — 미가입 적립 거부. 이 기능의 전제가 깨졌다는 신호다.
  /// - `/coupon/{no}/use-without-item`, `/coupon/{no}/use-cancel`
  static const Map<String, Set<String>> benignCodeToPaths =
      <String, Set<String>>{
    // 회원 조회 → 멤버십 화면이 '미가입' 상태로 정상 진행한다.
    'NOT_FOUND_USER': <String>{'/user/profile'},
  };

  static bool isBenign(Object? error) {
    if (error is! ApiHttpException) return false;
    if (error.status != 404) return false;
    final paths = benignCodeToPaths[error.code];
    return paths != null && paths.any(error.path.contains);
  }

  @override
  Future<void> log(String message) => sentry.log(message);

  @override
  Future<void> error(String message, dynamic error) => isBenign(error)
      ? plain.log(message) // Sentry 미전송 + 파일 로그는 INFO 레벨로
      : sentry.error(message, error);
}
