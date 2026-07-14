---
name: AppFit 주문 에이전트 UI 리프레시 Phase 1~6 완료
description: 플랫폼 전환에 맞춰 진행한 UI 리프레시 전체 작업 내역 (Phase 6: 2026-04-15 완료)
type: project
originSessionId: cc4079e0-4340-410a-a52c-f6e59bb37c96
---
Phase 1~6 UI 리프레시 작업 완료 (커밋: 65481cb, cdc9208, 1da4914)

**Why:** 구 플랫폼 → AppFit 플랫폼 전환 시점에 레이아웃/동선 무변경 조건 하에 "개편된 느낌" 제공

**범위 요약:**

Phase 1 — 디자인 토큰 & ThemeData
- `lib/constants/app_styles.dart`에 AppSpacing / AppRadius / AppElevation / AppTextStyles 토큰 추가
- `lib/main.dart` `_buildTheme()`: ColorScheme.fromSeed(kMainColor), ElevatedButton/Card/Dialog/TabBar/Input/Divider/PopupMenu/pageTransitionsTheme 테마 일괄 등록

Phase 2 — 공용 원자 컴포넌트 (`lib/widgets/common/`)
- app_loading_indicator.dart — 브랜드 컬러 스피너
- app_icon_action.dart — 앱바 아이콘 버튼 통일 (로딩·상태 variant)
- app_toolbar_button.dart — 40px 툴바 버튼 (primary/secondary/ghost)
- app_empty_view.dart / app_error_view.dart — 빈 상태·에러 위젯

Phase 3 — 통일성 이슈 타겟 정리
- app_bar_widget.dart: KDS/일반 새로고침 2종 → AppIconAction 1개, 네트워크·소켓·최소화·종료 AppIconAction 치환
- kds_screen.dart: 툴바 5개 빌더 → AppToolbarButton family (primary/secondary/ghost)
- common_dialog.dart: TextButton.styleFrom 반복 → AppStyles.primaryButton/outlinedButton
- kds_button_widget.dart: KdsButtonStyle → AppStyles 팩토리 위임

Phase 4 — 로딩·전환 애니메이션 현대화
- pageTransitionsTheme: ZoomPageTransitionsBuilder (login↔home↔settings zoom-fade)
- HomeContent: KDS↔일반 전환 AnimatedSwitcher(FadeTransition 200ms)
- CircularProgressIndicator → AppLoadingIndicator (6곳)
- Shimmer 스켈레톤: _OrderHistorySkeletonGrid(8열), _ProductGridSkeleton(5열)

Phase 5 — 폰트·Sidebar 인디케이터
- Pretendard 폰트 스왑: AppTextStyles._font + _buildTheme() fontFamily
- TabButtonWidget: 좌측 3px AnimatedContainer 인디케이터 바 + 선택 배경 tint(18 alpha)

Phase 6 — 주문 상세 팝업·서브 위젯·로그인 화면 대폭 개편 (커밋: 1da4914, 2026-04-15)
- `lib/widgets/order/order_detail_popup.dart`: 헤더에 _StatusPill + 주문시각 통합, 푸터 좌(보조)/우(주 액션) spaceBetween, _buildActionButtons → record 반환, 시간 선택 AlertDialog 토큰화
- `lib/widgets/order/order_menu_list_widget.dart`: 그림자 카드 쉘(AppElevation.soft), 섹션 헤더(count_items), 옵션 아이콘 배지(Icons.subdirectory_arrow_right)
- `lib/widgets/order/order_payment_info_widget.dart`: 그림자 카드 쉘, _buildRow TextStyle 파라미터 단순화
- `lib/widgets/order/order_info_panel_widget.dart`: displayNum·orderedAt·상태pill 제거(헤더로 이동), 고객명+메모만 표시
- `lib/screens/login_screen.dart`: 배경 login-bg.png → kMainColor→kSub 그라디언트, 좌우 2분할(Hero 패널 flex:5 + Form 패널 flex:4, maxWidth 880×maxHeight 560), KDS Switch → _ModeSegmentedTabs(POS/주방모니터), 언어 스위처·환경 배지 토큰화
- `lib/constants/app_styles.dart`: AppElevation.soft(blurRadius 12, 0x1A) / card(blurRadius 16, 0x26) 그림자 강도 상향

**남은 UI 개편 후보 (미착수):**
- `lib/screens/settings_screen.dart` — 설정 화면 (하드코딩 색상/크기 다수 존재)
- `lib/screens/home_screen.dart` / `lib/screens/kds_screen.dart` — 앱바·툴바 세부 정비 여지

**How to apply:** 후속 UI 작업 시 이 토큰/컴포넌트 체계를 기준으로 확장. AppSpacing/AppRadius/AppElevation/AppTextStyles/AppStyles 토큰 재사용, 신규 토큰 추가 없이 진행하는 것이 원칙
