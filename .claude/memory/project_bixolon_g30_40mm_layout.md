---
name: project-bixolon-g30-40mm-layout
description: BIXOLON G30(UPOS) 라벨프린터 40mm/58mm 레이아웃 완료(유효폭 실측 확정). Windows 이식 남음.
metadata: 
  node_type: memory
  type: project
  originSessionId: 53a45610-6eb5-4053-b969-874bbd803dd5
  modified: 2026-08-26T00:00:00.000Z
---

BIXOLON G30(연속용지+커터, UPOS/JavaPOS SDK) Android 드라이버 + **40mm/58mm 두 레이아웃** 구현 완료, `feat/bixolon-g30` 브랜치. 상세 경위·기하 확정 시행착오는 저장소의 `docs/PRINTER_FLOW.md` §3.5(40mm)·§3.6(58mm) 가 정본 — 여기는 놓치기 쉬운 핵심과 상태만.

**핵심 발견 ①(40mm, 비직관적)**: G30 은 인쇄 시작 위치 자체가 하드웨어에 고정돼 있어, 소프트웨어 margin 을 아무리 조정해도 시각적 중앙 정렬이 안 된다 — 오히려 좌측 margin 을 키울수록 콘텐츠가 그대로 더 오른쪽으로 밀렸다(3회 재현). 인쇄 가능 영역도 물리 40mm 가 아니라 정확히 35mm(280dot) 고정. 그래서 "캔버스+margin 으로 중앙 맞추기"를 포기하고 캔버스 자체를 실측 유효 인쇄폭(272dot)으로 좁혔다.

**58mm 실측 확정(2026-08-26)**: 눈금자 판독 결과 인쇄 가능폭 **52.5mm(420dot)** — 물리 58mm(464dot) 대비 5.5mm 손실로, 40mm 의 5mm 손실과 거의 같다(가이드 고정 오프셋 해석과 일관). `continuous58.widthDots=412`(경계 420 - 8dot 여유). ⚠️ **결과가 비슷했던 것이지 비례로 유도한 게 아니다** — 비례 확대였다면 50.75mm 로 1.75mm(14dot) 어긋났다.

**핵심 발견 ②(58mm 작업 중, 측정 함정)**: `BixolonPosDriver.printBitmap` 의 전송폭 clamp 가 `Math.min(w, 320)` — **40mm 물리 용지폭**이었다. 58mm 비트맵이 조용히 잘리는 것보다 나쁜 건, **눈금자 진단조차 항상 320dot 에서 끊겨 "58mm 유효폭 = 320dot" 이라는 가짜 실측값**을 만든다는 점이다. 576(헤드 최대폭)으로 올렸다. → 일반화: **측정 도구가 지나가는 경로에 측정 대상과 같은 단위의 상한이 박혀 있으면, 그 상한을 먼저 걷어내지 않은 측정은 자기 자신을 측정한 것이다.**

**핵심 발견 ③(58mm)**: QR quiet zone 겹침 사고의 **가로 버전**. QR 을 다른 요소와 같은 행에 두면(58mm: 번호 좌 + QR 우) quiet zone 이 박스 밖 30dot 넘게 확장돼 옆 요소를 흰색으로 지운다. `drawCrispQr` 에 `clampQuietLeftTo`/`clampQuietRightTo` 추가(기존 상하 clamp 와 대칭). gap 을 넓혀 막는 접근은 32dot 이상 필요 + `modulePx` 에 따라 흔들리는 취약한 불변식이라 기각.

**58mm 설계 판단**: 목업 구조는 40mm(세로 스택)이 아니라 갭라벨 V2 쪽에 가까웠다 — 번호+QR 가로 배치, 검정 반전 바, 옵션 2열. 별도 painter(`Continuous58LabelPainter`)로 분리하고 40mm 은 손대지 않았다. **폰트 절대 크기는 목업 비율이 아니라 40mm 검증값에 앵커링** — 목업 비례를 dot 으로 환산하면 메뉴명이 19dot 으로 40mm(26dot)보다 작아진다(넓은 용지가 덜 보이는 역전).

**핵심 발견 ④(58mm, 반전 인쇄 가독성)**: 검정 바 흰 글씨가 얇게 나온다는 실기기 피드백. 반전 인쇄의 흰 획은 두 번 얇아진다 — threshold 210 이진화가 AA 경계를 검정으로 밀고(①), 감열지에서 주변 검정이 번져 들어온다(②). Pretendard 는 **Bold(700)가 번들에 없어**(pubspec 이 Medium/Regular/SemiBold 만, Bold 추가 시 APK +1.6MB) w700 을 줘도 w600 폴백 → 자산 없이 굵게 하는 수단은 fontSize 와 의사 볼드(같은 색 stroke + fill) 둘뿐. → **stroke 는 획을 굵게 하는 만큼 획 사이 간격도 같은 양 좁힌다** — 한글 '블'/'없', 한자처럼 획이 촘촘하면 counter 가 먼저 메워져 흰 덩어리가 된다(fs24 기준 st1.2 실패, st0.8 깨끗). **fontSize 는 획과 간격이 함께 커져 counter 를 잃지 않는다 — 굵기가 필요하면 stroke 말고 fontSize.** 최종 fs24 / bar42 / stroke1.0.

**방법론(재사용 가치 큼)**: 라벨 렌더 결과를 **threshold 210 이진화까지 재현해서** 후보를 비교했다(임시 flutter test 로 PNG 덤프 + 3배 nearest 확대). 실기기 왕복 없이 "프린터가 실제로 받는 도트"를 보고 고를 수 있다 — 다만 감열 번짐은 재현 못 하므로 시뮬레이션보다 한 단계 굵은 쪽을 택하는 보정이 필요하다.

**현재 상태 / 남은 것**:
- 40mm·58mm 레이아웃, 설정 배선, 테스트, 문서 전부 완료. **미커밋.** `flutter analyze` 18건(전부 기존), `flutter test` 579 통과.
- 실물 확인 남음: 검정 바 폰트/stroke 조합(약하면 다음 지렛대는 fs26 → Pretendard-Bold 번들 +1.6MB), 좌측 여백 0 전제.
- Windows(BXLPAPI) 이식 미착수 — 할 일 ① `print_service.dart` 의 490/600 하드코딩을 실제 생성 이미지 크기로 교체 ② `windows_label_router` 에 **G30 분기 신규 추가**(구 'XD5-40d' 하드코딩은 2026-09-01 제거됐고, 라우터 파일은 그 분기가 들어올 자리로 의도적으로 남겨 둔 것 — [[project-bixolon-xd5-removal-residue]]).

[[feedback_concurrent_session_git_state]] 대로 커밋 직전 git status 재확인할 것 — 40mm 작업 때 다른 세션의 `api_service.dart` 미스테이징 변경이 섞였던 전례가 있다.
