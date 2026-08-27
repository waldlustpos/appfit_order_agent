# 주문 강제 완료 (PREPARING → DONE) — 구현 준비

**상태: 서버 staging 구현 완료 · 앱 구현 완료(analyze/test 통과) · 실기기 검증 대기 · 미배포.**
남은 것은 §3 의 서버 확인 3건과 §6 실기기 검증이다. 배포까지 끝나면 내용을
[ARCHITECTURE.md](ARCHITECTURE.md) 로 흡수하고 이 문서는 삭제한다.

선행 작업이던 appfit_core 라우트 추가는 **v1.5.0 으로 릴리즈 완료**(앱 `ref` 도 범프됨).

## 1. 문제

주문 상태는 서버가 `NEW → PREPARING → READY → DONE` 단계를 강제한다
(`PUT /v0/order/{orderNo}` 의 `DONE` 은 **READY → DONE** 만 허용).

그런데 앱은 PREPARING 주문 상세창에 이미 '주문 완료' 버튼을 노출한다 —
[order_detail_popup.dart:785](../lib/widgets/order/order_detail_popup.dart#L785).
누르면 `action=DONE` 이 400 `INVALID_ORDER_STATUS` 로 떨어지고,
[api_service.dart:299](../lib/services/api_service.dart#L299) 의 보강 로직이 이를
**"이미 수락된 주문입니다."** 로 바꿔 보여준다. 실패인데 실패로 안 읽히는 문구라
현장에서 오해를 만든다.

픽업 요청을 거치지 않고 바로 완료시키는 서버 API 가 필요하다.

## 2. 스펙 정본 — `PUT /v0/orders/force/bulk-done`

staging(core-stgapi) 실측, 2026-08-27. `operationId: forceBulkDoneOrders`,
summary "주문 완료 일괄 변경 (강제, 주문번호 지정)".

> 선택한 주문들을 선행 상태 검증 없이 완료 상태까지 강제로 이행한다.
> - 대상: 요청한 매장의 PREPARING/READY 상태 주문
> - PREPARING 주문은 픽업 요청을 거치지 않고 바로 완료 처리된다 (PREPARING → DONE)
>
> 부분 실패해도 200 OK 이며, results 에 건별 성공 여부와 실패 사유가 담긴다.

**요청** (`ForceBulkDoneOrdersRequest`, required: `shopCode`, `orderNos`)

```jsonc
{
  "shopCode": "TPCP0001",     // 발트 매장코드 또는 협력사(pos, kiosk) 매장코드
  "orderNos": ["1234567890"]  // 최대 100건, 중복은 1건으로 처리. 단건이면 원소 1개
}
```

**응답 200** — 부분 실패해도 200. `data` 안에 건별 결과가 온다.

```jsonc
{
  "code": "…", "message": "…",
  "data": {
    "targetOrderCount": 1,     // 중복 제거 후 대상 수. results 길이와 같다
    "updateSuccessCount": 1,
    "updateFailCount": 0,
    "results": [               // 요청 순서 보존
      { "orderNo": "1234567890", "success": true, "errorCode": null, "message": null }
    ]
  }
}
```

- `success` 는 **멱등**이다 — "이미 완료된 주문은 성공으로 응답한다". 재시도가 안전하다.
- `errorCode` 예시값: `NOT_FOUND_ORDER`, `ACCESS_DENIED`, `INVALID_ORDER_STATUS`,
  `ORDER_STATUS_UPDATE_FAILED`.

**에러 응답**: 400(shopCode 누락 / orderNos 비어있음·100건 초과·형식 오류),
403(프로젝트·매장 권한 없음), 404(매장 없음).

**헤더**: `Waldlust-Project-ID` 필수 — 코어 인터셉터가 붙인다. 경로에 shopCode 가
없지만 `_AgentAuthStateProvider.currentStoreId` 가 세션 매장 ID 를 넘겨주므로
인증 헤더는 그대로 붙는다([appfit_providers.dart:47](../lib/services/appfit/appfit_providers.dart#L47)).
`bulk-done` 이 이미 같은 방식으로 동작 중이라 추가 조치는 없다.

### 기존 `bulk-done` 과의 관계 — 혼동 주의

`PUT /v0/orders/bulk-done` 은 **그대로 남아 있고 여전히 기간 방식**이다
(`BulkUpdateStatusToDoneRequest` = `{shopCode, from, to}`, READY → DONE 만).
앱의 '전체 완료' 버튼이 이걸 쓴다
([order_provider.dart:1386](../lib/providers/order/order_provider.dart#L1386)).
DTO 가 분리됐으므로(`ForceBulkDoneOrdersRequest` 신설) **두 경로를 섞지 말 것** —
force 경로에 `from`/`to` 를 보내면 무시되고, `bulk-done` 에 `orderNos` 를 보내도
무시된 채 기간 전체가 완료된다.

> 재구현 전 이력: 초기 `force/bulk-done`(operationId `forceBulkUpdateOrderStatus`)은
> `bulk-done` 과 DTO 를 공유해 기간 단위였고, 단건 지정이 불가능했다. 그 판을 주문
> 카드 버튼에 걸면 매장 전체 주문이 함께 완료되는 사고 경로였다. 지금은 해소됐다.

### live/japanLive 배포 여부는 swagger 로 판정 불가

live(core-api)·japanLive(core-jpapi) 는 swagger 문서를 내려주지 않는다
(order 그룹 `paths` 0건, 전체 API 는 500). "live 에 없다"는 결론을 여기서
끌어내면 안 된다 — 실제로 `bulk-done` 은 live 에 있고 앱이 운영에서 쓰고 있다.
배포 여부는 서버팀에 직접 물을 것.

## 3. 서버팀에 남은 확인 항목

경로·필드·응답은 확정됐다. 아래 3개만 남았다.

1. **WebSocket 이벤트** — 푸시가 아니라 **에이전트로 가는 소켓 이벤트가
   `ORDER_DONE` 1건만인지, 건너뛴 `ORDER_PICKUP_REQUESTED` 도 함께 나가는지.**
   앱은 자가 PUT 의 echo 를 `SocketEventSuppressor` 로 억제하는데 억제 등록을 어느
   타입에 걸지가 이 답에 달렸다. 확답 전에는 **두 타입 모두 억제**하는 쪽으로 간다
   (과억제는 TTL 10초 뒤 풀리지만, 미억제는 유령 상태 되돌림을 만든다).
   - 참고: 재구현 전 판 description 에 있던 "건너뛴 중간 상태의 주문 이력은 순서대로
     모두 기록되며, **푸시 알림은 완료 1회만 발송된다**" 문장이 현재 판에서는
     빠져 있다. 문서 간소화인지 동작 변경인지 확인 필요.
2. **대상 외 주문의 결과 표현** — NEW·미결제(PENDING)·CANCELLED 주문번호를 넣으면
   `results` 에 `success:false` + `INVALID_ORDER_STATUS` 로 오는지. (앱은 PREPARING
   카드에서만 호출하므로 정상 경로에선 안 걸리지만, 소켓 지연으로 상태가 어긋난
   순간의 동작을 알아야 에러 문구를 정할 수 있다.)
3. **live / japanLive 배포 일정.**

## 4. 앱 구현

전부 구현됐다. 아래는 무엇이 어디에 있고 **왜 그렇게 했는지**의 기록이다.

### 4.1 appfit_core 라우트 — v1.5.0 (완료)

`ApiRoutes` 는 별도 레포다
([api_routes.dart](../../appifit_agent_core/appfit_core/lib/src/http/api_routes.dart)).
`ApiRoutes.forceBulkOrdersDone` 을 추가하고 `tool/release.sh` 로 v1.5.0 을 릴리즈,
앱 `pubspec.yaml` 의 `ref` 를 `v1.4.0` → `v1.5.0` 으로 범프했다.
**직접 `git tag`/`push` 금지 — release.sh 단일 진입점.**

두 상수를 헷갈리는 회귀는 컴파일로 안 잡히므로 core 쪽에 경로 고정 테스트를 뒀다
(`test/api_routes_test.dart` 의 "ApiRoutes 주문 일괄 완료" 그룹).

### 4.2 응답 모델 — [force_bulk_done_model.dart](../lib/models/force_bulk_done_model.dart)

수동 작성(freezed 금지). `ForceBulkDoneResult` / `ForceBulkDoneResponse`.

핵심은 `isSuccessFor(orderNo)` 다. 세 가지를 한 곳에서 처리한다:
- 인덱스가 아니라 **`orderNo` 로 찾는다** — 중복 제거로 `results` 길이가 요청 배열과
  어긋날 수 있다.
- 요청한 주문이 `results` 에 **없으면 실패로 본다** — 서버가 그 주문을 안 건드렸다는 뜻이다.
- `updateSuccessCount` 는 판정에 쓰지 않는다. 카운터는 "대상에서 빠짐" 과 "처리 실패" 를
  구분하지 못한다.

기존 `bulkCompleteOrders` 는 `Map<String, dynamic>` 을 그대로 돌려주는 채로 뒀다.
신규 경로만 모델로 올렸다.

### 4.3 API — `ApiService.forceCompleteOrders`

[api_service.dart](../lib/services/api_service.dart) 의 `bulkCompleteOrders` 바로 옆.
관례 4종(`_maybeInjectFault` / `_recordApiSuccess` / `_recordApiFailure` /
`_logApiFailure`)을 모두 따른다 — 빠뜨리면 건강도 배너와 장애 진단 로그에서 이 요청만
사라진다.

- `NetFaultTarget` 은 기존 `orderUpdate` 를 재사용한다. 같은 부류의 사용자 액션이고,
  전용 타깃을 새로 파면 fault-injection 리본까지 건드려야 한다. 강제완료만 따로
  죽여보고 싶어지면 그때 분리한다.
- `orderNos` 가 비어 있어도 조기 반환하지 않는다. 빈 배열이 흘러온 것 자체가 호출부
  버그라, 조용히 성공처럼 끝내는 것보다 400 예외로 드러나는 편이 낫다.
- 100건 초과 분할은 넣지 않았다(단건 호출).

### 4.4 Provider — `Order.forceCompleteOrder`

[order_provider.dart](../lib/providers/order/order_provider.dart). 흐름:

```
1. in-flight 락 tryAcquire(orderId)          — updateOrderStatus 와 같은 키 공간.
                                                픽업요청·강제완료 동시 발사를 막고
                                                버튼 스피너도 이 키를 본다
2. SocketEventSuppressor().add(orderId, …)   — ORDER_DONE + ORDER_PICKUP_REQUESTED
                                                (§3-1 확답 전까지 둘 다)
3. API 호출 → response.isSuccessFor(orderId) 로 판정
4. 성공: _applySuccessfulStatusTransition(...)
5. 실패/예외: 억제 discard  /  finally: release(orderId)
```

성공 후처리는 `_applySuccessfulStatusTransition` 으로 **뽑아내 `updateOrderStatus` 와
공유**한다. 그 5단계(RecentRemovals 마킹 → 큐 → 캐시 → 즉시 UI → 사운드그래프)와
순서가 불변식인데, 두 경로가 각자 복사본을 들면 한쪽만 고쳐져 서서히 어긋난다 —
특히 `_recentRemovals.mark` 를 빠뜨린 쪽은 폴링 stale 응답에 완료 주문이 되살아난다.

`updateOrderStatus` 자체를 분기시키지는 않았다. 그쪽은 자동접수 경로가 물려 있어
시그니처·분기를 건드리면 사거리가 넓다.

이미 DONE 인 주문은 요청을 아낀다. 서버 API 는 멱등이라 안전성 목적이 아니라 왕복
절약 목적이다. 사운드그래프 전송은 `PREPARING` 일 때만 도는데 강제완료는 DONE 이라
타지 않는다 — 정상이다.

### 4.5 UI — `lib/widgets/order/order_detail_popup.dart`

`_updateOrderStatus` 안에서 갈랐다. 버튼 핸들러(`completeOrder`)가 아니라 여기서
가른 이유는, 성공 후 뒷정리(`updateOrderInList` 등)를 두 경로가 그대로 공유하기
위해서다.

- `order.status == PREPARING` → `forceCompleteOrder` (신규 경로)
- `order.status == READY` → 기존 `_updateOrderStatus(DONE)` 유지 (단건 PUT 이 더 가볍고,
  force 가 live 에 배포되기 전에도 동작한다)

버튼 자체는 이미 있으므로 **위젯 트리·i18n 키 추가는 불필요**하다
(`t.order_detail.btn_order_complete`, 확인 문구는 `dialog_complete_confirm_content` 재사용).

KDS 진행탭은 주문완료 버튼을 **의도적으로 숨기고** 있다
([:768](../lib/widgets/order/order_detail_popup.dart#L768)). 여기에 노출할지는
운영 정책 결정 사항 — 이번 범위에 넣지 않는다.

### 4.6 뒤따라 고쳐야 할 것

`api_service.dart` 의 `INVALID_ORDER_STATUS` 보강 매핑에서
`OrderStatus.PREPARING => '이미 수락된 주문입니다.'`
([:299](../lib/services/api_service.dart#L299))는 이 기능이 붙으면 도달 경로가
바뀐다. 강제완료가 PREPARING 을 처리하게 되면 이 문구가 남을 이유가 있는지
재검토할 것.

### 4.6 뒤따라 볼 것 (미착수)

`api_service.dart` 의 `INVALID_ORDER_STATUS` 보강 매핑에 있는
`OrderStatus.PREPARING => '이미 수락된 주문입니다.'` 는 이제 상세창 '주문 완료'
경로로는 도달하지 않는다(강제완료가 처리하므로). 다른 도달 경로가 남아 있는지
확인하고, 없으면 정리 대상이다. **이번 변경에서는 건드리지 않았다** — 도달 경로
조사 없이 지우면 다른 화면의 문구가 조용히 바뀐다.

### 4.7 테스트 (완료)

`test/providers/order_ingestion_characterization_test.dart` 그룹 **(g)** 7건.
`_FakeApiService` 에 `forceCompleteOrders` 스크립트(응답/게이트/예외)를 추가했다.

1. PREPARING → DONE, **`orderNos` 가 단건인지** (여기가 무너지면 매장 전체가 완료된다)
   + 단계별 PUT 을 타지 않는지
2. 완료 후 서버 stale 응답(PREPARING)에도 부활하지 않음 — RecentRemovals 계약
3. `results.success == false` → 200 이어도 상태 불변
4. 요청한 주문이 `results` 에 없으면 실패 (카운터는 일부러 성공으로 채워 둔 응답)
5. 이미 DONE 이면 요청을 아낌
6. in-flight 락 — 응답 대기 중 재요청은 `false`, API 는 1회
7. 예외 후 락 해제 — 순차 재시도는 통과

## 5. 리스크

| 리스크 | 대응 |
| --- | --- |
| `bulk-done`(기간) 과 `force/bulk-done`(주문번호) 경로 혼동 | DTO 가 다르다. 상수·메서드 이름을 분명히 가르고, 잘못 보낸 필드는 **에러 없이 무시**된다는 걸 기억할 것 |
| 건너뛴 READY 소켓 이벤트가 뒤늦게 도착 → 유령 상태 되돌림 | §3-1 확답 전까지 두 타입 다 억제 |
| 부분 실패를 성공으로 오독 | 단건이어도 `updateSuccessCount` 가 아니라 `results` 의 해당 `orderNo` 로 판정 |
| live/japanLive 미배포 상태에서 릴리즈 | 배포 순서를 서버 → 앱으로 고정. §3-3 확인 |

## 6. 검증

**완료** — `flutter analyze` errors 0(잔여 17건은 전부 기존 info/warning),
`flutter test` 581 통과. 단, `test/config/build_brand_scope_test.dart` 의
"스테이징 폴더가 installDirName 아래에 있다" 1건은 macOS 에서 항상 실패한다
(`UpdateConfig.stagingDir()` 가 `%LOCALAPPDATA%` 부재 시 시스템 임시 폴더로 폴백).
Windows 전용 단언이며 이 변경과 무관하다.

**대기 — staging 실기기 검증.** 배포 전에 반드시 돌 것:

1. PREPARING 주문 1건 강제완료 → 상세창 닫힘, 카드가 완료로 이동
2. 같은 시각 **다른 PREPARING 주문이 그대로 남아있는지** (전체 완료 사고 회귀 검출.
   초기 스펙 사고 경로가 실제로 있었으므로 이 확인은 생략하지 말 것)
3. 라벨·영수증이 추가로 출력되지 않는지 (접수 시 이미 출력됨)
4. 소켓 재연결 후 해당 주문이 되살아나지 않는지 (`_recentRemovals` TTL 120초 이후까지)
5. 같은 주문에 한 번 더 → 멱등(`success:true`) 확인
6. READY 주문의 '주문 완료' 는 여전히 단건 PUT 을 타는지 (경로 분기 확인)
