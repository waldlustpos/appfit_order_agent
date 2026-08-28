# 일본향 Simple POS — 착수 전 기초 조사

> **문서 성격**: 신규 앱 착수 판단을 위한 사실 조사 보고서. 구현 계획서가 아니다.
> **조사 기준일**: 2026-08-28
> **조사 방법**: AppFit Core OpenAPI 스펙 전수 파싱(`core-stgapi`, 293 paths / 305 operations / 587 schemas) · 사내 4개 레포 실물 확인(`appfit_order_agent`, `appifit_agent_core`, `kiosk_v4`, `kiosk_v3_japan`) · Square 공식 개발자 문서 원문 인용 · 일본 소비세 제도 확인
> **검증 수준**: 1차 조사 후 전면 재검증을 거쳤다. 재검증에서 서술 3건이 정정되고 세제 개정 1건이 새로 발견됐다.

---

## 0. 프로젝트 전제

| 항목 | 결정 |
|---|---|
| 타겟 | 일본 현지 소형 요식업. 한국 풀기능 레거시 POS가 아닌 **판매 등록기** |
| 주력 단말 | **Sunmi D3 MINI** 등 소형 Android (Windows 2순위) |
| 플랫폼 | Flutter |
| 서버 | **AppFit 플랫폼 단독** |
| 결제 | **Square** (Terminal API 우선) |
| 앱 구성 | 신규 레포 + `appfit_core` 공유(태그 핀) |
| 1차 범위 | 판매 등록기 최소셋 (§11) |

### 배제 사항 — POS 서버 계열 전면 배제

기존 키오스크(`kiosk_v4` / `kiosk_v3_japan` / `kiosk_v4_japan`)는 설정과 메뉴를 `AppFit → POS 웹 어드민 → 기기(POS API)` 경로로 받는다. **Simple POS는 이 경로를 쓰지 않는다.**

- POS 웹 어드민 ❌
- POS 서버(비-AppFit) 연동 ❌
- POS CFG 체계 ❌

부족한 설정은 **AppFit에 신규 구현되는 것을 전제**로 설계한다(§3). 키오스크 레포는 **코드 이식 대상일 뿐 연동 대상이 아니다** — 이식할 때 `settingsProvider`(POS CFG) 의존을 AppFit 응답 또는 기기 로컬 설정으로 갈아끼우는 것이 필수 작업이다.

---

## 1. 결론 — 구현 가능성 판정

### 판정: 구현 가능. 신규 개발이 아니라 재조립에 가깝다.

서버와 클라이언트 양쪽의 핵심이 **이미 사내에 프로덕션으로 존재**한다.

| 층 | 이미 있는 것 |
|---|---|
| 서버 | 일본 소비세 기준 일 매출 마감(`sales-closing`), POS 출처 주문 등록(`WALD_POS`), 취식 추가금(`inShopPrice`), 일본 결제수단 enum(`FELICA_*`/`QR_PAYMENT`), 옵션 선택 규칙까지 내려주는 카탈로그, `appType=POS` 버전 관리 |
| 클라이언트 | Square Terminal 연동 일체(`kiosk_v3_japan`), Shift_JIS 영수증·領収書 출력, `POST /v1/orders` 완성 클라이언트(`kiosk_v4`), 결제성공/저장실패 재시도 큐, Sunmi 내장 프린터·캐시드로어·고객 LCD 제어(`appfit_order_agent`) |

남은 일의 성격은 **① 키오스크용으로 흩어진 조각을 POS 폼팩터로 재조립 ② POS CFG 의존을 AppFit/로컬로 치환 ③ 일본 세제 대응 설계**다.

### 실질 리스크 3가지

| # | 리스크 | 성격 |
|---|---|---|
| 1 | **2027-04 소비세 개정** (§7.1) | 앱·서버 동시 개수 필요. 법안 미성립이라 세부 미확정 |
| 2 | **품목별 세율 구분 부재** (§7.3) | 서버가 "포장=8%" 일괄 적용 → 포장 주류 오과세. 세무 리스크 |
| 3 | **POS 고유 영역** (§8) | 재사용 자산이 덮지 못하는 부분. 오프라인 완결 판매·영업일 마감·현금 관리·금액 계산 결정론·크래시 원자성이 실제 개발 난이도를 결정한다 |
| 4 | **설정 공백** (§3) | POS CFG 배제로 생긴 자리를 AppFit 신규 API 3종으로 메워야 함 |

Flutter 적합성·하드웨어 적합성·서버 적합성은 리스크 항목이 아니다. 이미 같은 조합(Flutter + Sunmi + AppFit)이 일본 매장에서 운영 중이다.

**"재조립"이라는 표현의 한계**: 서버 연동·결제·영수증·카탈로그는 실제로 재조립이 맞다. 그러나 **§8의 POS 고유 영역은 사내 어디에도 선례가 없는 신규 설계**다. 일정을 잡을 때 여기에 무게를 둬야 한다.

---

## 2. 서버 준비도 — AppFit Core API 실사

### 2.1 결정적 근거 — 서버가 이미 일본 세제를 계산한다

`GET /v1/shop/{shopCode}/sales-closing` (태그: **일 매출 마감 Ex API v1**) 설명 **원문**:

> Asia/Tokyo 영업일에 귀속되는 주문 승인과 취소를 운영 원장에서 직접 합산한다. 포함 소비세는 주문별로 **매장 취식 10%, 포장 8%**를 적용하고 **1엔 미만을 절사**한다.

| 요소 | 값 |
|---|---|
| 파라미터 | `Waldlust-Project-ID`(header), `shopCode`(path, **POS 매장 ID 가능**), `businessDate`(query, `YYYY-MM-DD`) |
| 응답 | `businessDate`, `bizNum`, `grossSalesAmount`, `netSalesAmount`, `grossTransactionCount`, `netTransactionCount`, `discountCount/Amount`, `cancellationCount/Amount` |
| 세금 | `taxes[]` = `taxType(STANDARD\|REDUCED)`, `taxRate`, `salesAmount`, `taxAmount` |
| 결제수단별 | `payments[]` = `paymentMethod`, `transactionCount`, `amount` |
| 채널별 | `salesChannels[]` = `salesChannel(APP\|KIOSK\|**POS**)`, `transactionCount`, `amount` |
| 오류 | 400(미래 영업일 등), 403(프로젝트/매장 권한), 404(매장 없음) |

일본 영업일·내세·경감세율·엔 절사·POS 판매채널이 **서버에 구현돼 있다.** 일마감 화면은 이 API 하나로 성립한다.

### 2.2 주문 등록 — `POST /v1/orders`

설명 원문: *"외부 시스템의 주문을 등록한다. 하나의 주문에 복수의 결제 수단(분할결제)을 지원하며, 금액 검증식(totalAmount/totalDiscount/paymentAmount) 불일치 시 400을 반환한다."*
v0 설명: *"키오스크 또는 외부 POS에서 결제 완료된 주문을 등록한다"* — **POS 등록기 모델과 정확히 일치**한다.

**요청 (`RegisterExternalOrderV1Request`)** — `*` 는 필수

| 필드 | 내용 |
|---|---|
| `shopCode*` | 발트 매장코드 또는 협력사(pos/kiosk) 매장코드 |
| `orderType*` | `IN_SHOP` \| `TAKE_OUT` |
| `orderSource*` | `WALD_APPFIT`·`WALD_CAMO`·**`WALD_POS`**·`WALD_KIOSK`·`OK_POS`·`EASY_POS`·`NICE_POS`·`NICE_KIOSK` |
| `totalAmount*` | 할인 전 총액 = Σ `(itemPrice + inShopPrice + Σ optionPrice×qty) × qty` |
| `totalDiscount*` | Σ 라인 할인 + Σ 주문 할인 |
| `paymentAmount*` | `totalAmount − totalDiscount` = Σ `payments[].amount` |
| `orderLines*` | `posId*`, `itemName*`, `itemPrice*`, **`inShopPrice`**(취식 가산액, 미전송 시 0), `qty*`, `options[]`(`posId*`/`optionName*`/`optionPrice*`/`qty*`), `discounts[]` |
| `payments[]` | 분할결제. `paymentAmount > 0`이면 1건 이상 필수, 전액 할인이면 생략 시 서버가 `FREE`로 파생 |
| `discounts[]` | 주문 단위 할인(라인 귀속 아닌 것). `discountType` = `COUPON`·`POINT`·`GIFT`·`PARTNER`·`MEMBERSHIP`·`EMPLOYEE`·`PRE_PAYMENT`·`SHOP` |
| `externalOrderNo` | 외부 시스템 주문번호 |
| `displayOrderNo` | 외부 기기 표시 번호 |
| `orderedAt` | 주문 일시 — *"오프라인 큐잉 재전송 시에도 원 주문 시각 전달"* |
| `userSearchNo` | 회원 조회번호(전화/바코드, AES-256-GCM 암호문) |
| `note`, `pickupTime`, `rewardId`, `cashReceipts[]` | |

**`payments[].paymentMethod` enum** (일본 관련 굵게):
`CREDIT_CARD`, `PREPAID_CARD`, `FREE`, `NAVER_PAY`, `KAKAO_PAY`, `TOSS_PAY`, `TOSS_PAY_DIRECT`, `APPLE_PAY`, `PAYCO`, `EASY_CARD`, `MOBILE_PAYMENT`, `KB_PAY`, `HANA_PAY`, `WOORI_PAY`, **`FELICA_TRANSPORTATION`**, **`FELICA_ID`**, **`FELICA_QUICPAY`**, **`QR_PAYMENT`**, `GIFT`, `CASH`, `APP_CARD`, `ZERO_PAY`, `KARROT_PAY`, `BANK_TRANSFER`, `LOCAL_CURRENCY`, `EASY_PAYMENT`, `MULTI`, `OTHER`

결제 1건의 부가 필드: `approvalNo`, `approvalDate`(`yyyyMMddHHmmss`, VAN 원문 포맷), `transactionId`, `instrumentNo`(마스킹 카드번호), `instrumentName`(카드사명), `installment`, `balance`, `vendor`, `resultCode/resultMsg`, `payDetail`(자유맵), `useId`(GIFT/PREPAID_CARD 필수)

**응답**: `orderNo`, `shopOrderNo`(일일 순번), `createdAt`
**409**: *"유일성 대상 외부사가 이미 등록된 externalOrderNo로 재요청 — `data.resourceNo`에 기존 내부 orderNo 반환"* → 오프라인 재전송 안전성의 근거. **단 `WALD_POS`가 유일성 대상인지는 확인 필요**(§10 Q4)

### 2.3 주문 취소 — `POST /v1/order/{orderNo}/cancel`

`CancelOrderV1Request` = `action*`, `reason*`(`SHOP_REQUEST`·`SHOP_CLOSED`·`CUSTOMER_REQUEST`·`SOLD_OUT`·`ORDER_SURGE`·`INGREDIENT_SHORTAGE`·`SYSTEM_ERROR`·`OTHER`), `message`, `payInfos*[]`

서버 설명: `payInfos[]`는 `vendorTxId`(등록 시 보낸 `transactionId`)로 결제건과 매칭하고, 없으면 `approvalNo`로 매칭한다. **미매칭 건은 기본값(`0000`/`SUCCESS`)으로 기록되므로 결제 건마다 전체 필드를 채워 보낼 것을 서버가 권고**한다.

### 2.4 카탈로그 — `GET /v0/shops/{shopCode}/categories/items`

카테고리 > 상품 > 옵션그룹 > 옵션 중첩. 전 계층 `displayOrder` 정렬.

| DTO | 필드 |
|---|---|
| `ShopItemCategoryDto` | `categoryId`, **`categoryPosId`**, `categoryName`, `categoryNameEn`, **`categoryNameJa`**, `displayOrder`, `items[]` |
| `ShopItemDto` | `shopItemId`, **`itemPosId`**, `itemName`, `itemNameEn`, **`itemNameJa`**, `salePrice`, `status`(`PENDING`/`ON_SALE`/`SOLD_OUT`/`DISCONTINUED`/`DELETED`), `imageUrls`, `thumbnailImageUrl`, `displayOrder`, `optionGroups[]` |
| `ShopOptionGroupDto` | `optionGroupId`, **`optionGroupPosId`**, `name`/`nameEn`/**`nameJa`**, `displayOrder`, **`uiButtonType`(`RADIO`\|`CHECKBOX`)**, `optionGroupType`(`DEFAULT`\|`PERSONAL`), **`minSelection`**, **`maxSelection`**, `options[]` |
| `ShopOptionDto` | `optionId`, **`optionPosId`**, `name`/`nameEn`/**`nameJa`**, `salePrice`, `status`, `displayOrder`, **`isDefault`**, **`isChangeable`**, **`maxQuantity`** |

**핵심 두 가지**
1. **`itemPosId`/`optionPosId` ↔ 주문 등록의 `posId` 왕복이 성립**한다. 별도 매핑 테이블이 필요 없다.
2. **옵션 선택 UI 규칙(라디오/체크박스, 최소·최대 선택 수, 기본값, 변경 가능 여부, 최대 수량)을 서버가 내려준다.** 옵션 화면 로직을 앱에 하드코딩할 필요가 없다.

**결함**: `ShopItemDto`에 **`inShopPrice`가 없다.** 취식 가산액을 이 API만으로는 알 수 없다 → §2.5로 우회.

### 2.5 증분 동기화 — `GET /v0/migration/*`

`items` / `categories` / `category-items` / `options` / `option-groups` / `option-groupings` / `deletion-history/*`

공통 파라미터: `type=MASTER|SHOP`(필수), `shopCode` 또는 `shopId`, `shopGroupId`, **`modifiedAfter`**(이 시각 이후 수정분만)
응답의 `id`는 **pos_id 값**이다.

`ItemMigrationResponse`: `type`, `id`, `name`/`nameEn`/`nameJa`, `salePrice`, **`inShopPrice`**(*"취식 시 salePrice에 더해지는 추가금 (추가금 미설정 시 null)"*), `status`, `rewardType`, `imageUrls`, `nutritionFacts`, `description`, `posCategoryId`, `shopGroupId`, `badges`, `editDate`

→ **§2.4의 `inShopPrice` 공백을 메우는 정식 경로이자, 삭제 이력까지 포함한 오프라인 캐시 갱신 수단**이다. POS의 카탈로그 동기화는 이 API 계열이 더 적합할 수 있다.

### 2.6 그 밖에 POS가 쓸 수 있는 것

| 용도 | 엔드포인트 | 비고 |
|---|---|---|
| 매장 정보 | `GET /v0/shop/{shopCode}` | `posShopId`로도 조회 가능. `shopContact`, `addrRoad/addrDetail`, `operatingStatus` |
| 매장 유형 | `ShopKindInfo` | **`diningOption{useHall, useTakeout}`**, **`useInShopPrice`** — 취식/포장 사용 여부가 매장 단위로 모델링돼 있음 |
| 영수증 헤더 | `OrderDetailV1Response` | **`bizNum`**, **`ownerName`**, **`shopAddress`** |
| 버전 관리 | `GET /api/v0/app-versions/check` | `osType=AOS\|WINDOW`, **`appType=POS`가 이미 enum에 있음** |
| 인증 | `POST /v0/auth/token/issue`, `GET /v0/project/info` | 전역 JWT Bearer |
| 기기 로그인 자격 | `ShopMigrationResponse` | **`pwContact`**(*"솔루션(**포스**/키오스크/에이전트) 기기 로그인 패스워드"*), `subLoginId` |
| 운영 상태 | `PUT /v0/shop/{shopCode}/operating-status`, 스케줄 API | |
| 2차 이후 | 스탬프/쿠폰/포인트 Ex API 일체, `POST /v0/device/call`(용지부족·직원호출) | |

### 2.7 서버 환경

| 환경 | Base URL |
|---|---|
| dev | `https://core-devapi.waldplatform.com` |
| staging | `https://core-stgapi.waldplatform.com` |
| live (KR) | `https://core-api.waldplatform.com` |
| **japanLive** | **`https://core-jpapi.waldplatform.com`** / `wss://notifier-jpapi.waldplatform.com` |

정본: `appfit_core/lib/src/config/appfit_config.dart`. **일본 라이브는 별도 도메인**이며 `appfit_core`가 이미 지원한다.

---

## 3. ⭐ 설정·데이터 소스 매핑 — AppFit 단일 의존

POS CFG 체계를 배제했으므로, 기존 키오스크가 POS 어드민에서 받던 항목을 전수 나열하고 각각 다음 셋 중 하나로 귀속시킨다.

- **① AppFit에 이미 있음** — 그대로 호출
- **② AppFit 신규 구현 요청** — 백엔드에 요청할 항목
- **③ 기기 로컬 설정** — 서버가 알 이유가 없는 것

| 필요 항목 | 귀속 | 근거 / 요청 내용 |
|---|---|---|
| 카테고리·상품·옵션 | ① | `/v0/shops/{shopCode}/categories/items` |
| 옵션 선택 규칙(라디오/체크, 최소·최대) | ① | 위 응답에 포함 (§2.4) |
| 다국어 상품명(ja/en) | ① | 위 응답에 포함 |
| 상품 취식 추가금 `inShopPrice` | ① (우회) | `/v0/migration/items`. **Ex 카탈로그에도 추가되면 왕복 1회로 단순화** (§10 Q5) |
| 취식/포장 사용 여부 | ① | `ShopKindInfo.diningOption`, `useInShopPrice` |
| 매장명·주소·연락처 | ① | `ReadShopExResponse` |
| 사업자번호 | ① 부분 | `OrderDetailV1Response.bizNum`, `ShopMigrationResponse.bizNum`(암호화) |
| 주문 채번(일일 순번) | ① | 등록 응답 `shopOrderNo`. 오프라인 구간만 로컬 `displayOrderNo` |
| 강제 업데이트 | ① | `app-versions/check` (`appType=POS`) |
| 영업 상태·오픈/마감 스케줄 | ① | 운영상태 / 스케줄 Ex API |
| **세율 테이블** (적용시작일 · 품목분류 · 주문유형) | ② **신규** | 2027-04 대응. **앱 하드코딩 금지** (§7.1) |
| **적격청구서 발행사업자 등록번호** (T+13자리) | ② **신규** | `bizNum` 확장 또는 신규 필드 |
| **매장별 결제단말 설정** (Square 액세스 토큰 · Location ID · 전자머니/QR 사용여부 / GMO A35 IP·포트) | ② **신규** (임시 ③) | 매장별 민감정보. AppFit 매장 설정 API가 정석. 없는 동안은 기기 로컬 입력 |
| 영수증 출력 여부 · 하단 문구 · 로고 | ② 또는 ③ | 원격 관리 필요성에 따라 결정 |
| 프린터/스캐너 종류 · 시리얼 포트 | ③ | 기기 고유 |
| 기기명 · 자동로그인 · 테스트 모드 | ③ | |
| 세션/경고 타임아웃, 그리드 수 등 UI | ③ 또는 코드 | Simple POS는 화면 타입 분기 자체가 불필요 |

### 결론

**AppFit에 신규로 필요한 것은 실질적으로 3가지다.**

1. **세율 테이블** — `(적용시작일, 품목분류, 주문유형) → 세율`
2. **적격청구서 발행사업자 등록번호**
3. **매장별 결제단말 설정**

나머지는 전부 기존 AppFit API 또는 기기 로컬로 덮인다. POS 서버를 배제해도 공백이 크지 않다는 것이 이번 조사의 실질 결론 중 하나다.

---

## 4. 재사용 자산 인벤토리

> 모두 **코드 이식** 대상이다. 런타임 연동 대상이 아니다.

| 출처 | 자산 | 이식 시 주의 |
|---|---|---|
| **kiosk_v3_japan** | `lib/features/square/provider/` — `repo_square_terminal.dart`(Devices·Terminal·Refund API 전체), `square_terminal_provider.dart`(폴링·PING·상태머신, 652줄), `m_square_checkout.dart`, `m_square_terminal.dart`(`SquarePaymentType`) | **토큰·Location ID를 `settingsProvider`(POS CFG)에서 읽는다 → §3 ②/③ 경로로 치환 필수** |
| | `lib/features/admin/widget/setting/w_square_terminal.dart` | 페어링 UI(6자리 코드) |
| | `w_square_payment_indicator.dart`, `w_square_refund_indicator.dart` | 결제·환불 진행 UI |
| | `lib/features/pay/utils/japan_payment_utils.dart` | 일본 결제수단 ↔ `SquarePaymentType` 매핑 |
| | `lib/service/print_services.dart` | **Shift_JIS 영수증 + 領収書(료슈쇼) 출력** (`charset_converter`, `isKorean ? "euc-kr" : "Shift_JIS"`) |
| **kiosk_v4** | `lib/features/pay/data/m_appfit_order.dart` | **`POST /v1/orders` 완성 클라이언트.** `inShopPrice`·`payments[]`·`cashReceipts`·`externalOrderNo`·`orderedAt` 전부 구현. **"할인은 라인에만 — top-level 중복 금지(서버가 합산 검증하므로 이중 계상되면 거절)"** 같은 실전 노하우가 주석으로 남아 있음 |
| | `appfit_save_strategy.dart` + `failed_order_retry_service.dart` | **결제 성공 후 서버 저장 실패 → 로컬 DB 마킹 + 백그라운드 재시도 큐.** POS 오프라인 내성의 핵심. `pos_save_strategy` 분기는 제거 |
| | `CartState`(할인 SSOT), 옵션 선택 UI, `payment_gateway.dart` 게이트웨이 추상화 | POS CFG 의존부 제거 |
| **appfit_order_agent** | `SunmiPrintHelper.java` — 내장 프린터, **`openCashBox()`**, 고객 LCD(`sendTextToLcd`/`sendBitmapToLcd`), QR·바코드, `getPrinterSerialNo` | 소형 POS 주변장치 요구를 그대로 충족 |
| | `output_queue_service` / `printer_job_queue` / `startup_probe_scheduler` | 출력 큐·backoff·재시도 |
| | `core/products/shop_catalog_parser.dart` | 카탈로그 응답 → 모델 순수 함수 |
| | `services/receipt_labels.dart` + slang ko/en/**ja** | 영수증 라벨 다국어. 이미 `領収書`·`消費税`·`様` 배포 중 |
| | Windows 데스크톱 골격(단일 인스턴스·트레이·자동시작·per-user 인스톨러) | 2순위 플랫폼용 |
| **appfit_core** | 토큰/AES-GCM, Dio 인터셉터(자동 인증 헤더+암호화), `ApiRoutes`, WebSocket notifier, OTA, Fleet, Sentry, `SerialAsyncQueue` | 태그 핀 의존. 신규 라우트 추가는 `tool/release.sh` 단일 진입점 |

**미확보**: `kiosk_v4_japan`(별도 레포, 이 머신에 없음). Square 최신 구현이 v3 대비 얼마나 진화했는지 확인하려면 clone 필요.

---

## 5. 하드웨어 — Sunmi D3 MINI

| 항목 | 값 |
|---|---|
| 메인 디스플레이 | 10.1" IPS, 800×1280 HD, 10점 터치 |
| 고객 디스플레이 | **변형별로 다름** — 58mm 모델 = **2.4" 7세그먼트(숫자 전용, 비트맵 불가)** / 80mm 모델 = 4" WVGA IPS 터치 |
| OS | Android 13 (SUNMI OS). **GMS / NO-GMS 변형 존재** |
| SoC / 메모리 | Qualcomm 헥사코어 1.9 or 2.4GHz / 3GB RAM, 32GB ROM(UFS 2.2) |
| ABI | `arm64-v8a` (order_agent 실측: `zygote64_32`) |
| 프린터 | 내장 58 / 80 / 100mm. 58mm 100mm/s, 80mm 최대 250mm/s |
| 스캐너 | 1D/2D 내장 |
| 포트 | **"USB (type A, 3x), Bluetooth (BLE, class 5.0), Ethernet, Wi-Fi (802.11ac), drawer kickout (RJ11, RJ12), NFC"** |

**시사점**
- **캐시드로어 포트(RJ11/RJ12) 확인.** `SunmiPrintHelper.openCashBox()`가 이미 구현돼 있어 그대로 동작한다.
- 10.1"는 소형 POS UI에 충분하다. 키오스크급 대형 레이아웃이 아니라 밀도 높은 그리드가 적합하다.
- 내장 프린터·드로어·스캐너·NFC가 한 대에 통합 → **주변장치 추가 없이 1차 범위 완결 가능**.
- **고객 디스플레이 활용은 80mm 변형 전제.** 58mm 변형은 숫자만 표시 가능하므로 도입 기종 확정 전에는 고객 화면 기능을 필수로 잡지 않는다.
- **GMS 여부는 Square POS API 채택 시에만 문제**가 된다(Square POS 앱이 Google Play 배포). **Terminal API를 쓰면 무관하다.**

---

## 6. 결제 연동 — Square 일본

### 6.1 선택지

**전제: Mobile Payments SDK는 일본에서 쓸 수 없다.** Square 공식 문서 원문 — *"The Mobile Payments SDK is currently available for accounts based in the United States, Canada, the United Kingdom, and Australia."* 일본 개발 가이드에도 `Mobile Payments SDK — ❌ Not yet available`로 표기돼 있다. 따라서 **자체 앱 내부에 결제 UI를 넣는 방식은 불가능**하고, 선택지는 둘뿐이다.

| | **Terminal API** | **POS API (Android)** |
|---|---|---|
| 방식 | 클라우드 API → Square가 페어링된 단말로 전달 | 같은 기기에서 앱 간 인텐트 |
| 하드웨어 | **Square Terminal**(전용 단말, 자체 화면) | Square Reader / Stand 2세대 + **Square POS 앱 v4.64+** |
| 아이템화 | **지원** (`order_id`로 Orders API 연계) | **미지원** — 공식 문서: *"The Point-of-Sale API supports only custom amount-based transactions"* |
| 인증 | 액세스 토큰 (+ 사내 방식: 매장별 토큰 주입) | application ID + 패키지명 + SHA-1 (OAuth 불필요) |
| 결과 수신 | 웹훅 또는 폴링 | `onActivityResult()` |
| 기기 제약 | **없음** (D3 MINI에서 호출만) | D3 MINI가 **GMS 탑재 + Reader 페어링 가능**해야 함(미검증). Android 11+는 `<queries><package android:name="com.squareup" /></queries>` 필요, Java 전용 SDK |

### 6.2 권고: Terminal API

이유 세 가지 — ① **사내 프로덕션 선례가 그것이다**(`kiosk_v3_japan`) ② 아이템화 지원 ③ D3 MINI의 GMS·Reader 호환성 리스크를 통째로 회피한다.
대가는 카운터에 Square Terminal 1대 추가.

### 6.3 사내 구현 실측 (`kiosk_v3_japan/lib/features/square/provider/`)

```
Square-Version: 2025-10-16
Authorization: Bearer {매장별 액세스 토큰}
baseUrl = token.contains('sandbox')
        ? https://connect.squareupsandbox.com/v2
        : https://connect.squareup.com/v2
```

| 단계 | 호출 |
|---|---|
| 페어링 | `POST /v2/devices/codes` (`product_type: TERMINAL_API`, `location_id`, `name`, `idempotency_key`) → 6자리 코드 → 점원이 단말에 입력 → `GET /v2/devices/codes/{id}` **폴링**으로 `device_id` 확보 → 로컬 저장 |
| 단말 상태 | `GET /v2/devices/{deviceId}` / `POST /v2/terminals/actions` (`type: PING`) **5분 주기** |
| 결제 | `POST /v2/terminals/checkouts` → `GET /v2/terminals/checkouts/{id}` **1.5초 폴링** → `COMPLETED` / `CANCELED` / 자체 `TIMEOUT_CANCELED` |
| 결제 취소 | `POST /v2/terminals/checkouts/{id}/cancel` 후 폴링에서 `CANCELED` 대기 |
| 환불 | `POST /v2/refunds` (`idempotency_key`, `amount_money{JPY}`, `payment_id`, `reason`) → `GET /v2/refunds/{id}` 폴링. **`REFUND_AMOUNT_INVALID` 400 = 이미 환불된 건으로 간주** |
| 결제 조회 | `GET /v2/payments/{paymentId}` |

**웹훅을 쓰지 않는다 → 별도 백엔드 컴포넌트가 필요 없다.** Square 문서는 프로덕션에서 웹훅을 권장하지만, 점원이 대기하는 대면 결제에서는 폴링이 실용적이며 사내에서 검증됐다.

### 6.4 `TerminalCheckout` 주요 필드

| 필드 | 내용 |
|---|---|
| `amount_money*` | 세 포함 징수 금액 |
| `device_options*` | `device_id*`, `skip_receipt_screen`, `collect_signature`, `tip_settings`, `show_itemized_cart` |
| `payment_type` | 기본 `CARD_PRESENT`. 일본: `FELICA_ALL`, `FELICA_ID`, `FELICA_QUICPAY`, `FELICA_TRANSPORTATION_GROUP`, `QR_CODE` |
| `order_id` | Square Order 참조(아이템화) |
| `reference_id` | 최대 40자 — **`externalOrderNo`를 심어 AppFit↔Square 상관키로 쓸 수 있다** |
| `deadline_duration` | **Deprecated.** 기본·최대 5분 |
| `status` | `PENDING` / `IN_PROGRESS` / `CANCEL_REQUESTED` / `CANCELED` / `COMPLETED` |
| `payment_ids`, `cancel_reason`, `app_fee_money`, `tip_money` | |

### 6.5 결제수단 enum 대응

AppFit 서버 enum과 Square Terminal API가 거의 1:1로 맞는다. 사내에 매핑 유틸(`japan_payment_utils.dart`)도 이미 있다.

| Square Terminal API | AppFit `paymentMethod` | 사내 `SquarePaymentType` |
|---|---|---|
| `FELICA_TRANSPORTATION_GROUP` | `FELICA_TRANSPORTATION` | `felicaTransportationGroup` |
| `FELICA_ID` | `FELICA_ID` | `felicaId` |
| `FELICA_QUICPAY` | `FELICA_QUICPAY` | `felicaQuicpay` |
| `QR_CODE` | `QR_PAYMENT` | `qrCode` |
| `CARD_PRESENT` | `CREDIT_CARD` | `cardPresent` |
| `FELICA_ALL`(단말에서 브랜드 선택) | — | 결과 브랜드로 매핑 필요 |

### 6.6 일본 특유 제약 — 설계에 반영해야 할 것

| 제약 | 근거 / 영향 |
|---|---|
| **交通系IC(Suica/PASMO) 환불 불가** | 원문: *"If a buyer uses a PASMO or SUICA transportation card for a payment, you encounter a `REFUND_DECLINED` error"* → **취소 정책이 결제수단별로 갈려야 한다.** UI에서 사전 안내 필요 |
| e-money·QR **가맹점별 사전 승인 필요** | 원문: *"The Square account location must be signed up for e-money in the Square Dashboard"* / QR은 *"The seller must be approved to accept QR code payments in Japan"* |
| 단말 펌웨어 요건 | FeliCa **4.11+**, QR **6.58+**. 단말이 일본에서 활성화돼 있어야 함 |
| e-money 오류 후 취소 불가 | *"Using CancelTerminalCheckout to cancel an e-money payment after getting an error on the Square Terminal is currently not supported"* → 구매자가 단말에서 직접 취소 |
| 에러 메시지 영어 고정 | 일본어 번역은 우리 몫 |
| **현금 미지원** | 현금 계산·거스름돈·시재는 우리 POS가 전담 |
| **오프라인 불가** | Terminal API는 온라인 필수. 주문 등록은 큐잉 가능하지만 결제는 아니다 |
| **領収書(정식 영수증) 미지원** | *"Formal receipts are not currently supported - only normal receipts can be printed"* → **적격간이청구서·領収書 발행은 우리 POS의 책임**(§7.2). `kiosk_v3_japan`에 구현체 있음 |
| 통화 | JPY 전용, 프로덕션 최소 1엔 |

### 6.7 대안 — GMO A35

사내 키오스크 설정에는 결제단말로 `GMO` / `SQUARE` 택일 항목과 **GMO A35 IP·포트(TCP 연동)**가 존재한다. Square 외 선택지가 이미 검토돼 있다는 뜻이며, 매장 여건(기존 계약·수수료)에 따라 비교 대상이 된다. 설정 주입 경로는 §3 ② 로 동일하다.

---

## 7. 일본 법규·세무

### 7.1 🔴 최우선 — 2027년 4월 소비세 개정

**2026-08-05 임시 각의에서 음식료품 소비세율을 2027-04-01부터 2년간(2029-03 말까지) 8% → 1%로 인하하는 방침이 결정됐다.**

| 항목 | 내용 |
|---|---|
| 대상 | 현행 경감세율과 동일 — **"주류와 외식을 제외한 식료품"** |
| 세율 | 대상 식료품 **1%** / 주류 **10%(유지)** / 외식·점내취식 **10%(유지)** / 그 외 표준 **10%** |
| 기간 | 2027-04-01 ~ 2029-03-31 (2년 한시) |
| **법적 상태** | **법안 미성립.** 가을 임시국회 통과가 전제 (2026-08-28 기준) |

**설계에 미치는 영향**

1. **1%로 정한 공식 이유가 "0%보다 사업자의 시스템 개수 기간을 단축할 수 있어서"다.** 제도 자체가 POS 개수를 전제하고 있다.
2. **취식/포장 세율차가 2%p → 9%p로 확대된다**(10% vs 1%). 주문유형 오선택의 금전 파급이 4.5배가 된다. → **취식/포장 선택 UI를 놓칠 수 없게 만들고, 결제 전 마지막 확인과 사후 정정 경로를 반드시 둔다.**
3. **세율을 상수로 박으면 안 된다.** `(적용시작일, 품목분류, 주문유형) → 세율` 테이블로 설계하고 **1% / 8% / 10% 3세율 병존**과 **구세율 영수증 재발행**을 처음부터 수용한다.
4. **서버도 개수 대상이다.** `sales-closing`이 "취식 10 / 포장 8"을 고정 규칙으로 계산한다(§2.1) → §10 Q1.

> ⚠️ 이 절은 **각의결정 단계**의 정보다. 국회 통과 시 대상 품목 세목·경과조치가 확정되므로 **이 문서의 갱신 대상**이다.

### 7.2 인보이스 제도 — 영수증 기재 요건

소매·음식점업 등 불특정 다수를 상대하는 업종은 적격청구서 대신 **적격간이청구서(適格簡易請求書)** 발행이 허용된다. 레시트 필수 기재사항 5가지(국세청 인보이스 Q&A 문58):

1. 적격청구서 발행사업자의 **성명 또는 명칭 및 등록번호**(T+13자리)
2. 거래 연월일
3. 거래 내용 — **경감세율 대상 품목인 취지**(※ 등 기호 + 범례)
4. **세율별로 구분 합계한 대가액**(세포함 또는 세별)
5. **세율별 소비세액 등 또는 적용세율** — 간이청구서는 **둘 중 하나만** 기재해도 무방

적격청구서와의 차이: 교부받는 사업자의 성명·명칭 기재가 **불필요**.

**대응**: ①의 등록번호를 담을 곳이 AppFit에 없다(§3 ②). ③·④·⑤는 세율 테이블(§7.1)이 있어야 성립한다. Square는 정식 영수증을 발행하지 못하므로(§6.6) **우리 POS가 발행 주체**다.

### 7.3 경감세율 범위 — 서버 규칙과의 갭

경감세율 8%(→2027-04부터 1%) 대상은 **"주류·외식·케이터링을 제외한 음식료품"**이다.

**→ 포장이어도 주류는 10%다.** 그런데 서버 `sales-closing`은 **주문유형만 보고 "포장 = 8%"를 일괄 적용**한다. 주류를 취급하는 매장에서는 **구조적으로 세액이 틀린다.** 상품 단위 세율 구분이 서버·앱 양쪽에 필요하다 → §10 Q2.

### 7.4 그 밖

| 항목 | 내용 |
|---|---|
| 총액표시 의무 | 소비자 대상 가격은 세포함(内税) 표시. 서버가 내세 기준으로 계산하므로 정합 |
| 領収書 | 요청 시 宛名·但し書き 대응 필요. `kiosk_v3_japan`에 출력 구현 있음 |
| 인지세 | 현금 5만엔 이상 영수증은 인지세 대상 |
| 전자장부보존법 | 전자 거래기록 보존 주체가 AppFit 서버 원장인지 확인 필요 |

---

## 8. POS 고유 기술 설계 영역 — 기존 자산에 없는 것

§4의 재사용 자산으로 덮이지 않는, **POS이기 때문에 새로 설계해야 하는 영역**을 정리한다. 이 절이 1차 개발의 실제 난이도를 결정한다.

### 8.1 뿌리 — 권위(authority) 모델이 다르다

| | 원장(source of truth) | 로컬 저장소 | 오프라인이면 |
|---|---|---|---|
| `appfit_order_agent` | **서버** | **없음** (SharedPreferences만) | 주문을 못 본다 (뷰어이므로 무해) |
| `kiosk_v4` / `kiosk_v3_japan` | **서버** | sqflite — 메뉴 캐시 + 거래 스냅샷 + 재시도 큐 | **판매 자체가 불가** (결제가 온라인 필수) |
| **Simple POS** | **서버 (최종) + 로컬 (일시)** | **필수** | **현금 판매는 정상 완결된다** |

**현금 결제는 네트워크 없이도 판매가 끝난다.** 그 순간 로컬 DB는 캐시가 아니라 **그 거래의 유일한 원장**이 되고, 나중에 서버로 수렴시켜야 한다. 기존 두 앱은 이 상태를 가진 적이 없다. 아래 항목 대부분이 여기서 파생된다.

다행히 서버가 이 모델을 이미 전제하고 있다 — `orderedAt`("오프라인 큐잉 재전송 시에도 원 주문 시각 전달")과 `externalOrderNo`(409 재전송)가 그 근거다(§2.2).

### 8.2 로컬 데이터 모델

**이미 있는 것** (`kiosk_v4/lib/service/sql_db/`, 이식 가능)

| 테이블 | 용도 |
|---|---|
| `foundation_sync(foundation_type, last_updated_at)` | 마스터 동기화 시각 → `modifiedAfter` 증분 호출의 커서 |
| `master_raw_data` / `master_raw_chunks` | 메뉴 원장 로컬 캐시(대용량 JSON 청크 분할) |
| `orders` | 거래 스냅샷 이력(JSON 덩어리) |
| `failed_orders(retryCount, lastError, lastRetryAt, actionType)` | 서버 저장 실패 재시도 큐 |
| `pending_payments` | 결제 승인 ↔ 주문 저장 사이의 고아 결제. **정의만 있고 호출부가 없다(사문화)** — POS에서는 실제로 구현해야 한다(§8.6) |

**새로 필요한 것**

| 저장소 | 왜 필요한가 |
|---|---|
| **영업일(business day) 상태** | 개시/마감 시각, 마감 확정 여부. §8.3 |
| **현금 원장** | 준비금·입금·출금·판매현금·환불현금·실사금액·과부족. §8.4 |
| **드로어 개폐 이력** | 판매 외 개폐(거스름돈 보충, 오조작)를 남겨야 과부족 원인을 추적할 수 있다 |
| **세율 스냅샷** | 거래 시점의 적용 세율·세액. 마스터가 바뀌어도 과거 거래와 재발행 영수증이 흔들리면 안 된다. §8.5 |
| **영수증 발행 이력** | 재발행 횟수, 領収書 발행(宛名·但し書き) 기록. §8.8 |
| **정정 링크** | 취소/반품이 원거래를 가리키는 관계. §8.7 |
| **담당자 이벤트** | 누가 판매·취소·출금했는가. §8.9 |

**거래 이력을 JSON 한 덩어리로 두면 안 된다.** kiosk는 "무슨 일이 있었나" 스냅샷이면 충분했지만, POS는 **일마감 집계·세율별 합계·결제수단별 합계·미전송 조회**를 로컬에서 해야 하므로 최소한 `거래 / 거래라인 / 결제 / 세금` 은 조회 가능한 컬럼으로 정규화해야 한다.

**보존 정책**도 새로 필요하다. 서버가 최종 원장이므로 로컬은 N일(예: 90일) 보관 후 정리하되, **미전송 건은 전송 성공 전까지 절대 삭제 금지**다.

### 8.3 영업일(business day)과 마감

- 심야 영업 매장은 달력 날짜와 영업일이 어긋난다(예: 새벽 2시까지 = 전일 매출). **영업일 경계 시각**이 설정 항목으로 필요하다.
- 서버 `sales-closing`은 `businessDate`(Asia/Tokyo)로 조회하므로, **앱의 영업일 판정이 서버와 같아야** 숫자가 맞는다.
- **일마감의 함정**: `sales-closing`은 **서버 원장 기준** 집계다. 로컬에 미전송 건이 남아 있으면 **일마감 금액이 실제 판매와 다르다.**
  → **마감 화면은 "미전송 N건"을 반드시 표시하고, 미전송이 0이어야 마감을 확정할 수 있게 한다.** 이것이 오프라인 완결 판매를 허용한 대가다.
- 마감 후 판매가 들어오면 어느 영업일에 귀속시킬지 규칙이 필요하다(서버는 `orderedAt` 기준으로 귀속하므로 앱도 동일하게).

### 8.4 현금 관리 — 완전 신규

기존 두 앱은 **현금을 다룬 적이 없다**(키오스크는 캐시리스, 에이전트는 결제를 안 한다). 필요한 것:

- 개점 준비금(釣銭準備金) 등록
- 판매 시 받은 금액 입력 → **거스름돈 계산 및 표시** (일본 현금 비중을 고려하면 이 UI가 1차의 핵심 동선)
- 입금(入金) / 출금(出金) 기록 — 은행 입금, 경비 지출
- 마감 시 **현금 실사** 입력 → **과부족(過不足) 산출**
- **드로어 개폐**: `SunmiPrintHelper.openCashBox()`가 이미 있으나(§4), *언제 여는가*의 정책이 새로 필요하다 — 현금 거래 시 자동, 그 외 수동 + 사유 기록
- 이 모든 것은 **AppFit에 대응 API가 없다**. 로컬 전용으로 두고 일마감 화면에서 서버 집계와 대조하는 것이 1차의 현실적 선택이다.

### 8.5 금액·세액 계산의 결정론

**서버 검증식이 1엔이라도 어긋나면 400이다** — `totalAmount − totalDiscount = paymentAmount = Σ payments[].amount`(§2.2). 따라서 계산 규칙을 서버와 정확히 맞춰야 한다.

| 쟁점 | 내용 |
|---|---|
| **절사 단위** | 서버는 *"1엔 미만을 **주문별**로 절사"*한다고 명시(§2.1). **앱이 라인별로 절사하면 합계가 갈린다.** 반드시 주문 단위로 맞춘다 |
| **할인 안분** | 주문 단위 할인을 라인에 안분할 때 나머지 1엔을 어디에 붙일지 규칙이 필요. 서버는 라인 할인과 주문 할인을 합산 검증하고, kiosk는 *"할인은 라인에만 — top-level 중복 금지"* 라는 규칙을 이미 따르고 있다(§4) |
| **세액을 누가 계산하나** | ⚠️ **주문 등록 요청에 세금 필드가 없다.** 서버가 `orderType`으로 세율을 스스로 정한다. 반면 **적격간이청구서 요건상 세율별 세액을 영수증에 인쇄하는 것은 앱**이다(§7.2). → **앱이 인쇄한 세액과 서버 일마감 세액이 갈릴 수 있다.** 특히 주류(§7.3). 계산 규칙 합의가 필요하다 → §10 Q10 |
| **세율 스냅샷** | 가격(`itemPrice`/`inShopPrice`)은 요청에 실어 보내므로 거래 시점에 고정된다. 그러나 **세율은 서버가 수신 시점 규칙으로 계산**한다 → **오프라인 큐가 2027-04-01을 넘겨 전송되면 세율이 바뀔 수 있다** → §10 Q11 |
| **3세율 병존** | 1% / 8% / 10%가 한 영수증에 공존할 수 있다(§7.1). 세율별 소계 구조를 처음부터 만든다 |

### 8.6 원자성과 크래시 복구

POS 1건의 판매는 **3단계**를 거치는데, 어느 사이에서 죽어도 돈이 사라지면 안 된다.

```
① Square 결제 승인   ② 로컬 원장 기록   ③ AppFit 서버 등록
```

| 죽은 지점 | 결과 | 필요한 복구 |
|---|---|---|
| ① 직후 | **돈은 받았는데 판매 기록이 없다** — 최악 | 기동 시 Square `GET /v2/terminals/checkouts/{id}` 또는 `GET /v2/payments/{id}`로 미결 체크아웃 회수. **먼저 로컬에 "결제 시도 중" 레코드를 남기고 Square를 호출**해야 회수할 단서가 남는다 |
| ② 직후 | 로컬엔 있고 서버엔 없다 | 재시도 큐(`failed_orders`, 이식 자산) |
| ③ 도중 | 서버 등록 여부 불명 | `externalOrderNo` 재전송 → 409면 이미 등록됨으로 확정(§2.2, **단 §10 Q4 확인 필요**) |

kiosk의 `pending_payments` 테이블이 정확히 ①의 자리인데 **호출부가 없다.** POS에서는 반드시 실제로 동작해야 한다.

전원 차단이 잦은 매장 환경이므로 **로컬 쓰기는 트랜잭션으로 묶고, "결제 시도 중" 레코드는 Square 호출 이전에 커밋**한다.

### 8.7 거래 생애주기와 정정

POS는 판매 후에 손대는 일이 많다. 기존 두 앱에는 없는 개념들:

- **당일 취소 vs 전일 취소(반품)** — 전일 건은 이미 마감된 영업일에 속하므로 당일 매출에 마이너스로 잡을지, 원 영업일을 정정할지 규칙이 필요
- **부분 취소** — 서버 `payInfos[]`는 결제 건별 매칭을 지원하지만(§2.3), 라인 단위 부분 취소를 어떻게 표현할지 확인 필요
- **환불 불가 수단** — **交通系IC는 Square가 환불을 거부한다**(`REFUND_DECLINED`, §6.6). 실무는 **현금으로 대신 환불**하는데, 이것을 서버에 어떻게 기록할지 정해야 한다 → §10 Q12
- **정정은 삭제가 아니다** — 세법·전자장부보존법 관점에서 원거래를 지우면 안 되고 **취소 거래를 추가**해야 한다. 로컬 스키마가 이 관계를 표현해야 한다(§8.2 정정 링크)

### 8.8 영수증 발행

- **채번**: 서버 `shopOrderNo`는 등록 **응답**으로 온다 → 오프라인에는 없다. **영수증에 찍을 번호를 로컬에서 먼저 채번**하고(`displayOrderNo`), 나중에 서버 번호와 대응시켜야 한다. kiosk의 로컬 채번(`start_number_pos`/`order_number_pos`)이 출발점
- **재발행** — 횟수 이력 필요. 재발행본에는 재발행 표기
- **領収書(료슈쇼)** — 宛名·但し書き 입력 UI + 발행 이력. 5만엔 이상 인지세 안내(§7.4). 출력 구현체는 `kiosk_v3_japan`에 있다(§4)
- **적격간이청구서 5요건**을 레이아웃에 고정(§7.2). 등록번호는 §3 ② 경로로 주입

### 8.9 담당자·권한

- 기존 두 앱은 **단일 로그인, 담당자 개념 없음**. POS는 최소한 **누가 팔았고 누가 취소·출금했는지**를 남겨야 현금 과부족을 추적할 수 있다
- 취소·출금·마감 같은 행위에 **관리자 승인(PIN)** 을 걸지 여부는 매장 규모에 따라 결정. 1차에서는 "담당자 식별 + 이벤트 기록"까지만 해도 충분할 수 있다

### 8.10 시각 신뢰

**영업일 판정과 세율 적용일이 모두 기기 시각에 의존한다.** 2027-04-01 세율 전환이 기기 시각으로 갈리면 사고가 난다.

- Sunmi 단말의 시각 드리프트, 점원의 수동 변경 가능성을 전제한다
- 서버 응답 시각과 기기 시각의 차이를 감시하고, 임계 초과 시 경고 또는 판매 차단
- `appfit_order_agent`에 `windows_timezone_service.dart`가 있으나 Windows 전용이라 Android용은 새로 필요

### 8.11 하드웨어 장애 시 판매 지속 정책

- **프린터 용지 소진 / 커버 열림 상태에서 판매를 계속할 것인가.** 결제는 이미 승인됐는데 영수증만 못 나오는 상황이 실제로 발생한다 → 판매는 성립시키고 **영수증을 미출력 큐에 넣어 복구 후 재출력**하는 것이 기존 `output_queue_service`(§4)의 사고방식과 일치
- 드로어가 안 열릴 때의 대체 동선
- Square Terminal 연결 끊김 시 현금 결제로 폴백하는 동선

### 8.12 신규 설계 항목 체크리스트

| # | 항목 | 기존 자산 | 신규 난이도 |
|---|---|---|---|
| 1 | 오프라인 완결 판매 + 수렴 | 재시도 큐만 있음 | **높음** |
| 2 | 로컬 원장 정규화 스키마 | JSON 스냅샷뿐 | 중 |
| 3 | 영업일·마감 + 미전송 게이트 | 없음 | **높음** |
| 4 | 현금 관리(준비금·거스름돈·과부족) | 없음 | 중 |
| 5 | 금액·세액 결정론(절사·안분·3세율) | 없음 | **높음** |
| 6 | 3단계 원자성·크래시 복구 | `pending_payments` 껍데기 | **높음** |
| 7 | 취소/반품/부분환불·정정 링크 | 단순 취소만 | 중 |
| 8 | 로컬 채번 + 서버번호 대응 | kiosk 로컬 채번 | 낮음 |
| 9 | 영수증 재발행·領収書 이력 | 출력 구현은 있음 | 낮음 |
| 10 | 담당자·권한 | 없음 | 낮음 |
| 11 | 시각 신뢰 | Windows 전용만 | 중 |
| 12 | 하드웨어 장애 시 판매 지속 | 출력 큐 사고방식 재사용 | 낮음 |

---

## 9. UI/UX 설계 방향

`appfit_order_agent`의 UI 사상은 **제한적으로만** 참고한다 — 그 완성도가 검증된 바 없기 때문이다. 그래서 이 절은 "무엇을 가져오고 무엇을 버리는가"를 **실측 근거로 판정**(§9.6)한 뒤, POS로서 필요한 것을 새로 정의한다.

### 9.1 설계 원칙 — "Simple"의 정의

**Simple은 기능을 숨기는 것이 아니라 덜어내는 것이다.** 숨기면 점원이 찾다가 느려지고, 덜어내면 화면이 빨라진다.

| # | 원칙 | 의미 |
|---|---|---|
| 1 | **모드리스** | 테이블·좌석·코스·웨이터 호출 개념 없음. 앱은 언제나 "새 판매" 상태로 존재한다 |
| 2 | **한 화면 완결** | 메뉴 선택 → 장바구니 → 금액 확인이 화면 전환 없이 한 화면에서 끝난다. 화면을 덮는 것은 **결제와 옵션 선택뿐** |
| 3 | **2탭 담기** | 옵션 없는 상품은 **탭 1회로 장바구니에 들어간다**. 옵션이 있는 상품만 시트가 뜬다 |
| 4 | **판매 화면엔 판매만** | 설정·상품관리·마감·내역은 판매 화면에서 분리한다. 피크타임에 잘못 눌릴 여지를 없앤다 |
| 5 | **되돌릴 수 있게** | 라인 삭제·수량 변경 같은 동작은 확인 다이얼로그 대신 **되돌리기**를 제공한다. 확인은 금전이 확정되는 지점(결제·취소·출금)에만 |
| 6 | **상태를 숨기지 않음** | 오프라인·미전송 건수·프린터 이상은 상단바에 **상시** 표시한다. §8.3의 "미전송 0 게이트"가 UI에서 실체를 갖는 자리다 |

> 업계 조사에서도 계산원은 일반 사용자보다 **약 2배 빠르게 탭**하고, 피크타임 처리량은 평시의 **2~3배**다. 속도가 곧 제품이며, 위 6원칙은 전부 속도를 위한 것이다.

### 9.2 화면 인벤토리 — 1차 8개

| # | 화면 | 성격 |
|---|---|---|
| 1 | 로그인 | 매장코드/서브로그인 ID + 비밀번호, 서버 환경 선택 |
| 2 | **판매 (메인)** | 앱의 90%. §9.3 |
| 3 | 옵션 시트 | 상품에 옵션그룹이 있을 때만. 서버가 주는 `uiButtonType`/`min·maxSelection` 규칙 그대로(§2.4) |
| 4 | 결제 | 수단 선택 → 현금(받은금액·거스름돈) 또는 Square(진행 상태) |
| 5 | 완료 | 영수증 출력 여부, 領収書 발행, 다음 판매로 |
| 6 | 거래 내역 | 당일 목록 + 상세 + 취소 + 재발행 |
| 7 | 영업일·현금 관리 | 개시 / 입출금 / 실사 / 마감 (§8.3·§8.4) |
| 8 | 설정 | 기기·프린터·결제단말·언어 |

8개뿐이라는 것이 이 앱의 정체성이다. 화면이 늘어나는 요구는 "정말 판매 등록기에 필요한가"로 되묻는다.

### 9.3 메인 판매 화면 레이아웃

D3 MINI 실측 해상도 **1280×800 landscape** 기준.

```
┌──────────────────────────────────────────────────────────────────────┐
│ 상단바 56px                                                          │
│  매장명 · 영업일  |  담당자  |  [🟢온라인] [⚠ 미전송 3]  |  ≡        │
├────────┬────────────────────────────────────────┬────────────────────┤
│카테고리│           상품 그리드                  │   회계 패널        │
│ 160px  │           736px                        │      384px         │
│        │                                        │                    │
│ ドリンク│  ┌─────┐┌─────┐┌─────┐┌─────┐         │ ┌────────────────┐ │
│ フード │  │167×110││     ││     ││     │        │ │ 店内   │ お持帰 │ │
│ デザート│  └─────┘└─────┘└─────┘└─────┘         │ └────────────────┘ │
│ セット │  ┌─────┐┌─────┐┌─────┐┌─────┐          │  ─ 라인 리스트 ─   │
│  ...   │  └─────┘└─────┘└─────┘└─────┘          │  ホット珈琲  ¥450  │
│        │        4열 × 5행 = 20개/화면            │   └ L / 氷少なめ   │
│        │                                        │  ...               │
│        │                                        │  ────────────────  │
│        │                                        │  10%対象   ¥1,200  │
│        │                                        │   内消費税   ¥109  │
│        │                                        │  合計    ¥1,200    │
│        │                                        │ ┌────────────────┐ │
│        │                                        │ │  会計 (72px)   │ │
│        │                                        │ └────────────────┘ │
└────────┴────────────────────────────────────────┴────────────────────┘
```

**폭 배분**: `160 + 736 + 384 = 1280`
**타일 산출**: 그리드 영역 736 − 좌우 패딩 32 = 704, 4열 사이 간격 12×3 = 36 → 타일 폭 `(704−36)/4 = 167`
**행 수**: 800 − 상단바 56 − 상하 패딩 32 = 712, 타일 110 + 간격 12 = 122 → `712/122 ≈ 5.8` → **5행**, 한 화면 **20개**

근거: 음식점 POS 화면의 적정대는 **10.1~12.1"** 이고 D3 MINI가 정확히 그 대역이다. 카테고리는 좌측 세로 레일에 두어 상품 그리드의 세로 공간을 최대로 쓴다. 카테고리 색은 **파스텔 + 높은 투명도**의 사각 칩으로 구분한다(원형은 지양).

### 9.4 일본 특화 UI 요구 — 이 절의 핵심

#### (1) 취식/포장은 토글이 아니다

2027-04부터 **취식 10% vs 포장 1%로 세율차가 9%p**가 된다(§7.1). 잘못 누르면 그대로 세무 오류다. 따라서 일반적인 토글 스위치로 두지 않는다.

- **판매 시작 시 명시 선택** — 첫 상품을 담는 순간 아직 미선택이면 선택을 요구한다
- **회계 패널 최상단에 상시 대형 세그먼트** — 화면 어디를 보고 있어도 현재 상태가 보인다
- **색 + 아이콘 + 텍스트 3중 구분** — 색맹·저조도·흘깃 보기 모두에서 구분되게
- **결제 확인 모달에서 재확인** — 금액과 함께 "店内 / お持ち帰り"를 한 번 더 보여준다
- 도중 변경 시 **세액이 다시 계산됨을 즉시 반영**하고, 변경 사실을 라인 리스트 위에 잠시 알린다

#### (2) 금액 표기

- ¥ 정수, 3자리 구분(`¥1,200`), 소수점 없음
- **`FontFeature.tabularFigures()` 필수** — 금액을 세로로 나열하는 화면에서 자릿수가 흔들리면 오독한다. agent에는 없는 요구
- **세율별 소계를 항상 표시** — 적격간이청구서 요건(§7.2)이 화면에도 그대로 반영되어야 점원이 영수증과 대조할 수 있다. 1%/8%/10% 세 줄이 동시에 뜰 수 있다
- 합계는 화면에서 가장 큰 활자(display 32)

#### (3) 현금 계산

- 받은 금액 **프리셋 버튼**(`¥1,000` / `¥5,000` / `¥10,000` / `ちょうど`)을 먼저, 키패드는 그 아래
- 키패드는 **`NumericKeypadWidget` 재사용**(§9.6)
- **거스름돈을 화면에서 가장 크게** — 계산 실수가 곧 현금 과부족(§8.4)이다
- 드로어는 현금 거래 시 자동 개방, 그 외 수동 + 사유 선택

#### (4) 영수증 동선

완료 화면에서 **レシート(적격간이청구서)** 는 기본 출력, **領収書** 는 요청 시 별도 발행(宛名·但し書き 입력). 5만엔 이상은 인지세 안내를 띄운다(§7.4).

### 9.5 디자인 토큰 — POS 규격

| 토큰 | 값 | agent 대비 |
|---|---|---|
| 간격 | 4 / 8 / 12 / 16 / 20 / 24 / 32 | 동일 |
| 라운딩 | 8 / 12 / 16 / 20 | 동일 |
| **타이포** | display **32** / title **24** / titleSm **20** / body **17** / bodySm **15** / caption **13** | **한 단계씩 상향** |
| **금액 전용** | display·title에 `tabularFigures` 적용한 변형 | **신규** |
| **최소 터치 타겟** | **56dp** (주 액션 72dp) | agent는 34~52px |
| 색 | **시맨틱 토큰**으로 정의 — `surface` / `surfaceVariant` / `onSurface` / `outline` / `primary`(결제·확정) / `danger`(취소·반품) / `warning`(오프라인·미전송) / `success`(완료) / `dineIn` / `takeout` | agent는 도메인 색(`statusPalette` 등) |
| 브랜드 색 | **주색 아님.** 로그인 화면과 영수증 로고에 한정 | agent는 브랜드 핑크가 주색 |

**시야거리 ~75cm(카운터)** 를 전제로 타이포를 잡았다. 터치 타겟은 Material 최소 48dp보다 위로 잡는데, 계산원의 빠른 탭과 젖은 손·장갑을 고려한 것이다.

**색을 시맨틱으로 정의하는 이유**는 다크 모드다. 1차는 라이트만 출시하되, 색이 `Colors.white` 같은 리터럴이 아니라 `surface` 같은 역할 이름으로 정의돼 있으면 2차에 다크를 **값 교체만으로** 얻는다. agent가 `Colors.white`를 여러 곳에 하드코딩해 다크를 못 얻는 상태와 반대로 간다.

### 9.6 재사용 판정 — `appfit_order_agent` 자산 감사

**전제**: agent의 토큰 **체계 자체는 건강하다.** `Color(0x` 50건 중 47건이 토큰 정의 파일 안에 있고 화면 코드의 하드코딩은 3건뿐이며, `ThemeData`도 Material 3로 중앙화돼 있다. 문제는 구조가 아니라 **값과 도메인**이다.

| 자산 | 판정 | 근거 |
|---|---|---|
| `AppSpacing` · `AppRadius` · `AppElevation` | ✅ **그대로** | 표준 8pt 그리드, 도메인 중립 |
| `AppTextStyles` | ⚠️ **구조 차용, 값 상향** | 24/20/17/15/13/11 → POS 규격(§9.5). 금액용 tabular 변형 추가 |
| `gray1~gray9` 그레이 스케일 | ✅ 차용 | 5·7·8 결번만 정리 |
| `AppStyles.kMainColor`(브랜드) | ⚠️ **주색에서 강등** | POS는 브랜드 앱이 아니라 업무 도구 |
| `orderPalette` / `orderSourcePalette` / `statusPalette` | ❌ **폐기** | NEW/PREPARING/READY/DONE은 주문접수 도메인. POS엔 없는 개념 |
| `AppStyles.k*Size` 상수군 | ❌ 폐기 | 주문카드·KDS 전용 치수 |
| `primaryButton` / `outlinedButton` / `settingsToggleButton` | ⚠️ 구조 차용, 크기 상향 | 현 `minimumSize` 34~52px → 56dp 이상 |
| `filledInputDecoration` / `outlinedInputDecoration` | ✅ 차용 | 도메인 중립. 포커스 테두리만 브랜드색을 쓰므로 시맨틱 `primary`로 치환하면 끝 |
| `AppLoadingIndicator` · `AppEmptyView` · `AppErrorView` | ✅ **그대로** | 40~62줄, 도메인 중립, 문서화 양호 |
| `ActionButtonShell` · `AsyncActionButton` | ✅ **그대로** | 버튼별 busy 격리 + try/finally + mounted 가드. 우수 패턴이라 그대로 가져간다 |
| **`NumericKeypadWidget`** (93줄) | ✅ **그대로** | 콜백만 받는 순수 위젯. **현금 받은금액·수량 입력에 직결** |
| `CommonDialog` (1065줄) | ⚠️ **형태만 차용해 재구현** | 7개 중 5개(confirm/exit/info/error/updateProgress)는 일반, 2개는 도메인(`OrderCancelReason` 16회 참조). **중복 표시 방지(`_activeDialogKeys`) 아이디어는 이식** |
| `AppStyles.applyBrand` (static mutable) | ❌ **답습 금지** | 전역 가변 상태 + 런타임 변경 불가. Riverpod provider로 |
| 다크 모드 부재 (`Colors.white` 다수) | ❌ 보완 | §9.5의 시맨틱 토큰으로 대체 |
| `textScaler` 미대응 | ❌ 보완 | §9.8 |
| `ThemeData` 중앙화(Material 3) | ✅ 방식 차용 | 화면 코드의 색 하드코딩이 3건뿐인 것이 이 방식의 성과다. POS도 동일하게 간다 |

### 9.7 폰트 전략

#### 🔴 발견 — 번들 폰트에 일본어 한자가 없다

`assets/fonts/Pretendard-*.otf`의 cmap을 직접 파싱한 결과:

| 문자 | 결과 |
|---|---|
| A(라틴) · 가(한글) · あ(히라가나) · ア(카타카나) · ー(장음) · ¥ | ✅ 있음 |
| **円 · 税 · 直 · 骨 · 領 · 収 · 様 (한자)** | ❌ **전부 없음** |

`appfit_order_agent`는 `lib/main.dart`에서 `fontFamily: 'Pretendard'`를 전역 지정하면서 **`fontFamilyFallback`을 어디에도 두지 않았다.** `strings_ja.i18n.json` 실측 결과 고유 한자 **280자**, 번역 문자열 **484개 중 412개(85%)** 가 한자를 포함한다.

→ **일본어 UI의 85%가 "가나는 Pretendard, 한자는 시스템 폴백"으로 혼합 렌더링된다.** 한 문장 안에서 자형·굵기·베이스라인이 섞이고, Android 폴백이 Noto Sans CJK **SC(중국어 간체)** 로 잡히면 한자 자형이 일본 관습과 달라진다(直/骨/類 등). `label_painter.dart`도 Pretendard로 래스터화하므로 **라벨·영수증 이미지 출력에도 같은 문제가 있다.**

> 이는 일본에서 운영 중인 `appfit_order_agent`에 지금 해당되는 이슈이기도 하다. 별도 확인이 필요하다.

#### POS의 폰트 구성

UI 언어를 ja/ko/en 3개로 가는 이상, **한 벌로는 안 된다** — Noto Sans JP에는 한글이 없고 Pretendard에는 한자가 없다.

| 로케일 | primary | fallback |
|---|---|---|
| `ja` | **Noto Sans JP** | `[Pretendard]` |
| `ko` | **Pretendard** | `[Noto Sans JP]` |
| `en` | 둘 중 하나로 고정 | — |

- **서브셋팅 불가** — 상품명·옵션명이 서버에서 오므로 임의의 한자가 들어온다. 전체 한자 세트를 번들해야 한다
- weight는 **Regular / Bold 2종**으로 제한해 용량을 관리한다(정적 OTF 기준 weight당 5MB대). 가변 폰트도 검토 대상
- **검증**: ja/ko/en 각 로케일에서 **한 문장 안에 폰트가 섞이지 않는지** 실기 확인. 특히 일본어 화면에서 가나와 한자의 자형이 일치하는지

### 9.8 접근성 · 사용 환경

| 항목 | 방침 |
|---|---|
| **텍스트 배율** | POS는 레이아웃 안정이 우선 → `textScaler`를 **clamp**한다(예: 1.0~1.15). agent는 미대응 |
| 명도 대비 | 최소 **4.5:1** (WCAG 2.1). 특히 회색 위 회색 조합 금지 |
| 터치 | 젖은 손·장갑 전제 → 최소 56dp, 주 액션 72dp, 인접 액션 간 간격 12 이상 |
| **오탭 비용** | 파괴적 액션(라인 삭제·전체 비우기)은 결제 버튼과 **물리적으로 멀리** 배치 |
| 조도 | 1차는 라이트 전용. 다크는 §9.5의 시맨틱 토큰으로 2차에 확보 |
| **3개 언어 폭** | 같은 라벨이 ja/ko/en에서 길이가 다르다. 버튼은 **고정폭 + 2줄 허용 + 말줄임**을 기본으로 하고, 세 언어 중 최장 문자열로 레이아웃을 검증한다 |
| 사운드 | 담기·결제 완료·오류에 짧은 피드백음. 주방 소음 환경에서 시각만으로는 부족 |

### 9.9 UI 관점의 미결 사항

§10.2 확인 질문에 합류시킨다.

- **상품 타일에 이미지를 쓸 것인가** — 서버가 `imageUrls`/`thumbnailImageUrl`을 준다(§2.4). 이미지를 쓰면 타일이 커져 한 화면 상품 수가 줄고, 텍스트만 쓰면 밀도가 오른다. 소형 카페는 텍스트+색상칩이 대체로 빠르다
- **폰트 번들 용량 상한** — Noto Sans JP 전체 한자 세트가 필요해 APK가 10MB 이상 늘어난다
- **고객 디스플레이 활용 범위** — 58mm 변형은 2.4" 7세그먼트(숫자 전용)라 금액만 표시 가능하고, 4" IPS는 80mm 변형에만 있다(§5)

---

## 10. 갭 · 확인 질문

### 10.1 앱이 메워야 할 갭

| 갭 | 대응 |
|---|---|
| Ex 카탈로그에 `inShopPrice` 없음 | `/v0/migration/items` 병용 (§2.5) |
| 현금 거스름돈·시재·드로어 개폐 이력 서버 미지원 | 로컬 처리 + 일마감 화면에서 서버 집계와 대조 |
| Terminal API 오프라인 불가 | 결제는 온라인 필수로 명시. 주문 등록만 큐잉(`orderedAt` + `externalOrderNo`) |
| 세율 3종 병존 | 세율 테이블 구조로 설계 (§7.1) |
| POS CFG 의존 코드 이식 | `settingsProvider` → AppFit/로컬 치환 (§3, §4) |
| 외부 ESC/POS 경로가 CP949 고정 | Sunmi 내장 프린터는 인코딩 무관(AIDL). 외부 프린터가 필요하면 `kiosk_v3_japan`의 Shift_JIS 구현 이식 |
| **현금 관리 전반**(준비금·거스름돈·입출금·과부족) 서버 API 없음 | 로컬 전용. 일마감 화면에서 서버 집계와 대조 (§8.4) |
| **영업일·마감 상태** 서버 API 없음 | 로컬. `sales-closing`의 `businessDate`와 판정 규칙을 일치시킬 것 (§8.3) |
| **미전송 건이 있으면 일마감 금액이 실제와 다름** | 마감 화면에 "미전송 N건" 표시 + 미전송 0을 마감 확정 조건으로 (§8.3) |
| 오프라인 시 `shopOrderNo` 없음 | 로컬 채번 후 서버 번호와 대응 (§8.8) |
| 담당자·권한 개념 없음 | 신규 (§8.9) |
| 기기 시각 신뢰 (세율 전환일·영업일 판정) | 서버 시각과 차이 감시 (§8.10) |
| **일본어 한자가 번들 폰트에 없음** | Noto Sans JP 번들 + 로케일별 primary/fallback (§9.7) |
| agent 디자인 토큰이 주문접수 도메인에 묶임 | 시맨틱 토큰으로 재정의, 도메인 팔레트 폐기 (§9.5·§9.6) |
| 터치 타겟·타이포가 POS 규격에 미달 | 최소 56dp, 타이포 한 단계 상향 (§9.5) |

### 10.2 확인 질문

| # | 대상 | 질문 |
|---|---|---|
| 1 | 백엔드 | **2027-04 세율 개정 대응 계획.** `sales-closing`의 취식10/포장8 고정 규칙, 1%/8%/10% 병존, 적용시작일 파라미터화 **[최우선]** |
| 2 | 백엔드 | **품목별 세율 구분** — 포장 주류 10% 처리 계획 **[세무 리스크]** |
| 3 | 백엔드 | **§3 ② 신규 API 3종** — 세율 테이블 / 적격청구서 등록번호 / 매장별 결제단말 설정. 우선순위와 일정 |
| 4 | 백엔드 | `WALD_POS`가 `externalOrderNo` **유일성 대상 외부사**에 포함되는가. 미포함이면 오프라인 재전송이 중복 주문을 만든다 |
| 5 | 백엔드 | Ex 카탈로그(`/v0/shops/{shopCode}/categories/items`)에 `inShopPrice` 추가 가능한가 |
| 6 | 백엔드 | `sales-closing`이 취소·부분취소·환불을 어떻게 반영하는가 (交通系IC 환불 불가 건 포함) |
| 7 | 개발 | `kiosk_v4_japan` 레포 접근 — Square 구현이 v3 대비 얼마나 진화했는지 |
| 8 | 사업 | Square vs GMO A35 결정 근거. 매장별 Square 계정 개설 주체, e-money/QR 가맹점 승인 절차 담당 |
| 9 | 사업 | 대상 브랜드·파일럿 매장. D3 MINI 신규 도입인지 기존 재사용인지, **프린터 변형(58 vs 80mm)** — 고객 디스플레이 기능 가부가 갈린다 |
| 10 | 백엔드 | **세액 계산 규칙의 정확한 정의.** 주문 등록 요청에 세금 필드가 없어 서버가 자체 계산하는데, 영수증에 세액을 인쇄하는 것은 앱이다. 절사 단위(주문별 확인됨)·세율별 소계 산출식·할인이 있을 때의 과세표준을 명문화해야 **영수증 세액과 일마감 세액이 일치**한다 (§8.5) |
| 11 | 백엔드 | **오프라인 큐가 세율 전환일을 넘겨 전송될 때 어느 세율이 적용되는가** — `orderedAt` 기준인가 수신 시각 기준인가. 2027-04-01 전후 며칠간 실제로 발생한다 (§8.5) |
| 12 | 백엔드 | **환불 불가 수단의 대체 환불 기록 방법.** 交通系IC 결제를 현금으로 환불했을 때 `payInfos[]`에 어떻게 표현하는가 (§8.7) |
| 13 | 백엔드 | **라인 단위 부분 취소** 지원 여부. `payInfos[]`는 결제 건별 매칭인데 상품 단위 반품을 어떻게 보내는가 (§8.7) |
| 14 | 기획/디자인 | **상품 타일에 이미지를 쓸 것인가.** 서버가 `imageUrls`/`thumbnailImageUrl`을 주지만(§2.4), 이미지를 쓰면 타일이 커져 한 화면 상품 수가 줄고 텍스트+색상칩은 밀도가 오른다 (§9.9) |
| 15 | 개발/기획 | **폰트 번들 용량 상한.** Noto Sans JP는 서브셋팅이 불가해 전체 한자 세트가 필요하고 APK가 10MB 이상 늘어난다 (§9.7) |
| 16 | 사업/개발 | **고객 디스플레이 활용 범위.** 58mm 변형은 2.4" 7세그먼트(숫자 전용)라 금액만 표시 가능하다 — 도입 기종이 정해져야 설계가 갈린다 (§5, §9.9) |

---

## 11. 1차 범위와 로드맵

### 11.1 1차 범위 — 판매 등록기 최소셋

**포함**

- 로그인 / 매장 선택
- 카탈로그 동기화 (증분) + 오프라인 캐시
- **메인 판매 화면 1장으로 완결되는 동선** (§9.1·§9.3)
- 메뉴 그리드 + 옵션 선택 (서버 규칙 준수)
- 장바구니
- 취식 / 포장 전환 (`inShopPrice` 반영) — **토글이 아니라 명시 선택 + 상시 표시 + 결제 재확인** (§9.4)
- 금액 계산 (내세, 세율 테이블, 주문 단위 절사, 할인 안분) — §8.5
- 결제 — 현금(**받은 금액·거스름돈**) + Square Terminal
- **로컬 원장 기록 + 3단계 원자성/크래시 복구** — §8.6
- 주문 등록 `POST /v1/orders` + 오프라인 큐 + 재전송 수렴
- 영수증 출력 (적격간이청구서 요건 + 領収書) + 로컬 채번 + 재발행
- 캐시드로어 개폐 + 개폐 이력
- 주문 취소 (당일) + 환불 불가 수단 대체 동선
- **영업일 개시/마감** + **현금 실사·과부족** + 일 매출 마감 조회(**미전송 0 게이트**) — §8.3·§8.4

**제외 (2차 이후)**

회원·스탬프·쿠폰 / 앱·키오스크 주문 접수 및 KDS / 테이블 관리 / 예약 / 재고 / 다중 단말 동기화

### 11.2 단계

| Phase | 내용 | 완료 기준 |
|---|---|---|
| **0** | `kiosk_v4_japan` 확보 + 스테이징 E2E + Square 샌드박스 1건 + **§9.2 백엔드 질문 회신**(특히 Q1·Q2·Q4·Q10·Q11) | 카탈로그 → 주문등록 → 취소 → 일마감이 실제로 돌고, Square 샌드박스 결제 1건 성공. 세액 계산 규칙 합의 |
| **1** | 신규 레포 골격(`appfit_core` 태그 의존) + AppFit 로그인 / 매장 / 카탈로그 증분 동기화 + **로컬 DB 스키마 확정**(§8.2) + **디자인 토큰·폰트 확정**(§9.5·§9.7) | D3 MINI에 설치되어 메뉴가 뜬다. 오프라인에서도 메뉴가 뜬다. **ja/ko/en 각 화면에서 폰트가 한 문장 안에 섞이지 않는다** |
| **2** | 장바구니 · 옵션(서버 규칙) · **세율 테이블 + 금액 계산 결정론**(§8.5) | 서버 금액 검증식이 400 없이 통과. **절사·할인 안분 골든 테스트** 통과. 1%/8%/10% 전환 테스트 통과 |
| **3** | 현금(거스름돈) + Square Terminal 이식(CFG 의존 제거) + **로컬 원장 + 3단계 원자성**(§8.6) + 주문 등록 + 오프라인 큐 | 네트워크 단절 후 복구 시 중복 없이 등록. **결제 승인 직후 강제 종료해도 판매가 회수**된다 |
| **4** | 영수증(적격간이청구서 + 領収書) + 로컬 채번 + 재발행 + 캐시드로어(개폐 이력) + 고객 디스플레이 | 기재 5항목이 실물 레시트에 인쇄. 오프라인 판매도 번호가 찍힌다 |
| **5** | **영업일 개시/마감 + 현금 관리(준비금·입출금·실사·과부족)** + 일 매출 마감 조회 | **미전송 0 게이트**가 동작하고, 현금 과부족이 산출된다 |
| **6** | 취소/반품(당일·전일, 부분, 交通系IC 예외) + 담당자·권한 + 시각 신뢰 + OTA · Fleet 편입 | 운영 투입 가능 |

---

## 부록 — 조사 재현 방법

```bash
# OpenAPI 스펙 확보 (재다운로드 바이트 동일 확인됨: 293 paths / 587 schemas)
curl -s https://core-stgapi.waldplatform.com/v3/api-docs -o apidocs.json

# 일 매출 마감 설명 원문
node -e "const s=require('./apidocs.json');console.log(s.paths['/v1/shop/{shopCode}/sales-closing'].get.description)"

# 주문 등록 요청 스키마
node -e "const s=require('./apidocs.json');const S=s.components.schemas;
const n=Object.keys(S).find(k=>k.endsWith('RegisterExternalOrderV1Request'));
console.log(JSON.stringify(S[n],null,1))"
```

인용한 사내 파일:

- `kiosk_v3_japan/lib/features/square/provider/repo_square_terminal.dart`
- `kiosk_v3_japan/lib/features/pay/utils/japan_payment_utils.dart`
- `kiosk_v3_japan/lib/service/print_services.dart`
- `kiosk_v4/lib/features/pay/data/m_appfit_order.dart`
- `kiosk_v4/lib/features/pay/strategy/appfit_save_strategy.dart`
- `kiosk_v4/lib/service/sql_db/order_database_services.dart` (로컬 스키마 — `orders`/`failed_orders`/`pending_payments`)
- `kiosk_v4/lib/service/sql_db/menu_database_services.dart` (`foundation_sync`/`master_raw_data`/`master_raw_chunks`)
- `appfit_order_agent/android/app/src/main/java/co/kr/waldlust/order/receive/util/print/SunmiPrintHelper.java`
- `appifit_agent_core/appfit_core/lib/src/config/appfit_config.dart`
- `appfit_order_agent/lib/constants/app_styles.dart` (디자인 토큰 — §9.6 판정 대상)
- `appfit_order_agent/lib/widgets/common/` (`action_button_shell` · `async_action_button` · `common_dialog` · `app_loading_indicator` · `app_empty_view` · `app_error_view`)
- `appfit_order_agent/lib/widgets/membership/numeric_keypad_widget.dart` (현금 입력 재사용 대상)
- `appfit_order_agent/assets/fonts/Pretendard-*.otf` (§9.7 cmap 실측 대상)

폰트 커버리지 재현 (cmap 직접 파싱):

```bash
# Pretendard 에 한자가 없음을 확인 — 円(U+5186)·税(U+7A0E)·領(U+9818) 등이 ❌ 로 나온다
node cmap.js assets/fonts/Pretendard-Regular.otf

# ja 번역의 한자 비율 확인 — 고유 280자 / 484개 중 412개(85%)
node -e "const o=require('./lib/i18n/strings_ja.i18n.json');let t=0,m=0;(function w(x){for(const v of Object.values(x)){if(typeof v==='string'){t++;if(/[一-鿿]/.test(v))m++;}else if(v&&typeof v==='object')w(v);}})(o);console.log(m+'/'+t)"
```
