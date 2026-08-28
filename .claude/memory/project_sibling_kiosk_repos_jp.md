---
name: project-sibling-kiosk-repos-jp
description: "일본 결제(Square)·Shift_JIS 영수증·POST /v1/orders 구현은 형제 레포 kiosk_v3_japan / kiosk_v4 에 이미 있다. \"신규 개발\" 판단 전 반드시 훑을 것"
metadata: 
  node_type: memory
  type: project
  originSessionId: 28d866f9-2136-4185-90f7-b11a6016fcab
  modified: 2026-08-28T01:23:48.317Z
---

`~/Documents/GitHub/` 아래 형제 레포에 **일본 매장용 구현이 이미 프로덕션으로 존재**한다. appfit_order_agent 안에서만 보면 "신규 개발"로 오판하게 된다.

| 레포 | 있는 것 |
|---|---|
| `kiosk_v3_japan` | Square Terminal API 일체(`lib/features/square/` — Devices/Terminal/Refund, 폴링 1.5초 + PING 5분, 페어링 UI). **웹훅 미사용 → 백엔드 불필요**. 인증은 OAuth 아니라 매장별 액세스 토큰+Location ID. `lib/service/print_services.dart` = Shift_JIS 영수증 + 領収書 출력(`charset_converter`) |
| `kiosk_v4` | `lib/features/pay/data/m_appfit_order.dart` = `POST /v1/orders` 완성 클라이언트(inShopPrice·payments[]·할인 라인/주문 중복금지 규칙). `appfit_save_strategy.dart` + `failed_order_retry_service.dart` = 결제성공/서버저장실패 재시도 큐. `docs/settings-rr.md` = 키오스크 설정 R&R 정본 |
| `kiosk_v4_japan` | **이 머신에 없음(clone 필요).** v3 의 후속 |

**Why:** 2026-08 Simple POS 타당성 조사 1차에서 "Square 연동 = 최대 리스크, 신규 개발"이라 판단했다가 재검증에서 뒤집혔다. 형제 레포를 안 봤기 때문이다. 같은 이유로 "영수증 CP949라 일본어 재작업 필요"도 오판이었다(Sunmi 내장은 AIDL이라 인코딩 무관 + Shift_JIS 구현이 이미 존재).

**How to apply:** 일본·결제·영수증·POS·키오스크가 걸린 타당성/설계 판단 전에 `grep -ril <키워드> ~/Documents/GitHub/kiosk_v3_japan ~/Documents/GitHub/kiosk_v4` 를 먼저 돌린다. 단 이 레포들은 설정을 POS 웹 어드민(CFG)에서 받으므로 **이식할 때 `settingsProvider` 의존을 걷어내야 한다** — Simple POS 는 POS 서버 계열을 전면 배제하고 AppFit 단독으로 간다([[project-simple-pos-jp]] 전제, 정본 `docs/SIMPLE_POS_JP.md`).

관련: [[project-appfit-core-dual-repo]]
