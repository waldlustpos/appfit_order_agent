---
name: project-order-payment-breakdown
description: "주문 상세 다이얼로그에 결제수단별 금액 표시 구현 — 서버가 이미 주던 payments[]/discounts[]/cashReceipts[]/reward 파싱 + 상세필드 유실 버그 수정. 실기기 검증 대기"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7f85b352-2639-46f6-9aa1-06960aab8bce
  modified: 2026-08-10T07:38:05.431Z
---

2026-08-10 구현 완료(미커밋). `/v1/orders/{orderNo}` 상세 응답의 결제수단별 금액을 주문 상세 팝업 **가운데 금액 카드**에 표시.

**핵심 발견 — 서버는 이미 다 주고 있었다.** Swagger(`core-stgapi.waldplatform.com/v3/api-docs/1. 외부 API - order`, DTO `OrderDetailV1Response`)에 `payments[]`가 **required** 필드로 있고 설명에 "결제 수단별 상세(신용카드·간편결제·현금·선물하기·선불카드), 현금영수증, 적립"이 명시돼 있었다. 앱은 상위 스칼라 `paymentMethod` 하나만 읽고 `payments[]`/`cashReceipts[]`/`reward`를 통째로 버렸고, `discounts[]`는 `discountType` 문자열만 뽑고 `discountAmount`를 버렸다. 서버 협의 없이 클라이언트만으로 완결됐다. (같은 교훈 반복: [[reference-shop-catalog-display-order]])

**최종 채택 범위는 `payments[]` + `discounts[]` 둘뿐.** `cashReceipts[]`/`reward`는 검토 후 불필요 판정 → 모델·파싱·i18n·테스트까지 전부 제거(서버는 계속 내려주므로 필요해지면 Swagger 보고 다시 붙이면 된다).

`paymentMethod` enum은 28종(앱은 15종만 라벨 매핑이었음, 복합결제 시 `MULTI`). `payments[].status`는 **스키마에 enum 미선언** → 미지 값은 정상 결제로 취급(fail-open). 반대로 하면 서버가 값을 늘렸을 때 멀쩡한 결제가 전부 취소선이 된다.

**함께 고친 실버그 — 상세 전용 필드 유실.** `order_provider`의 병합 4곳이 `order.copyWith(menus:…, isDetailLoaded: true, kdsOrderType:…)` 로, base가 목록/소켓 주문이라 **상세 전용 필드는 기본값으로 리셋되는데 `isDetailLoaded`만 true**가 됐다. 팝업은 `isDetailLoaded == true`면 재조회를 건너뛰고, 손상본이 `_orderDetailCache`에 덮어써진다. → "팝업 열어 확인 → 접수 → 다시 열면 결제수단이 사라짐". 기존 `discountTypes`도 이미 같은 증상이었다. `OrderModel.withDetailsFrom()` 한 메서드로 통일했으니 **상세 전용 필드를 추가할 땐 여기만 고치면 된다**.

**설계 결정**: `cardNo`는 파싱 시점에 마스킹(모델이 원본 PAN 미보유 — `toSunmiJson`→`jsonEncode`로 프린터 페이로드에 새어나감). 신규 모델에 `DateTime`/object 필드를 아예 안 만듦(non-primitive가 섞이면 영수증이 통째로 안 나옴, 테스트로 잠금). `discountTypes`는 필드→`discounts` 파생 getter로 강등.

**UI 는 최소로 확정(사용자 지시).** 결제수단 행은 `아이콘 · 수단명 ⋯ 금액` 한 줄뿐:
- **결제 상태(취소/실패/대기) 미표시** — 주문이 취소면 결제도 취소라는 전제가 성립하고 팝업 헤더의 주문 상태 배지와 중복. 취소선·배지·dim 전부 제거. `status`는 계속 파싱하되 상세 로그용으로만 보관(`isCancelled`/`isSettled` 등 파생 getter는 삭제).
- **카드 상세(카드사·카드번호·할부·잔액) 미표시** — 파싱은 유지, 렌더만 제거.
- **금액 0원 건은 행째 숨김** — 100% 쿠폰이면 `FREE 0원`이 오는데 그 사실은 할인 상세에 이미 있음. 건수 배지도 보이는 행 기준으로 다시 셈. 금액이 있는 FREE 건은 그대로 표시.
- **현금영수증·적립 줄 삭제**.
- 회수한 i18n 키: `pay_status_*` 3개, `installment_lump`, `installment_months`, `balance`, `cash_receipt*`, `reward_stamp*`.

최종 중앙 카드 = 주문금액 / 할인금액(+종류별 상세) / 결제금액 / 결제수단별 금액. 결제수단 행은 `아이콘 · 수단명 ⋯ 금액` 한 줄.

**남은 것**:
- **실기기 검증 대기** — 샘플 주문 873452469021424335. `_logOrderDetail`에 전 필드 계측 로그를 심어놨으니 팝업만 열면 파일 로그에 남는다. 확인할 것: `payments`가 실제로 오는지 / `status` 실제 문자열 / `installment` 일시불이 0인지 1인지 / `cardNo`가 이미 마스킹돼 오는지 / `totalStampCount` 의미(목표치 아니라 누적치로 가정해 `+3 (누적 10)`으로 표기 중).
- **서버 `paymentAmount` 채택 보류** — 상세는 `totalAmount-totalDiscount`로 재계산, 목록은 서버값 사용이라 불일치 가능. 생성자가 `exceptTaxPrice`/`taxPrice`를 여기서 파생하고 그 값이 **영수증 세액 줄에 인쇄**되므로, 위 로그로 두 값 차이를 먼저 계측한 뒤 판단. 로그에 비교 줄을 넣어놨다.
- 영수증(ESC/POS + Sunmi Java)에 결제수단 줄 추가는 범위 밖. payload에는 이미 실려 간다.

검증: `flutter analyze` 17건(기존 baseline 불변), `flutter test` 390건 통과(기존 352 + 신규 38). 신규 포맷 부채 0.
