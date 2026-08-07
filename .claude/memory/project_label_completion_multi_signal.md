---
name: project_label_completion_multi_signal
description: 라벨 완료 판정을 QueryPrintResult 단일 의존 → +PAPERNOFETCH edge 다중 신호로 (3e700f6). 보류는 정상 운영이라 안 빨라짐 — 기대효과를 보류 건수로 계산하지 말 것.
metadata: 
  node_type: memory
  type: project
  originSessionId: 3386bd7a-e00e-4391-9ed0-84a919ea04eb
  modified: 2026-08-07T01:08:43.897Z
---

2026-08-07 커밋 `3e700f6`(main, 미푸시·미배포). 설계 정본은
[docs/PRINTER_FLOW.md §3.2](docs/PRINTER_FLOW.md), 경위는 INCIDENT 문서 §후속 2.

## 무엇을 고쳤나

`CP_Pos_QueryPrintResult` 30초 블로킹 **단일 신호** → 2초 슬라이스 + **PAPERNOFETCH 상승
edge**, 먼저 오는 쪽. **총 상한 30초는 유지**(줄이면 미인쇄 페이지를 넘겨 펌웨어 버퍼에 쌓임).

## ⚠️ 전제 오류 — 두 번 틀렸고 둘 다 로그가 반박했다

**틀린 것 ①: "30초 소진 11건 × 28초를 회수한다".** 떼기대기 9건은 앞 라벨이 30초 넘게
안 떼어진 경우라 펌웨어가 실제로 인쇄를 안 하고 있었다. 그 30초는 낭비가 아니라 **기다려야
하는 시간**이고, 다중 신호로도 안 빨라진다. 실제 회수 대상은 `#40` 유형(프린터 idle인데
응답만 유실) **하루 1건 남짓**.

**틀린 것 ②: "라벨을 즉시 떼도록 안내 강화".** 러시아워에 음료 만들고 나중에 일괄로 떼는
것은 **정상 작업 흐름**이다. 앱이 적응할 입력이지 고칠 대상이 아니다. (사용자 지적으로 정정)

**How to apply:** 라벨 지연·큐 정지 개선을 논할 때 **보류 시간과 응답 유실 시간을 분리해서**
세라. 합치면 기대효과가 10배 부풀려진다.

## 설계 결정 두 가지

**edge 여야 하는 이유**: 앞 라벨이 안 떼어져 있으면 PAPERNOFETCH 레벨은 이미 true 라
"내 라벨이 나왔는가"를 구별 못 한다. 보류에서도 edge 는 반드시 생긴다 —
앞 라벨 peel(true) → 뗌(false) → 붙잡힌 페이지 인쇄(true).

**pageId 는 신호로 안 쓴다**: 같은 호출 안에서 절대 갱신 안 됨(로그 199건 중 **0건**),
다음 인쇄 시점에야 +1(186/198=94%). 판정에 쓰면 앞 페이지의 뒤늦은 등록을 내 페이지로
오인 → 미인쇄 페이지를 넘김. 진단 로그에만 남긴다. ⚠️ 단 **30초짜리 긴 창에서는 증가한다**
(#40 의 `pg=7→8`) — [[reference_rexod_label_printer_signals]] 의 "판정 불가" 는 ~1초 창 한정.

## 실기기 실측 (D2s_KDS_STGL `DK1925AJ40349` + REXOD, cold-restart)

| 상황 | 결과 |
|---|---|
| 정상 | `출력끝 (1213ms, via=query, ack=900ms)` — 슬라이싱해도 응답 유실 없음 |
| 보류→떼기 | `출력끝 (12645ms, via=peel, ack=12515ms)` — edge 후 **481ms** |
| 계속 안 뗌 | 30.2초에 `떼기대기 (buzzer 활성)` — 폴백·비프음 유지 |

peel edge 는 query 응답보다 일관되게 150~500ms 빠르다.

**남은 것**: ① push·배포 ② 배포 후 `via=` 분포로 query/peel 기여도와 잔여 ACK timeout 재측정
③ 그 결과로 feedToTear 순서 교정 여부 판단(우선순위 하향됨).

관련: [[project_label_ack_timeout_duplicate]], [[project_label_printer_platform_divergence]],
[[reference_rexod_label_printer_signals]]
