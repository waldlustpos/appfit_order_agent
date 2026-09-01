# 미픽업 처리 (READY → NOT_PICKED_UP)

**상태: 서버 스펙 확정 · 앱 구현 완료(analyze/test 통과) · 실기기 검증 대기 · 미배포.**

남은 것은 §3 의 서버 확인 3건과 §6 검증이다. 그중 **상태 문자열 실측(§3-1)이
가장 중요하다** — 틀리면 미픽업이 화면에 '취소' 로 조용히 표시된다.
배포까지 끝나면 [ARCHITECTURE.md](ARCHITECTURE.md) 로 흡수하고 이 문서는 삭제한다.

관련: [ORDER_FORCE_DONE.md](ORDER_FORCE_DONE.md) — 같은 "구현 완료·미배포" 상태의
선행 사례. 다만 그쪽은 **전용 메서드를 유지**하고 이쪽은 **흡수**했다. 그 차이의
근거가 §2 에 있다.

## 1. 문제

고객이 상품을 찾아가지 않은 채 남은 READY 주문을, 앱은 **취소로 처리하는 길밖에
없었다**. 취소는 환불/결제취소를 뜻하므로 매출·정산에서 의미가 다르다.

점주 안내서에는 용어가 이미 실려 있었다 —
[appfit-agent-guide.html:600](guide/appfit-agent-guide.html): "미픽업 처리 — 손님이
상품을 가져가지 않은 경우에 남기는 처리". i18n 확인 다이얼로그 문구
(`order_detail.dialog_not_picked_up_confirm_*`)도 3로캘에 있었으나 호출부가 0건인
dead key 였다.

레거시(kokonut)에는 숫자 상태코드 `2099 = 미픽업` 이 실재했고, 앱은 그것을
CANCELLED 로 뭉개고 있었다(`order_model.dart` 의 `// 미픽업 -> 취소 처리`).

## 2. 스펙 — 확정

staging swagger `주문 상태 관리 Ex API v0` / `updateOrderStatus`:

```
PUT /v0/order/{orderNo}
body: {"action": "NO_SHOW", "readyTime": 0}

NO_SHOW: 미픽업 처리 (NEW·PREPARING·READY → NO_SHOW)
         고객 알림 및 외부 이벤트 미발행
```

**기존 상태 변경 엔드포인트와 동일하다.** 그래서 전용 경로를 만들지 않고
`ApiService.updateOrderStatus` / `Order.updateOrderStatus` 로 **흡수**했다.

### 왜 흡수했나 — `forceCompleteOrder` 와 다른 판단인 이유

사전 배선 시점에는 "`updateOrderStatus` 의 switch 는 자동접수가 물려 있어 사거리가
넓다" 는 이유로 전용 메서드를 뒀다. 엔드포인트 확정 후 실코드로 재검증한 결과 그
판단은 **이 건에는 성립하지 않는다**:

- `ApiService.updateOrderStatus` 의 action switch 는 `default:` 가 있어
  **non-exhaustive** → 케이스 추가는 순수 가산이다
- `Order.updateOrderStatus` 의 `expectedEventType` switch 는 `_ => null` 이라
  `NOT_PICKED_UP` 이 **이미 통과**한다. "외부 이벤트 미발행" 스펙과 코드가 이미 일치
- 자동접수 고유 상태(`_selfAcceptedOrderIds`·`_autoAcceptingOrderIds`·출력큐·NEW
  롤백)는 **전부 호출부(`_processNewOrder`)에 있고 `updateOrderStatus` 본문에는
  0줄**이다. 두 호출부 모두 `(order, PREPARING, readyTime:)` 고정이라 새 상태값이
  그 경로를 바꾸지 않는다
- 원 판단이 걱정한 것은 "시그니처·분기 변경" 인데 `NO_SHOW` 는 시그니처를 안 바꾼다

**`forceCompleteOrder` 는 그대로 유지한다** — 엔드포인트(`force/bulk-done`),
응답 DTO(`ForceBulkDoneResponse`, 건별 판정), suppressor 개수(2개)가 모두 달라
흡수 근거가 성립하지 않는다. 그때의 판단은 옳았고, **그것을 이 건에 이식하면
틀린다**.

### action 어휘 ≠ status 어휘

서버는 요청의 `action` 과 응답의 `status` 에 다른 단어를 쓴다:
`ACCEPT`→`ACCEPTED`, `PICKUP_REQUEST`→`PICKUP_REQUESTED`, `REJECT`→`CANCELED`.

그래서 `OrderAction.NO_SHOW`(요청)와 `kNotPickedUpServerStatus`(응답 매핑)를
**별개 상수로 분리**했다. 사전 배선 때 이 둘을 겸용해 잘못된 action 이 나가는
버그가 있었다.

## 3. 서버팀에 남은 확인 항목

- [ ] **1. 상태 문자열 정본** ← 가장 중요. NO_SHOW 처리 후 목록(`GET /v1/orders`)의
      `status` 와 상세의 `orderStatus` 가 `NO_SHOW` 인가. action 과 다른 단어일
      수 있다(위 참조). 틀리면 매핑표에서 빠져 **미픽업이 '취소' 로 조용히 표시**된다
- [ ] **2. 거부 시 error code** — DONE 주문에 NO_SHOW 를 보내면 응답 `code` 가
      `INVALID_ORDER_STATUS` 인가. 그래야 §4.6 의 안내 문구가 뜬다. 다른 코드면
      `updateOrderStatus` 가 `false` 로 삼켜 범용 문구가 뜨므로, 그때는
      `api_service.dart` 의 코드 판정을 화이트리스트(Set)로 넓힌다
- [ ] **3. NO_SHOW 에서 나가는 전이** — 미픽업 주문에 `DONE`/`REJECT` 가 들어오면
      거부하는가. "들어가면 못 나오는 종결" 이어야 §4.2 의 영구 분기가 성립하지 않는다

**해소됨:** 엔드포인트 모양 · 허용 선행 상태(NEW·PREPARING·READY, DONE 제외) ·
소켓 이벤트 유무(미발행) · 멱등성(앱이 로컬 상태로 조기 반환하므로 무영향).

## 4. 앱 구현

### 4.1 확정 후 남은 교체 지점은 1곳

| 파일 | 상수 | 확정 시 할 일 |
|---|---|---|
| [order_status.dart](../lib/models/enums/order_status.dart) | `kNotPickedUpServerStatus` | §3-1 실측값으로 확정 |
| [order_status.dart](../lib/models/enums/order_status.dart) | `kNotPickedUpServerAliases` | **원소 1개로 축소** |

현재 `'NO_SHOW'` 를 정본으로 두고 `'NOT_PICKED_UP'` 을 방어 별칭으로 남겼다.
매핑표에 없는 값은 CANCELLED 로 떨어지므로, 응답 status 가 다른 단어면 무증상
실패가 된다. **판정은 화면이 아니라 로그로 한다** — 별칭이 먹으면 화면은 정상으로
보이고, 미매핑일 때만 `알 수 없는 주문 상태` 경고가 뜬다.

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
판정한다. 다만 **두 방어는 겹치지 않는다** — `_recentRemovals` 필터는 서버가
*active*(NEW/PREPARING)로 돌려줄 때만 걸리고(`isActiveOrderStatus` 조건),
READY·DONE 응답은 통과시킨다. 즉 stale READY 부활을 막는 것은
`resolveMergedStatus` **하나뿐**이다.

**알려진 트레이드오프:** `(DONE, NOT_PICKED_UP)` → NOT_PICKED_UP 이 이긴다.
서버가 DONE→NO_SHOW 를 거부하므로 이 조합은 앱이 만들 수 없고, 남는 위험은
**NO_SHOW 에서 나가는 전이**(§3-3)뿐이다. 서버가 그것도 거부하면 아래 시퀀스가
성립하지 않는다:

1. 기기 A 가 미픽업 처리 성공 → 서버 = NO_SHOW, A 로컬 = NOT_PICKED_UP
2. 기기 B 가 '주문 완료' → 서버가 받아주면 서버 = DONE
3. 기기 A 가 폴링 → `resolveMergedStatus(NOT_PICKED_UP, DONE)` → NOT_PICKED_UP

기기 A 는 **서버·기기 B 가 완료라고 하는 주문을 영원히 미픽업으로 표시**한다.
`resolveMergedStatus` 에는 TTL 이 없고 `_recentRemovals`(TTL 120초)는 DONE 응답을
통과시키므로 도움이 안 된다. 앱 재시작으로만 회복된다. 문제가 되면
`kTerminalStatusPriority` 에 `DONE` 을 2번째로 끼우는 1줄 변경으로 대응한다.

### 4.3 API — `ApiService.updateOrderStatus` (전용 메서드 없음)

action switch 에 케이스 1줄:

```dart
case OrderStatus.NOT_PICKED_UP:
  action = OrderAction.NO_SHOW.name;
  break;
```

`_maybeInjectFault(NetFaultTarget.orderUpdate)`·건강도 카운터·`INVALID_ORDER_STATUS`
보강이 전부 공짜로 따라온다.

**에러는 `false` 로 삼켜진다** (`INVALID_ORDER_STATUS` 제외). 이는
`api_fault_injection_test.dart` 가 고정한 기존 계약이며, 접수/픽업요청/완료 버튼과
동일한 취급이다. 미픽업의 주된 실패 사유(잘못된 선행 상태)는
`INVALID_ORDER_STATUS` 분기가 잡아 구체적 안내를 띄운다(§4.6).

### 4.4 Provider — `Order.updateOrderStatus` (전용 메서드 없음)

in-flight 락(같은 키 공간, 버튼 스피너 공유) → 멱등 조기반환(`status == newStatus`)
→ `MOCK_` 우회 → API → `_applySuccessfulStatusTransition` → `finally` release.
`ApiException` 은 rethrow 되어 서버 메시지가 다이얼로그까지 올라간다.

**`SocketEventSuppressor` 를 걸지 않는다** — 서버가 미픽업에 대해 외부 이벤트를
**발행하지 않기로 확정**했으므로 억제할 self-echo 가 없다. `expectedEventType` 의
`_ => null` 이 그 정본이다. 나중에 서버가 이벤트를 추가하면 그 switch 에 케이스
1줄을 더하는 것으로 끝난다(§5 재개 순서).

### 4.5 UI·집계·표시

**버튼** — [order_detail_popup.dart](../lib/widgets/order/order_detail_popup.dart)
의 READY 분기 2곳(KDS `isKdsMode && READY`, 일반 `READY`) secondary 에 픽업 재요청
옆으로 넣었다. 서버는 NEW·PREPARING 도 허용하지만 **READY 만 노출한다** — 미픽업은
"만들어놨는데 안 찾아감" 이 본래 의미라 NEW/PREPARING 에서는 취소가 맞다.

핸들러는 `requestPickup`/`completeOrder` 와 같은 관용구다. 다른 점은 **확인
다이얼로그 하나** — 되돌릴 수 없는 종결이라 한 번 묻는다. 성공하면
`_handleStatusUpdate` 가 팝업을 닫고, 카드가 완료 섹션/탭으로 옮겨가는 것 자체가
성공 신호라 성공 다이얼로그는 없다.

> 이 두 분기는 반환값이 완전히 동일한 중복이다(픽업 재요청 커밋에서 그렇게 됐다).
> 통합은 별건으로 남긴다.

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
`isCancelled` 만 본다). 미픽업은 환불이 아니라 운영상 종결이기 때문이다.

### 4.6 버튼 가시성과 전송 대상의 상태 출처가 다르다 — 서버가 안전망

`order_detail_popup.dart` 의 `build()` 는 상세조회 결과에 **팝업 열 때 찍은 스냅샷
상태를 덮어씌운다**:

```dart
final order = orderDetailState.order?.copyWith(
  status: _originalOrder.status,          // ← 버튼 트리는 이 값을 본다
  orderStatus: _originalOrder.orderStatus,
);
```

그래서 READY 에서 팝업을 연 뒤 다른 기기가 완료 처리해도 **미픽업 버튼은 계속
보이고**, 누르면 서버 기준 DONE 인 주문에 요청이 나간다. 강제 완료
(`forceCompleteOrder`)도 같은 불일치를 안고 있다(기존 이슈).

**앱 가드는 넣지 않았다** — DONE 이 서버의 허용 선행 상태에서 빠져 있어 서버가
거부하고, `INVALID_ORDER_STATUS` 분기가 `getOrder` 로 현재 상태를 재조회해
**"이미 완료된 주문입니다."** 라는 구체적 안내를 띄운다. 서버 원문보다 나은 문구다.
(§3-2 가 확인되지 않으면 이 안내 대신 범용 문구가 뜬다.)

`overrideMsg` switch 에 `NOT_PICKED_UP => '이미 미픽업 처리된 주문입니다.'` 도
추가해, 로컬 상태가 stale 해서 이미 미픽업인 주문에 다시 요청이 나가는 경우를
덮는다(보통은 provider 의 멱등 조기반환이 먼저 걸린다).

### 4.7 테스트

| 파일 | 무엇을 고정하나 |
|---|---|
| `test/models/order_status_test.dart` | 터미널 우선순위 양방향, **교환법칙 전수**, 격자에 터미널이 없음, 매핑표·별칭 |
| `test/services/order_list_parsing_test.dart` | 상태 문자열·별칭 → NOT_PICKED_UP, `PICKUP_REQUESTED` → READY |
| `test/services/api_fault_injection_test.dart` | **NOT_PICKED_UP 이 `action=NO_SHOW` 로 PUT 된다** (action/status 겸용 버그 회귀 방지) + 삼킴 계약 |
| `test/providers/order_ingestion_characterization_test.dart` (g-2) | **미픽업 후 stale READY 응답에 부활하지 않음** ← 핵심 회귀. 멱등 조기반환, **소켓 미억제** |
| `test/providers/order_ingestion_characterization_test.dart` (b-2) | 완료 탭 합류 / 취소 탭 미포함 |
| `test/providers/order_ingestion_characterization_test.dart` (f) | in-flight 락·예외 후 락 해제 — 상태 무관이라 미픽업도 커버 |
| `test/providers/order_history_sort_test.dart` | COMPLETED 필터 포함 / CANCELLED 필터 제외 |

## 5. 소켓 이벤트 — 서버가 발행하지 않는다

스펙에 **"고객 알림 및 외부 이벤트 미발행"** 이 명시됐다. 따라서:

- 자기 기기는 낙관적 UI 로 즉시 반영
- **타 기기는 폴링 주기 내에 따라잡는다** — 이는 임시 제약이 아니라 **설계상
  영구 특성**이다. KDS 완료 탭 강조 애니메이션도 그 타이밍에 뜬다
- `SocketEventSuppressor` 는 영구 불필요(§4.4)

### 5.1 나중에 서버가 이벤트를 추가한다면 — 기존 타입 재사용 금지

사전 배선 단계에서 세 시나리오를 분석했다. 그 결론은 **지금도 유효한 제약**이라
남긴다.

| 서버가 쏘는 것 | 앱 동작 | 판정 |
|---|---|---|
| 아무것도 안 쏨 (현재) | 폴링으로 수렴 | 안전 |
| **새 타입** (`ORDER_NOT_PICKED_UP` 등) | `unknownEventType` 으로 조용히 버려짐 | 안전, 무시됨 |
| `ORDER_DONE` 재사용 | `resolveMergedStatus(미픽업, DONE)` → 미픽업. 보정 생략 | 무해 |
| **`ORDER_CANCELLED` 재사용** | `resolveMergedStatus(미픽업, CANCELLED)` → **취소** | **오염** |

`ORDER_CANCELLED` 재사용은 **세션 내 회복이 불가능하다.** 로컬이 CANCELLED 가 된
뒤에는 폴링이 서버의 NO_SHOW 를 가져와도
`resolveMergedStatus(CANCELLED, NOT_PICKED_UP)` → CANCELLED 로 유지된다. 앱을
재시작해야 서버 값으로 돌아온다. 자가 echo 도 같다.

**앱에서는 이를 구분할 방법이 없다** — `SocketEventPayload` 에 status 필드가 없어
이벤트 타입만으로 상태를 추론하므로, `ORDER_CANCELLED` 가 진짜 취소인지 미픽업의
대역인지 알 수 없다. `orderCancelled` 를 억제하면 TTL 동안 진짜 취소까지 삼킨다.

**관측:** `unknownEventType` 분기에 `[WEBSOCKET]` 태그를 붙여 파일 로그
화이트리스트를 통과시켰다. 서버가 새 이벤트를 쏘기 시작하면 기기 로그로 확인된다.

**재개 시 순서 (이 순서를 지킬 것):**

1. 서버 이벤트명 확정 — **기존 타입 재사용이 아닌지 먼저 확인**
2. core `order_event_types.dart` 에 enum 값 + `value` switch 추가
3. core 태그 릴리스 → 앱 `pubspec.yaml` 의 `ref` 범프
4. **DID 앱의 exhaustive switch 동시 수정** ← 빠뜨리면 DID 가 컴파일 실패
5. 앱 `order_socket_manager.dart` 의 `handled` 화이트리스트 + `eventStatus` 매핑
6. `order_provider.dart` 의 `expectedEventType` switch 에 케이스 1줄

## 6. 검증

**스테이징 실기기 — 정상 경로**

1. READY 주문 상세팝업에 '미픽업 처리' 버튼이 픽업 재요청 옆에 뜬다
2. 누르면 확인 다이얼로그 → 성공하고 **팝업이 닫힌다**
3. 카드가 완료 섹션/탭으로 이동하고 **딥오렌지 색 + '미픽업' 배지**로 완료·취소와 갈린다
4. **취소 건수 칩이 늘지 않는다**
5. **폴링 1주기 후에도, 앱 재시작 후에도 부활하지 않는다** ← 가장 중요

**상태 문자열 실측 (§3-1)**

위 처리 직후 목록/상세를 조회한다. 화면이 '미픽업' 으로 뜨는 것만으로는 판정할 수
없다 — 방어 별칭이 먹었을 수 있다. **로그에 `알 수 없는 주문 상태 "..." → CANCELLED`
경고가 있는지**로 판정하고, 없으면 어느 문자열이 매핑됐는지 응답 원문으로 확인한다.
확정 후 `kNotPickedUpServerAliases` 를 1개로 줄인다.

**거부 경로 (§3-2)**

팝업을 READY 에서 연 뒤 다른 기기로 완료 처리 → 미픽업 버튼 누름 →
**"이미 완료된 주문입니다."** 가 뜨면 `INVALID_ORDER_STATUS` 확인. 범용 문구
("주문 상태 변경에 실패했습니다.")가 뜨면 서버가 다른 코드를 쓰는 것이므로
`api_service.dart` 의 코드 판정을 넓혀야 한다.

**다기기 수렴**

기기 A 에서 미픽업 → 기기 B 가 폴링 주기 내에 따라잡는지. 소켓 이벤트가 없으므로
즉시 반영은 기대하지 않는다(§5).

**연타·중복**

`AsyncActionButton` 스피너 + `statusUpdateInFlightProvider` 락으로 막히는지.
서로 다른 주문 2건을 연달아 실패시켜도 두 번째 에러 다이얼로그가 뜨는지
(`dedupeKey` 주문별 분리).
