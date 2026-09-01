# 미픽업 처리 (READY → NOT_PICKED_UP) — 사전 배선

**상태: 서버 스펙 논의 중 · 앱 구현 완료(가칭 배선, analyze/test 통과) · 미배포.**

미확정 항목이 **3개**다 — 엔드포인트 모양, 상태 문자열, 소켓 이벤트명. 그래서
확정 시 교체 지점이 한 곳에 모이도록 배선했다(§2, §4.1). 남은 것은 §3 의 서버
확인 8건과 §6 실기기 검증이다. 배포까지 끝나면 [ARCHITECTURE.md](ARCHITECTURE.md)
로 흡수하고 이 문서는 삭제한다.

관련: [ORDER_FORCE_DONE.md](ORDER_FORCE_DONE.md) — 같은 "구현 완료·미배포" 상태의
선행 사례이고, Provider 골격(`forceCompleteOrder`)을 이 기능이 그대로 따랐다.

## 1. 문제

고객이 상품을 찾아가지 않은 채 남은 READY 주문을, 앱은 **취소로 처리하는 길밖에
없다**. 취소는 환불/결제취소를 뜻하므로 매출·정산에서 의미가 다르다.

점주 안내서에는 용어가 이미 실려 있다 —
[appfit-agent-guide.html:600](guide/appfit-agent-guide.html): "미픽업 처리 — 손님이
상품을 가져가지 않은 경우에 남기는 처리". i18n 확인 다이얼로그 문구
(`order_detail.dialog_not_picked_up_confirm_*`)도 3로캘에 있었으나 호출부가 0건인
dead key 였다.

레거시(kokonut)에는 숫자 상태코드 `2099 = 미픽업` 이 실재했고, 앱은 그것을
CANCELLED 로 뭉개고 있었다(`order_model.dart` 의 `// 미픽업 -> 취소 처리`).
**서버팀 논의 시 "과거에도 개념이 있었다" 는 근거로 쓸 수 있다.**

## 2. 스펙 (가칭) — 확정 전

### A안 (현재 가정) — 전용 엔드포인트

```
POST /v0/order/{orderNo}/not-picked-up
body: {}          // shopCode 는 Dio 인터셉터가 세션 값으로 채운다
200 → 성공
```

픽업 재요청(`POST /v0/order/{id}/pickup-noti`)과 같은 모양이라 서버 쪽 추가
비용이 작다. 다만 그쪽과 달리 **상태를 바꾼다**.

### B안 — 기존 상태 변경 API 재사용

```
PUT /v0/order/{orderNo}
body: {"action": "NOT_PICKED_UP", "readyTime": 0}
```

기존 `action` 어휘(ACCEPT/PICKUP_REQUEST/DONE/REJECT)에 값 하나를 더하는 안.

### 교체 방법

`lib/services/api_service.dart` 의 상수 하나를 바꾼다. 상위(Provider/UI/테스트)는
전혀 바뀌지 않는다.

```dart
static const _NotPickedUpTransport _kNotPickedUpTransport =
    _NotPickedUpTransport.dedicatedPost;   // ← updateAction 으로 바꾸면 B안
```

미채택 안을 `switch` 분기로 남겨 "논의 중" 이라는 사실 자체를 코드에 남겼다.
**확정 후 죽은 분기와 `_NotPickedUpTransport` enum 을 삭제할 것.**

경로는 `ApiService._provisionalNotPickedUpRoute` 에 가칭으로 둔다. appfit_core 의
`ApiRoutes` 가 아니라 **앱에 둔 이유**: core 는 별도 레포의 git ref 핀이라,
확정 전 경로를 넣으면 되돌릴 때 태그를 한 번 더 태워야 한다. 확정 후 core 로
승격하고 앱에서 지운다.

> **B안이 채택돼도 `ApiService.updateOrderStatus` 는 건드리지 않는다.** 그 switch 는
> 자동접수 경로(`_processNextEmit`)가 물려 있어 시그니처·분기를 바꾸면 사거리가
> 넓다. `forceCompleteOrder` 를 별도 메서드로 뺀 것과 정확히 같은 이유다.
> `OrderAction` enum 에도 값을 추가하지 않았다.

## 3. 서버팀에 남은 확인 항목

- [ ] **1. 엔드포인트 모양** — A안(전용 POST) / B안(PUT + action) 중 어느 쪽인가.
      v0 인가 v1 인가
- [ ] **2. 상태 문자열 정본** — `NOT_PICKED_UP` / `NOT_PICKUP` / `NO_SHOW` / 기타.
      목록(`GET /v1/orders`)의 `status` 와 상세(`GET /v1/orders/{id}`)의
      `orderStatus` **양쪽에 같은 값**으로 실리는가
- [ ] **3. 허용 선행 상태** — READY 만인가, PREPARING 도 되는가.
      **DONE 은 409 로 거부하는가** ← 가장 중요. §4.2(영구 분기)와 §4.7(버튼
      가시성 불일치) 두 항목이 이 답에 달려 있다. 앱 UI 는 READY 분기에서만
      버튼을 노출하지만, 팝업을 열어둔 사이 상태가 바뀌면 DONE 주문에 요청이
      나간다 — 즉 **앱이 READY 만 보낸다고 가정하면 안 된다**
- [ ] **3-1. NOT_PICKED_UP 에서 나가는 전이** — 미픽업 주문에 `DONE`/`REJECT`
      액션이 들어오면 수락하는가 409 인가. "들어가면 못 나오는 종결" 이어야
      §4.2 의 영구 분기가 성립하지 않는다
- [ ] **4. 멱등성** — 이미 미픽업인 주문에 재요청하면 200 인가 409 인가
      (`force/bulk-done` 은 멱등)
- [ ] **5. 금전 처리** — 환불/정산에 영향을 주는가. **주지 않는다면** 취소 영수증
      미발행 결정(§4.5)이 맞다
- [ ] **6. 소켓 이벤트 — 기존 타입을 재사용하지 않는가** ← 유무보다 이게 중요.
      **`ORDER_CANCELLED` 로 대신 쏘면 미픽업이 취소로 뒤집히고 세션 내 회복이
      안 된다**(§5.1-C). 새 타입(`ORDER_NOT_PICKED_UP` 등)이면 앱이 안전하게
      무시하므로 core 추가 일정은 나중에 잡아도 된다. 페이로드에 상태 문자열을
      실어주면 더 좋다 — 현재 `SocketEventPayload` 에는 status 필드가 없어
      이벤트 타입만으로 상태를 추론한다
- [ ] **7. `PICKUP_REQUESTED` 실사용 여부** — 이 값이 프로덕션 파서에 없어서
      READY 주문이 CANCELLED 로 떨어지는 상태였다. 선제 대응은 했으나(커밋
      `f63ff75`) 서버가 실제로 이 문자열을 쓰는지 확증이 필요하다
- [ ] **8. 목록 조회 필터** — `GET /v1/orders?status=NOT_PICKED_UP` 이 동작하는가.
      현재 앱은 `getNewOrders` 에서만 status 필터를 써서 당장은 무영향

## 4. 앱 구현

### 4.1 교체 지점은 3곳, 전부 두 파일 안

| 파일 | 상수 | 확정 시 할 일 |
|---|---|---|
| [order_status.dart](../lib/models/enums/order_status.dart) | `kNotPickedUpServerStatus` | 정본 문자열로 교체 |
| [order_status.dart](../lib/models/enums/order_status.dart) | `kNotPickedUpServerAliases` | **원소 1개로 축소** |
| [api_service.dart](../lib/services/api_service.dart) | `_kNotPickedUpTransport` | A/B 확정 + 죽은 분기 삭제 |

별칭(`NOT_PICKED_UP` / `NOT_PICKUP` / `NO_SHOW`)을 미리 받아두는 이유: 매핑표에
없는 값은 CANCELLED 로 떨어지므로, **서버 배포가 앱 배포보다 앞서면 미픽업 주문이
화면에 '취소' 로 보이는 무증상 실패**가 된다. 다만 별칭을 넓게 두면 서버가 다른
뜻으로 쓰는 값을 오매핑하므로, 확정 즉시 줄여야 한다.

`ApiService._mapAppFitOrderStatus` 는 `kServerOrderStatus` 표를 조회할 뿐이라
**손댈 일이 없다.** 선행 커밋(`f63ff75`)에서 파서 두 벌을 이 표로 합친 이유가
이것이다 — 그 전에는 프로덕션 파서와 테스트 파서가 각자 switch 를 들고 있었다.

### 4.2 터미널 우선순위 — `CANCELLED > NOT_PICKED_UP > 진행도 격자`

`kTerminalStatusPriority` 목록 순서가 그대로 우선순위이고,
`resolveMergedStatus` 가 **격자 접근보다 먼저** 이 목록을 순회한다.

미픽업을 `kOrderStatusProgress`(진행도 격자)에 **넣지 않는 것이 핵심이다.** 넣으면
`kOrderStatusProgress[s] ?? 0` 폴백에 걸려 NEW 급으로 취급되고, 서버가 stale READY
를 돌려줄 때마다 **종결된 주문이 폴링 주기마다 되살아난다.** 격자 밖 터미널로 두면
이 경로가 구조적으로 막힌다.

근거:
- **교환법칙이 필수다.** 이 함수는 `refreshOrders` 에서 `(local, server)` 로,
  `OrderSocketManager` 에서 `(order.status, eventStatus)` 로 불린다. 인자 순서에
  결과가 의존하면 폴링과 소켓이 서로를 덮어쓰며 화면이 깜빡인다. 리스트 순회
  방식(`local == t || server == t`)은 정의상 교환법칙을 만족한다.
- **취소가 이겨야 하는 이유는 금전이다.** 취소는 환불/결제취소를 수반하고 취소
  영수증 발행 트리거다. 취소를 미픽업으로 가리면 **환불 사실이 화면·영수증에서
  사라진다.** 반대(미픽업을 취소로 표시)는 오해를 낳지만 금전 사실은 보존된다 —
  비대칭 손실.
- **전이가 단방향이다.** `NOT_PICKED_UP → CANCELLED`(사후 클레임 환불)는
  현실적이지만 역방향은 성립하지 않는다.

`_applySuccessfulStatusTransition` 의 `_recentRemovals.mark` 도 같은 목록으로
판정한다(`kTerminalStatusPriority.contains`). 다만 **두 방어는 겹치지 않는다** —
`_recentRemovals` 필터는 서버가 *active*(NEW/PREPARING)로 돌려줄 때만 걸리고
(`isActiveOrderStatus` 조건), READY·DONE 응답은 통과시킨다. 즉 stale READY 부활을
막는 것은 `resolveMergedStatus` **하나뿐**이다.

**알려진 트레이드오프:** `(DONE, NOT_PICKED_UP)` → NOT_PICKED_UP 이 이긴다.
정답이 없는 경합이며, 서버가 §3-3 을 409 로 막으면 조합 자체가 생기지 않는다.

**서버가 허용할 경우의 실제 위험 — 영구 분기:**

1. 기기 A 가 미픽업 처리 성공 → 서버 = NOT_PICKED_UP, A 로컬 = NOT_PICKED_UP
2. 기기 B 가 (READY 때 열어둔 팝업에서) '주문 완료' → 서버가 받아주면 서버 = DONE
3. 기기 A 가 폴링 → `resolveMergedStatus(NOT_PICKED_UP, DONE)` → NOT_PICKED_UP

기기 A 는 **서버·기기 B 가 완료라고 하는 주문을 영원히 미픽업으로 표시**한다.
`resolveMergedStatus` 에는 TTL 이 없고, `_recentRemovals`(TTL 120초)는 DONE 응답을
통과시키므로 도움이 안 된다. 서버가 NOT_PICKED_UP 을 진짜 종결(들어가면 못 나옴)로
다루면 이 시퀀스가 성립하지 않는다.

대응 선택지(서버 답에 따라): `kTerminalStatusPriority` 에 `DONE` 을 2번째로 끼우거나,
`markOrderNotPickedUp` 에 선행 상태 가드를 넣는다(§4.7).

### 4.7 버튼 가시성과 전송 대상의 상태 출처가 다르다 (기존 구조, 미해결)

`order_detail_popup.dart` 의 `build()` 는 상세조회 결과에 **팝업 열 때 찍은 스냅샷
상태를 덮어씌운다**:

```dart
final order = orderDetailState.order?.copyWith(
  status: _originalOrder.status,          // ← 버튼 트리는 이 값을 본다
  orderStatus: _originalOrder.orderStatus,
);
```

그래서 READY 에서 팝업을 연 뒤 다른 기기가 완료 처리해도 **미픽업 버튼은 계속
보이고**, 누르면 서버 기준 DONE 인 주문에 미픽업 요청이 나간다.
`Order.markOrderNotPickedUp` 에도 선행 상태 가드가 없다(orderId 만 쓴다).

이것이 "UI 상 완료 섹션에서는 미픽업을 누를 수 없다" 는 구조적 방어를 뚫는
경로다. 강제 완료(`forceCompleteOrder`)도 같은 불일치를 안고 있다(기존 이슈).

- 서버가 §3-3 을 **409 로 거부**하면 → 서버가 안전망. 운영자는 에러 다이얼로그를
  본다. 앱 수정 불필요.
- 서버가 **수락**하면 → 앱에서 막아야 한다. 다만 가드 조건이 §3-3 의 "허용 선행
  상태" 에 달려 있으므로(READY 만? PREPARING 도?) **서버 답 이후에 구현한다.**

### 4.3 API — `ApiService.markOrderNotPickedUp`

`sendPickupNotification`(픽업 재요청)과 대비되는 판단 2가지:

- **건강도 카운터와 `_maybeInjectFault` 를 건다.** 픽업 재요청은 상태를 안 바꾸는
  사이드 액션이라 카운터 표본을 오염시키지만, 미픽업은 in-flight 락·낙관적 UI
  갱신을 전부 타는 진짜 상태 전이라 `NetFaultTarget.orderUpdate` 의 검증 대상이다.
- **예외를 삼켜 false 로 바꾸지 않는다.** 미배포 404 와 "서버가 상태를 거부함(409)"
  을 호출부가 구분해야 하고, 서버 메시지 원문이 가장 정확한 안내다.

정상 응답 로그는 `LogTag.API` 가 아니라 `LogTag.SYSTEM` 이다 — `[API]` 는
ERROR/실패/오류가 든 줄만 파일 화이트리스트를 통과한다(`logger.dart`).

### 4.4 Provider — `Order.markOrderNotPickedUp`

`forceCompleteOrder` 골격 그대로: storeId 가드 → 이미 미픽업이면 조기 반환 →
`statusUpdateInFlightProvider.tryAcquire`(같은 키 공간, 버튼 스피너 공유) →
`MOCK_` 우회 → API → `_applySuccessfulStatusTransition` → `finally` 에서 release.
`ApiException` 은 rethrow 해서 서버 메시지를 다이얼로그까지 올린다.

**`SocketEventSuppressor` 는 걸지 않는다** — core `OrderEventType` 에 미픽업
이벤트가 없어 억제할 대상 자체가 없다. `forceCompleteOrder` 가 2개를 거는 것과
대비되는 지점이라 코드에도 주석을 남겼다. §5 가 진행되면 여기에 추가한다.

### 4.5 UI·집계·표시

**버튼** — [order_detail_popup.dart](../lib/widgets/order/order_detail_popup.dart)
의 READY 분기 2곳(KDS `isKdsMode && READY`, 일반 `READY`) secondary 에 픽업 재요청
옆으로 넣었다. 픽업 재요청과 달리 `_handleStatusUpdate` 를 써서 **성공 시 팝업을
닫는다** — 카드가 완료 섹션/탭으로 옮겨가는 것 자체가 성공 신호라 성공
다이얼로그를 만들지 않았다.

> 이 두 분기는 반환값이 완전히 동일한 중복이다(픽업 재요청 커밋에서 그렇게 됐다).
> 이번에도 양쪽을 함께 고쳤고, 통합은 별건으로 남긴다.

**집계** — 미픽업은 **완료 쪽에 합류**한다. KDS 6번째 탭을 만들지 않았다.

| 지점 | 처리 |
|---|---|
| `kdsTabOrdersProvider.completed` | DONE + NOT_PICKED_UP |
| `orderStatusOrdersProvider.completedOrders` | DONE + CANCELLED + NOT_PICKED_UP |
| `filterOrders(OrderFilter.COMPLETED)` | DONE + READY + NOT_PICKED_UP |
| 취소 필터 / 취소 건수 칩 | **CANCELLED only 유지** — 미픽업이 섞이면 취소 집계가 오염된다 |

**표시** — 완료/취소와 색으로 구분한다. `AppStyles.kNotPickedUp`(딥오렌지) +
`orderPalette`/`orderSourcePalette` 의 `isNotPickedUp` 축(`isCancelled` 다음,
`muted` 보다 앞). KDS 완료 탭은 DONE 과 섞이므로 `_palette` 가 `cardType` 이 아니라
실제 상태를 보고, 저조도 주방 화면을 고려해 **'미픽업' 배지**도 함께 단다.

메인 카드의 **취소선과 회색 처리는 취소 전용으로 남겼다** — 미픽업까지 그으면 둘을
가르는 신호가 사라진다. 정사각 카드라 라벨 자리가 없어 색으로만 구분하고, 텍스트
구분은 상세팝업 상태 pill 이 담당한다.

**취소 영수증은 발행하지 않는다** (`OutputQueueService.addReceiptReprint` 는
`isCancelled` 만 본다). 미픽업은 환불이 아니라 운영상 종결이기 때문이다. 서버가
금전 처리를 붙이면(§3-5) 재검토한다.

### 4.6 테스트

| 파일 | 무엇을 고정하나 |
|---|---|
| `test/models/order_status_test.dart` | 터미널 우선순위 양방향, **교환법칙 전수**, 격자에 터미널이 없음, 매핑표·별칭 |
| `test/services/order_list_parsing_test.dart` | 가칭 문자열·별칭 → NOT_PICKED_UP, `PICKUP_REQUESTED` → READY |
| `test/services/api_service_not_picked_up_test.dart` | 가칭 경로를 친다 / 200→true / **404→ApiException** / 서버 message 원문 |
| `test/providers/order_ingestion_characterization_test.dart` (g-2) | **미픽업 후 stale READY 응답에 부활하지 않음** ← 핵심 회귀 테스트. 락 해제, 멱등 조기반환, rethrow |
| `test/providers/order_ingestion_characterization_test.dart` (b-2) | 완료 탭 합류 / 취소 탭 미포함 |
| `test/providers/order_history_sort_test.dart` | COMPLETED 필터 포함 / CANCELLED 필터 제외 |

## 5. 소켓 이벤트 — 이번 범위에서 제외

**뺀 이유:**

1. **크로스 레포 3개 동시 릴리스가 필요하다** — core `OrderEventType` 추가 →
   core 태그 릴리스(`tool/release.sh`) → 앱 `ref` 범프 + **DID 앱**
   (`did/lib/services/order_socket_listener.dart` 의 default 없는 exhaustive
   switch) 동시 수정·배포. 서버 이벤트명조차 미확정인데 3레포를 묶는 것은
   되돌리기 비용이 너무 크다.
2. **새 이벤트 타입이면 앱이 깨지지 않는다** — core `dispatcher.classify` 가
   `unknownEventType` 으로 분류하고 `order_socket_manager.dart` 가 로그만 남기고
   반환한다. `handled` 화이트리스트까지 도달하지도 않는다 (§5.1-B).
3. **정합성은 유지된다** — 버튼을 누른 단말은 낙관적 UI 로 즉시 반영되고, 다른
   단말은 폴링 주기 내에 따라잡는다(§4.1 의 상태 문자열 매핑이 있으므로 목록
   조회만으로 미픽업이 정확히 표시된다).

**대가:** 타 기기의 미픽업 처리가 폴링 주기만큼 지연된다. KDS 완료 탭 강조
애니메이션도 그 타이밍에 뜬다.

### 5.1 소켓 메시지가 올 때 / 안 올 때 — 경우별 실제 동작

서버가 무엇을 쏘느냐에 따라 셋으로 갈리고, **셋 중 하나만 위험하다.**

#### A. 아예 안 쏨 (현재 가정) — 안전

자기 기기는 낙관적 UI 로 즉시, 타 기기는 폴링이 `status` 문자열을 매핑표로 읽어
`resolveMergedStatus(READY, NOT_PICKED_UP)` → 미픽업으로 수렴한다. 지연만 있고
오염은 없다. **단, §4.1 의 매핑표에 서버 문자열이 없으면 CANCELLED 로 떨어진다**
— 별칭을 미리 받아둔 이유가 이것이다.

#### B. 새 이벤트 타입으로 쏨 (`ORDER_NOT_PICKED_UP` 등) — 안전, 다만 무시됨

`OrderEventTypeExtension.fromValue` 가 null → `unknownEventType` → 로그 후 반환.
크래시도 오염도 없지만 **실시간 반영도 없다** — 결과적으로 A 와 같다.

관측 문제가 하나 있었다: 이 분기가 `logger.d` 라 **파일 로그에 안 남아**, 서버가
이벤트를 쏘기 시작해도 기기 로그로는 알 수 없었다. `[WEBSOCKET]` 태그를 붙여
파일 화이트리스트를 통과시켰다(`logger.dart`). 빈도 위험은 낮다 —
`DEVICE_CALL_REQUESTED` 는 dispatcher 앞에서 가로채고, 알려진 주문 이벤트는
`OrderEventType` 이 전부 커버한다.

#### C. 기존 이벤트 타입을 재사용해 쏨 — **여기만 위험하다**

`handled` 화이트리스트를 통과하고 `_enforceStatusFromEvent` 가 **이벤트 타입만 보고**
상태를 보정한다(페이로드에 status 필드가 없다 — `SocketEventPayload` 는 이벤트
타입과 id 들만 싣는다). 결과는 재사용한 타입에 따라 정반대다:

| 서버가 쏘는 타입 | `resolveMergedStatus(미픽업, 이벤트상태)` | 결과 |
|---|---|---|
| `ORDER_DONE` | 미픽업 (터미널이 진행도를 이김) | **무해** — 보정 생략, 로그만 |
| `ORDER_CANCELLED` | **취소** (취소가 최우선) | **오염** — 미픽업이 취소로 뒤집힌다 |

`ORDER_CANCELLED` 재사용은 **세션 내 회복이 불가능하다.** 로컬이 CANCELLED 가 된
뒤에는 폴링이 서버의 NOT_PICKED_UP 을 가져와도
`resolveMergedStatus(CANCELLED, NOT_PICKED_UP)` → CANCELLED 로 계속 유지된다.
앱을 재시작해야(로컬 값이 비워져야) 서버 값으로 돌아온다.

자가 echo 도 같다 — 이 기기가 미픽업 처리한 직후 서버가 `ORDER_CANCELLED` 를
돌려주면 방금 만든 로컬 상태가 취소로 덮인다. `SocketEventSuppressor` 를 안 걸어
뒀으므로 막히지 않는다(§4.4). 그렇다고 `orderCancelled` 를 억제하면 TTL 동안
**진짜 취소**까지 삼키므로 그 방향은 답이 아니다.

**→ 그래서 §3-6 은 "이벤트를 쏘는가" 가 아니라 "기존 타입을 재사용하지 않는가" 를
물어야 한다.** 새 타입이면 B(무시)로 안전하게 착지하고, 이후 §5 재개 순서를 밟아
실시간성을 얹으면 된다. 앱 쪽에서 A/B/C 를 구분할 방법은 없다 — 페이로드에 상태가
없어 `ORDER_CANCELLED` 가 진짜 취소인지 미픽업의 대역인지 알 수 없기 때문이다.

**재개 시 순서 (이 순서를 지킬 것):**

1. 서버 이벤트명 확정 (§3-6)
2. core `order_event_types.dart` 에 enum 값 + `value` switch 추가
3. core 태그 릴리스 → 앱 `pubspec.yaml` 의 `ref` 범프
4. **DID 앱의 exhaustive switch 동시 수정** ← 빠뜨리면 DID 가 컴파일 실패
5. 앱 `order_socket_manager.dart` 의 `handled` 화이트리스트 + `eventStatus` 매핑
6. `order_provider.dart` 의 `markOrderNotPickedUp` 에 `SocketEventSuppressor` 추가

## 6. 검증

**엔드포인트 확정 전 (지금 가능):**

- READY 주문 상세팝업에 '미픽업 처리' 버튼이 픽업 재요청 옆에 뜬다
- 누르면 확인 다이얼로그 → **404 에러 다이얼로그**가 뜨고 팝업은 닫히지 않는다
  (미배포 서버의 기대 동작)
- 연타 시 `AsyncActionButton` 스피너로 막힌다
- 서로 다른 주문 2건을 연달아 실패시켜도 **두 번째 에러 다이얼로그가 뜬다**
  (dedupeKey 주문별 분리)

**엔드포인트 확정 후:**

- §4.1 의 3곳 교체 → 실주문으로 READY → 미픽업 전이
- 카드가 완료 섹션/탭으로 이동하고, 딥오렌지 색 + 배지로 완료·취소와 갈린다
- 취소 건수 칩이 늘지 않는다
- **폴링 1주기(및 앱 재시작) 후에도 부활하지 않는다** ← 가장 중요
- 두 단말 중 한쪽에서 처리 시 다른 쪽이 폴링 주기 내에 따라잡는다
