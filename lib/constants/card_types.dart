// 통일된 카드 타입 enum
enum CardType {
  progress, // 진행 중
  pickup, // 픽업 대기
  completed, // 완료
  cancelled, // 취소
}

// 통일된 카드 레이아웃 타입 enum
enum CardLayoutType {
  simple, // 타입 0, 1: 간단한 레이아웃
  dynamic, // 타입 2: 동적 크기
  multiColumn, // 타입 3-1: 다중 컬럼
  scrollable, // 타입 3-2: 스크롤 가능
}
