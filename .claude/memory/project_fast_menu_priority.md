---
name: project_fast_menu_priority
description: 빠른 제조 메뉴 우선 출력 기능 — 구현 완료·미커밋·실기기 미검증. 모드 2(주문 간 추월)는 현장 검증 후 켤 것
metadata: 
  node_type: memory
  type: project
  originSessionId: 6533b9fb-864e-4ce6-bf7e-7fd77589eb30
  modified: 2026-08-12T07:42:52.591Z
---

2026-08-12 구현 완료. 매장 요청("아이스 아메리카노가 앞 주문에 밀림") 대응. **미커밋, 실기기 미검증.**

설계·불변식은 [docs/ARCHITECTURE.md](../../../../Documents/GitHub/appfit_order_agent/docs/ARCHITECTURE.md) "빠른 제조 메뉴 우선 출력" 항목과 코드 주석에 있음. 여기엔 그 문서에 없는 것만 기록한다.

**롤아웃 상태**: 모드 1 현장 관찰 완료. 2026-08-12 **D2s 실기기에서 모드 2 전 시나리오 검증 완료** — A(추월), B(가드가 정확히 3회에서 발동, 16:01 구간), C(재출력 면역, 16:36 구간에서 실제로 발동), E(cupIdx 불변). **미커밋 상태.** 남은 것: 커밋·배포 판단.

**혼합 주문이 많은 매장이면 모드 2 효용이 작다**: `isFastOrder` 는 `menus.every(isFast)` 라 빠른 메뉴가 4개 들어도 다른 메뉴 하나 섞이면 추월 대상이 아니다. 그런 매장은 **모드 1(주문 내 정렬)이 주력**이고 모드 2는 보너스. 매장 주문 패턴(전량-커피 주문 비중)을 보고 모드를 정할 것.

**현장 순서 검증은 반드시 로그로**: 키오스크 주문이 서버·소켓을 거쳐 라벨 큐에 도달하는 시점은 **클릭 순서와 다르다**(실측 45초 차이). 육안 출력만 보면 가드가 고장난 것처럼 보인다. 판정법: 느린 주문의 `enqueue (일반)` 줄을 찾고 **그 뒤에** 오는 `PRIORITY enqueue` 개수를 센다 — 3이면 정상. 대기열이 비어 있으면 추월 자체가 일어나지 않으므로 "빠른 주문 N개 연속"은 정상일 수 있다.

**D2s 로그 접근**: Android 릴리즈는 `developer.log` 가 **logcat 에 안 나온다**(AOT). logcat 에는 Java `LabelPrinter` 줄만. Dart 로그는 `adb pull /sdcard/Documents/appfit/appfit_YYYY-MM-DD.txt` (Git Bash 는 `MSYS_NO_PATHCONV=1` 필요).

**cupIdx 는 절대 불변 (가장 중요한 제약)**: 라벨의 `orderIndex` 는 인쇄 카운터가 아니라 **컵의 고유 식별자**다 — QR 스캔 후 서버 데이터와 대조해 별도 처리하는 용도. 채번은 반드시 **원본 메뉴 순서** 기준이고, 정렬은 순회(인쇄) 순서만 바꾼다. 그 대가로 인쇄 순번이 단조 증가하지 않는다(2/3 → 3/3 → 1/3). **이건 버그가 아니라 계약이다.**
- 함정: `getLabelQrPayloadFormat()` 기본값이 **1(신규)** 이라 운영 기본 전략은 `DisplayNumIndexQrPayloadStrategy` 이고, 이게 `cupIdx = labelIndex - 1` 로 순번을 직접 쓴다. "Default 전략은 labelSeq 기반이니 안전" 이라고 판단하면 **틀린다** — Default 는 기본값이 아니다.

**실기기에서 반드시 볼 것**:
- 정렬 전후 QR 페이로드가 동일한가 (기존 라벨과 대조) — 최우선
- TPCP 기기에서 sub-info 4개(빠름/사이즈/온도/원두) 동시 노출 시 라벨 폭 잘림 — **유일하게 미검증인 레이아웃 리스크**
- 버스트에서 `[LabelQueue] … PRIORITY enqueue` 로그로 판정 결과 추적
- 모드 2 가 안 먹는 것처럼 보이면 `빠른 메뉴 판정 불가 (메뉴 미로드)` 로그 확인 — 자동접수가 상세 없이 enqueue 하면 전량 빠른 주문이어도 일반 처리된다

**설계 중 뒤집힌 판단 3건** (같은 실수 반복 방지):
- `menuStartIndex` 채번을 정렬된 순서로 바꿔 인쇄 순번을 단조 증가시켰다가 되돌렸다. cupIdx 가 서버 대조용 식별자라 출력 편의로 흔들면 안 됨. **"보기 좋은 번호" 와 "식별자" 를 구분할 것.**
- 처음엔 재출력(`ReprintJob`)을 그냥 FIFO 로 넣었는데 뒤에 온 빠른 주문에게 추월당했다. 운영자가 프린터 앞에서 기다리는 요청이라 틀렸음 → `protectedFromPriority` 도입. **큐에 우선순위를 넣을 땐 "밀리면 안 되는 항목"을 먼저 열거할 것.**
- `_enqueueLabel` 이 `ref.read(fastMenuPolicyProvider)` 를 그대로 호출해 SharedPreferences 미초기화 시 라벨 enqueue 가 통째로 죽었다(기존 테스트 4건 실패로 발각). **부가 기능의 설정 조회가 출력 경로를 죽일 수 있는 구조는 항상 fail-safe 로 감쌀 것.**

관련: [[project_order_intake_essential_complexity]] · [[feedback_queue_enqueue_timing]] · [[project_label_qr_cupidx_collision]]
