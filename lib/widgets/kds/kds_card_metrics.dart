import 'package:appfit_order_agent/constants/app_styles.dart';

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

  // ── 메뉴/옵션 텍스트 위계 ─────────────────────────────────────────────
  // 주문 상세 다이얼로그(AppTextStyles.body 15 : bodySm 13)의 위계 비율을
  // KDS 기준 크기에 그대로 옮긴다. 종전엔 메뉴명·옵션명이 같은 스타일을
  // 공유해 '- ' 접두어와 들여쓰기로만 구분됐다.

  /// 카드 메뉴명 폰트.
  static const double menuFontSize = AppStyles.kOrderCardTimeSize; // 16.8

  /// 카드 옵션명 폰트 = 메뉴명 × (13/15).
  static const double optionFontSize =
      AppStyles.kOrderCardTimeSize * 13 / 15; // 14.56

  /// 옵션 앞 subdirectory 아이콘 크기 (주문 상세와 동일).
  static const double optionIconSize = 14;

  /// 아이콘을 옵션 첫 줄에 광학 정렬하기 위한 top 보정.
  /// 텍스트 라인박스 ≈ 14.56 × 1.2 = 17.5, 아이콘 14 → (17.5 - 14) / 2 ≈ 2.
  static const double optionIconTopNudge = 2;

  /// 카드 폭 250px 기준 가용폭은 메뉴 193px / 옵션 198px 이라 긴 이름은 1줄에
  /// 담기지 않는다. 2줄이면 메뉴 약 23자 / 옵션 약 27자까지 보인다.
  /// 3줄은 다옵션 주문에서 카드 높이가 과하게 튄다.
  static const int menuNameMaxLines = 2;
  static const int optionNameMaxLines = 2;

  static const Duration cardSizeAnimDuration = Duration(milliseconds: 400);
  static const Duration cardSizeAnimDurationShort = Duration(milliseconds: 300);
  static const Duration opacityAnimDuration = Duration(milliseconds: 500);
}
