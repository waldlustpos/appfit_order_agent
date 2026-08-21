---
name: project-bixolon-g30-40mm-layout
description: BIXOLON G30(UPOS) 라벨프린터 통합 + 40mm 연속용지 레이아웃 완료·커밋. 58mm/Windows 남음.
metadata: 
  node_type: memory
  type: project
  originSessionId: 53a45610-6eb5-4053-b969-874bbd803dd5
  modified: 2026-08-21T07:22:54.828Z
---

BIXOLON G30(연속용지+커터, UPOS/JavaPOS SDK) Android 드라이버 + 40mm 전용 세로 가변 레이아웃 완료, `feat/bixolon-g30` 브랜치에 커밋 완료(cb56a37). 상세 경위·기하 확정 시행착오는 저장소의 `docs/PRINTER_FLOW.md` §3.5 가 정본 — 여기는 놓치기 쉬운 핵심만.

**핵심 발견(비직관적)**: G30 은 인쇄 시작 위치 자체가 하드웨어에 고정돼 있어, 소프트웨어 쪽 margin(padding)을 아무리 조정해도 시각적 중앙 정렬이 안 된다 — 오히려 margin(좌측)을 키울수록 콘텐츠가 그대로 더 오른쪽으로 밀렸다(3회 재현). 인쇄 가능 영역도 항상 정확히 35mm(280dot)로 고정(용지 물리폭 40mm=320dot 중). 그래서 "40mm 캔버스+margin으로 중앙 맞추기"를 포기하고 캔버스 자체를 실측 유효 인쇄폭(272dot)으로 좁히는 방향으로 최종 확정(`LabelMediaSpec.continuous40`: widthDots=272, sideMarginDots=0, rightMarginDots=16).

**Why**: 프린터 UPOS SDK 에 인쇄 시작 위치/margin 관련 API 없음(매뉴얼 확인). 하드웨어/가이드 쪽 문제로 보임 — 재장착이나 BIXOLON 유틸리티 확인이 남은 유일한 레버.

**How to apply**: 이 결론은 **40mm 전용 실측**이다. 58mm 레이아웃 작업 시 이 margin/폭 값을 그대로 스케일하지 말 것 — 처음부터 다시 실측 필요(같은 진단 패턴: mm눈금+CL/CR 마커, 계산 끝나서 코드는 제거했지만 재구현 가능). `LabelMediaSpec.continuous58` 슬롯 추가해서 채우면 됨.

**남은 작업**: ① 58mm 레이아웃(40mm 단순 확대 아닐 것으로 예상, 별도 실측 필요) ② Windows(BXLPAPI) 이식 — 레이아웃(PNG 생성)은 재사용 가능, 전송 계층만 별도 ③ 설정 화면 용지 사이즈 선택 UI — G30 한 대가 가이드 교체만으로 40mm/58mm 겸용이라, 58mm 되면 매장이 선택하도록 배선 필요(현재 40mm 단일 고정, 선택 UI 자체가 없음).

부수 수정: `LabelDrawOps.drawCrispQr` 에 `clampQuietTopTo`/`clampQuietBottomTo` 추가 — QR quiet zone 이 gap 보다 넓으면 인접 요소를 흰색으로 덮어쓰던 겹침 버그(표시번호/QR, QR/subInfo 둘 다) 수정. 이 패턴은 다른 라벨 레이아웃에서 QR 겹침 이슈 생기면 먼저 의심할 것.

세션 중 `lib/services/api_service.dart` 에 다른 세션(또는 이전 작업)의 미스테이징 변경(로그 주석처리)이 섞여 있었음 — [[feedback_concurrent_session_git_state]] 대로 커밋 직전 git status 재확인해서 걸러내고 커밋 대상에서 제외함(파일은 그대로 미스테이징 상태로 둠).
