/// KDS 주문 카드 전용 치수·임계값 상수.
///
/// AppSpacing/AppRadius로는 표현하기 어려운 카드 고유 치수
/// (열 너비, 헤더+푸터 예약 높이, 스크롤 임계 등)를 한곳에 모은다.
class KdsCardMetrics {
  const KdsCardMetrics._();

  static const double cardWidth = 250;
  static const double columnWidth = 260;

  /// 스크롤 가능 카드의 메뉴 영역 maxHeight 계산 시 빼는 값
  /// (헤더 + 메모 + 버튼 영역 합산 추정).
  static const double headerFooterReserve = 165;

  /// Stack 위에서 하단 버튼 영역과 컨텐츠 충돌을 막기 위한 예약 높이.
  static const double bottomButtonReserve = 55;

  /// 가로/세로 스크롤에서 "끝에 도달했다"고 판단하기 위한 여유 픽셀.
  static const double scrollEdgeThreshold = 5.0;

  /// 무한 스크롤 트리거 임계 (maxScrollExtent - 이 값 이하 도달 시 추가 로드).
  static const double loadMoreThreshold = 200;

  /// 카드 메뉴 이름 표시 최대 글자 수.
  static const int maxMenuNameLength = 12;

  static const Duration cardSizeAnimDuration = Duration(milliseconds: 400);
  static const Duration cardSizeAnimDurationShort = Duration(milliseconds: 300);
  static const Duration opacityAnimDuration = Duration(milliseconds: 500);
}
