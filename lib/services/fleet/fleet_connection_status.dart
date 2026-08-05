/// 앱바 아이콘이 표시하는 기기 관제(Fleet) 연결 상태.
///
/// appfit_core 의 [FleetReporter] 는 이 상태를 직접 노출하지 않는다(내부
/// `_consecutiveFailures` 는 private). 그래서 앱 쪽에서 [FleetSink] 를 감싸
/// register/heartbeat 결과를 관찰해 이 값을 유도한다 — appfit_core 태그
/// 릴리즈 왕복 없이 앱 전용으로 끝낼 수 있게.
enum FleetConnectionStatus {
  /// FLEET_BASE_URL/FLEET_DEVICE_KEY 미주입 — 관제 자체가 꺼져 있음.
  disabled,

  /// 설정은 있으나 register/heartbeat 응답을 아직 한 번도 받지 못함.
  connecting,

  /// 최근 보고가 성공.
  connected,

  /// 최근 보고가 실패(오프라인·서버 오류·타임아웃 등).
  error,
}
