---
name: project_windows_label_beep_restore
description: "Windows 라벨 비프음 복원 (4f222b3, 푸시·실기기 검증 완료). 완료 시 떼기 대기 제거 + 레벨→edge. peel edge 가 printed 콜백을 항상 이김."
metadata: 
  node_type: memory
  type: project
  originSessionId: 3386bd7a-e00e-4391-9ed0-84a919ea04eb
  modified: 2026-08-07T04:17:08.241Z
---

2026-08-07 커밋 `4f222b3` (origin/main 푸시 완료, **Windows 실기기 검증 완료**).
설계·실측 정본은 [docs/PRINTER_FLOW.md §3.3](docs/PRINTER_FLOW.md).

## 원인과 수정

`_printOnce` 가 **성공 경로에서** `_waitPaperFetched` 로 떼기까지 블로킹한 뒤 반환했다.
그래서 다음 `PagePrint` 는 peel 이 비워진 뒤에야 나가고 펌웨어가 buzzer 를 울릴 계기가 없었다.
→ 완료 신호를 받으면 떼기를 안 기다리고 반환. 불변식: **떼지 않은 상태에서 다음 PagePrint 가
펌웨어에 도달한다.**

## ⚠️ 비프음만 따로 고칠 수 없었다

완료 폴링이 `paperNoFetch` 를 **레벨**로 검사하고 있었는데, 그 검사는 위 떼기 대기가
"인쇄 시작 시 peel 은 늘 비어 있다" 를 보장해 준 덕에 **우연히** 맞아떨어지던 것이었다.
대기를 걷어내면 앞 라벨이 남은 채로 인쇄가 시작되고, 레벨은 이미 true 라 **아직 나오지도
않은 라벨을 첫 폴링에서 완료로 판정**한다. Android(`3e700f6`)와 동일하게 상승 edge 로 전환.

**How to apply:** 어떤 대기를 없앨 때는 **그 대기가 암묵적으로 보장하던 사전조건**을 먼저
찾아라. 여기서는 "인쇄 시작 시 peel 이 비어 있음" 이었고, 그게 다른 코드의 정확성을 떠받치고
있었다.

## 실측이 뒤집은 설계 가정

**`프린터응답`(printed 콜백)은 한 번도 이기지 못했다. 전부 `라벨나옴`(peel edge).**
계획 단계에서 "Windows 는 printed 콜백이 주 신호이므로 폴링 예산만 늘리면 된다" 고 봤는데
반대였다. edge 신호가 이 경로의 **주 신호**다.

## 계획에서 실행 중 뒤집은 것 두 가지

1. **폴링 예산 30초 확대 → 안 함.** Windows fallback query 는 30초가 아니라 **1000ms**이고
   보류는 그 뒤 무한 떼기 대기가 받는다. 늘리면 폴백 도달만 늦어져 손해.
2. **`_resetStatusBeacon` 에서 edge 카운터 리셋 → 안 함.** `!=` 비교라 리셋이 "변화" 로 읽혀
   **인쇄되지 않은 라벨을 완료로 판정**한다. 단조 카운터로 유지.

## 실기기 결과 (Windows POS)

바로바로 떼며 3장: `529ms / 1019ms / 1272ms` 전부 `라벨나옴`, **비프음 정상**, 중복 없음.
첫 인쇄 1회만 3329ms(warm-up). 안 뗀 채 요청: `떼기대기` → 떼면 완료.

한 주문 내 라벨은 ~0.5초 간격이라 **2번째부터 거의 항상 비프음**이 난다(그 사이 떼기 불가).
바로 떼면 보류 없이 이어져 지연 0. Android 도 동일.

**남은 것**: ① `떼기대기` 완료 보고가 한 박자 이른 문제(양 플랫폼 공통, 중복·누락은 없음)
② BIXOLON Windows 경로는 미검증이라 손대지 않음.

관련: [[project_label_completion_multi_signal]], [[project_label_printer_platform_divergence]]
