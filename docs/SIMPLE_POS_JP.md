# 일본향 Simple POS — 착수 전 기초 조사

> **문서 성격**: 신규 앱 착수 판단을 위한 사실 조사 보고서. 구현 계획서가 아니다.
> **조사 기준일**: 2026-08-28
> **조사 방법**: AppFit Core OpenAPI 스펙 전수 파싱(`core-stgapi`, 293 paths / 305 operations / 587 schemas) · **사내 12개 레포 전수 확인**(`appfit_order_agent`, `appifit_agent_core`, `kiosk_v4`, `kiosk_v3_japan` + 2차에서 `kokonutJapan`·`kokonut_order_agent`(_v2)·`kiosk`·`kiosk_new`(_v2)·`kiosk_v2`·`kiosk_v3`) · Square 공식 개발자 문서 원문 인용 · **국세청 법령·통달·Q&A 원문**(e-Gov / nta.go.jp) · 레거시 POS 운영 관행 조사
> **검증 수준**: 1차 조사 후 전면 재검증, 이어서 **POS 도메인 지식 기준 2차 재검증**을 거쳤다. 1차 재검증에서 서술 3건 정정 + 세제 개정 1건 발견. **2차 재검증에서 서술 5건이 추가 정정되고 신규 발견 35건이 반영됐다**(§8은 이때 실질 재작성). 정정 이력은 §12.

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

> ⚠️ **단, "주문별 절사"는 한 주문에 세율이 하나일 때만 법령과 정합한다.** 일본 세법이 요구하는 단위는 `영수증 1장 × 세율마다 각 1회`이지 주문당 1회가 아니다(§8.5). 지금은 서버가 `orderType`만 보고 주문 전체에 한 세율을 적용하므로 결과가 우연히 일치하지만, §7.3(포장 주류 10%)이 실현돼 **한 주문에 8%와 10%가 섞이는 순간 절사가 세율별 2회로 바뀌어야 한다.** → §10 Q2·Q17

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
| **매장별 결제단말 설정** (Square 자격증명 · Location ID · 전자머니/QR 사용여부 / GMO A35 IP·포트) | ② **신규** | 매장별 민감정보. **장기 액세스 토큰을 기기에 두지 않는 구조가 정석** — 아래 참조 |
| 영수증 출력 여부 · 하단 문구 · 로고 | ② 또는 ③ | 원격 관리 필요성에 따라 결정 |
| 프린터/스캐너 종류 · 시리얼 포트 | ③ | 기기 고유 |
| 기기명 · 자동로그인 · 테스트 모드 | ③ | |
| 세션/경고 타임아웃, 그리드 수 등 UI | ③ 또는 코드 | Simple POS는 화면 타입 분기 자체가 불필요 |

### 결론

**AppFit에 신규로 필요한 것은 실질적으로 3가지다.**

1. **세율 테이블** — `(적용시작일, 품목분류, 주문유형) → {표시세율, 내세역산분수, 국세율}` (§8.5에서 구조 확정)
2. **적격청구서 발행사업자 등록번호**
3. **매장별 결제단말 설정 — 단, 토큰 중개까지 포함한다** (아래)

나머지는 전부 기존 AppFit API 또는 기기 로컬로 덮인다. POS 서버를 배제해도 공백이 크지 않다는 것이 이번 조사의 실질 결론 중 하나다.

### ⚠️ 3번의 성격 정정 — 결제 자격증명은 "설정값"이 아니다

1차 조사는 Square 액세스 토큰을 다른 설정값과 같은 층위로 두고 "AppFit 설정 API가 정석, 없는 동안은 기기 로컬 입력"이라 적었다. **이는 Square 보안 가이드에 어긋난다.** Square 문서는 액세스 토큰의 하드코딩·클라이언트 코드 포함·버전관리 노출을 명시적으로 금지하고, 안전한 자격증명 저장소와 강암호화를 요구한다.

| 원칙 | 내용 |
|---|---|
| **장기 토큰은 서버에만** | AppFit이 매장별 Square 자격증명을 보관·갱신한다. OAuth 사용 시 액세스 토큰은 **30일 만료 · 7일 이내 자동 갱신**, 모바일 등 public client는 **PKCE** 필수 |
| **기기에는 단기 세션 토큰** | 기기는 AppFit이 발급한 단기 토큰으로 결제 요청을 중개받는다 |
| **부득이 기기 저장 시** | **Android Keystore** 기반 보안 저장소 + **기기 단위 revoke 경로**가 전제 조건. 평문 저장은 도난 단말로 서버 매장 데이터를 조작당하는 경로가 된다(§8.12) |
| 최소 권한 | 필요한 scope만 발급 |

즉 3번은 "설정 항목 하나 추가"가 아니라 **AppFit이 결제 자격증명의 보관·갱신 주체가 된다는 설계 결정**이다. 일정 산정에서 1·2번과 다르게 다뤄야 한다.

---

## 4. 재사용 자산 인벤토리

> 모두 **코드 이식** 대상이다. 런타임 연동 대상이 아니다.

| 출처 | 자산 | 이식 시 주의 |
|---|---|---|
| **kiosk_v3_japan** | `lib/features/square/provider/` — `repo_square_terminal.dart`(Devices·Terminal·Refund API 전체), `square_terminal_provider.dart`(폴링·PING·상태머신, 652줄), `m_square_checkout.dart`, `m_square_terminal.dart`(`SquarePaymentType`) | **토큰·Location ID를 `settingsProvider`(POS CFG)에서 읽는다 → §3 ② 경로로 치환 필수.** 🔴 **추가로 결함 1건을 고쳐야 한다 — 아래** |
| | `lib/features/admin/widget/setting/w_square_terminal.dart` | 페어링 UI(6자리 코드) |
| | `w_square_payment_indicator.dart`, `w_square_refund_indicator.dart` | 결제·환불 진행 UI |
| | `lib/features/pay/utils/japan_payment_utils.dart` | 일본 결제수단 ↔ `SquarePaymentType` 매핑 |
| | `lib/service/print_services.dart` | **Shift_JIS 영수증 + 領収書(료슈쇼) 출력** (`charset_converter`, `isKorean ? "euc-kr" : "Shift_JIS"`) |
| **kiosk_v4** | `lib/features/pay/data/m_appfit_order.dart` | **`POST /v1/orders` 완성 클라이언트.** `inShopPrice`·`payments[]`·`cashReceipts`·`externalOrderNo`·`orderedAt` 전부 구현. **"할인은 라인에만 — top-level 중복 금지(서버가 합산 검증하므로 이중 계상되면 거절)"** 같은 실전 노하우가 주석으로 남아 있음 |
| | `appfit_save_strategy.dart` + `failed_order_retry_service.dart` | **결제 성공 후 서버 저장 실패 → 로컬 DB 마킹 + 백그라운드 재시도 큐.** POS 오프라인 내성의 핵심. `pos_save_strategy` 분기는 제거 |
| | `CartState`(할인 SSOT), 옵션 선택 UI, `payment_gateway.dart` 게이트웨이 추상화 | POS CFG 의존부 제거 |
| **appfit_order_agent** | `SunmiPrintHelper.java` — 내장 프린터, **`openCashBox()`**, 고객 LCD(`sendTextToLcd`/`sendBitmapToLcd`), QR·바코드, `getPrinterSerialNo` | 소형 POS 주변장치 요구를 그대로 충족 |
| | **스캐너** — `MainActivity.java:313` `hasScanner()` 기기 판별, `AndroidManifest.xml:9-22` `<queries>` 이중 선언(신형 `com.sunmi.scanner` / 구형 `com.sunmi.sunmiqrcodescanner`) | 판별·선언은 그대로 재사용. 단 **입력 모드는 교체 필요** — 현재는 스캔 **액티비티 인텐트**(모달)라 POS 상시 스캔에 부적합(§5) |
| | `output_queue_service` / `printer_job_queue` / `startup_probe_scheduler` | 출력 큐·backoff·재시도 |
| | `core/products/shop_catalog_parser.dart` | 카탈로그 응답 → 모델 순수 함수 |
| | `services/receipt_labels.dart` + slang ko/en/**ja** | 영수증 라벨 다국어. 이미 `領収書`·`消費税`·`様` 배포 중 |
| | Windows 데스크톱 골격(단일 인스턴스·트레이·자동시작·per-user 인스톨러) | 2순위 플랫폼용 |
| **appfit_core** | 토큰/AES-GCM, Dio 인터셉터(자동 인증 헤더+암호화), `ApiRoutes`, WebSocket notifier, OTA, Fleet, Sentry, `SerialAsyncQueue` | 태그 핀 의존. 신규 라우트 추가는 `tool/release.sh` 단일 진입점 |

### 🔴 이식 전 반드시 고칠 결함 — Square 체크아웃 폐기

`kiosk_v3_japan/lib/features/square/provider/square_terminal_provider.dart:405-431`

취소 요청 후 폴링이 최대 시도를 넘기면 다음과 같이 처리한다.

```dart
CommonUtil.writeErrorAndFileLog(..., '❌ 취소 후 폴링 타임아웃 - 강제 상태 초기화');
state = state.copyWith(
  isLoading: false,
  checkoutStatus: 'TIMEOUT_CANCELED',
  cancelReason: 'TIMEOUT_AUTO_CANCEL',
  clearCheckout: true,      // ← 체크아웃 ID를 버린다
);
```

**최종 상태를 확정하지 못한 채 체크아웃을 버린다.** Square 문서는 타임아웃 경계에서 **서버가 `CANCELED`로 둔 사이에도 단말이 결제를 완주**할 수 있다고 명시한다(§6.3). 즉 이 분기는 "결제됐을 수도 있는 건"을 추적 단서 없이 폐기한다.

키오스크에서는 캐시리스 + 현금 대사가 없어 넘어갔지만, **현금 시재를 맞추는 POS에서는 §8.6 ①("돈은 받았는데 판매 기록이 없다")이 그대로 발생**한다. 이식할 때 이 분기를 §8.6의 `unknown` 상태 + `SearchTerminalCheckouts` 정합화로 교체해야 한다. **그대로 복사 금지.**

**미확보**: `kiosk_v4_japan`(별도 레포, 이 머신에 없음). Square 최신 구현이 v3 대비 얼마나 진화했는지 확인하려면 clone 필요.

**전수 확인 결과 (2026-08-28, 2차)**: 사내 나머지 8개 레포(`kokonutJapan`·`kokonut_order_agent`·`kokonut_order_agent_v2`·`kiosk`·`kiosk_new`·`kiosk_new_v2`·`kiosk_v2`·`kiosk_v3`)를 전수 확인했으나 **현금을 다루는 POS 자산은 없다.** 전자는 주문 수신/출력 에이전트, 후자는 고객 셀프오더 키오스크 계보이며 영업일 마감·현금 관리·드로어 이력·전표 채번·담당자 권한·전자저널이 **전부 미구현**이다. 주변부 참고 자산 2건만 있다 — `kiosk_v3/lib/shared/provider/order_number_provider.dart`(날짜 리셋 **대기표** 번호. 전표번호가 아니므로 §8.8의 **반례**로만 가치), `kiosk_v3/lib/features/admin/dialog/d_admin_password.dart`(4자리 PIN 다이얼로그 **UI 패턴**만. 기본값이 오늘 날짜 MMDD라 그대로 쓰면 안 됨). → **§8의 "그린필드" 판정은 재확인됐다.** 재조사 불요.

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

### 5.1 스캐너 입력 모드 — 설계 분기점

내장 스캐너가 있다는 사실만으로는 부족하다. **어떤 방식으로 앱에 들어오는가**가 UI 구조를 가른다. Sunmi는 3가지를 제공하며 공장 기본값은 "키 시뮬레이션 + Enter 전송 + 브로드캐스트"다.

| 모드 | 특성 | POS 적합성 |
|---|---|---|
| **브로드캐스트** (`com.sunmi.scanner.ACTION_DATA_CODE_RECEIVED`, extra `data`) | 포커스 무관, 소프트키보드 미발생 | ✅ **1차 경로**. 판매 화면 어디에 있든 스캔이 들어온다 |
| 키보드 시뮬레이션(HID 웨지) | 포커스된 위젯에 키 입력으로 주입 | ⚠️ 외장 스캐너 폴백용 |
| 직접 채움(클립보드) | 클립보드 경유 | ❌ |

**HID 웨지의 고전적 함정** — 포커스가 없으면 입력이 유실되거나 엉뚱한 위젯으로 가고, paste 이벤트가 발생하지 않아 일반적인 붙여넣기 감지로는 못 잡으며, 스캐너와 OS 키보드 레이아웃이 어긋나면 문자가 뒤바뀌고, 소프트키보드가 매번 떠서 화면을 가린다.

**설계 방침**
- 브로드캐스트를 1차로 받고, HID는 앱 최상위 **전역 키 캡처** + "30ms 이내 연속 키를 한 스캔으로 묶고 개행으로 종료" 파서로 폴백 처리
- `(코드, 200ms)` 디바운스로 빠른 연속 스캔 흡수
- **스캔을 소비할 대상이 없으면 조용히 버리지 말고** "지금은 스캔 대상 없음"을 알린다 — 점원이 스캔했는데 아무 반응이 없는 것이 가장 나쁘다
- 기존 자산: `hasScanner()` 판별과 `<queries>` 이중 선언은 그대로 재사용(§4)

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
| **미결 체크아웃 정합화** | **`POST /v2/terminals/checkouts/search`** (`SearchTerminalCheckouts` — 디바이스ID·기간·상태 필터). 사내 구현에는 **없다.** 결제 결과 불명 시 정본 절차 |
| **결제 결과 불명 취소** | **`CancelPaymentByIdempotencyKey`** — 해당 키의 결제가 없으면 no-op 성공. 취소 확정 후 재요청 |

### ⚠️ "웹훅 불필요" 결론의 조건부 정정

1차 조사는 *"웹훅을 쓰지 않는다 → 별도 백엔드 컴포넌트가 필요 없다"*로 단정했다. **폴링으로 갈 수 있다는 결론 자체는 유지되지만, 무조건은 아니다.**

Square가 웹훅을 권고하는 이유는 편의가 아니라 **상태 전이의 역전** 때문이다 — 타임아웃 경계에서 **서버가 체크아웃을 `CANCELED`로 둔 사이에도 단말은 결제를 완주**할 수 있어, `CANCELED → COMPLETED` 순서가 실제로 나온다. 폴링은 이 전이를 놓칠 수 있고, 놓친 결과가 곧 §8.6 ①("돈은 받았는데 판매 기록이 없다")이다.

**따라서 폴링만으로 가려면 다음이 필수 조건이다.**

1. **기동 시 `SearchTerminalCheckouts` 정합화** — 미결 체크아웃을 조회해 회수한다. 이것이 웹훅을 대신하는 안전망이다
2. **결제 상태를 `unknown`으로 유지**할 수 있는 모델(§8.6) — 타임아웃을 실패로 접지 않는다
3. **`COMPLETED`여도 Payment 객체로 실징수액을 확인** — 팁 등으로 **실징수액 ≠ 요청액**일 수 있다고 Square가 명시한다. 금액을 대조하지 않으면 시재가 어긋난다

이 셋이 갖춰지면 백엔드 컴포넌트 없이 성립한다. **갖춰지지 않으면 웹훅 수신부가 필요하다.**

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

### 6.7 PCI DSS 스코프

카드 데이터가 **우리 앱을 통과하지 않는다**(단말 내부에서만 처리) — 이것이 Terminal API의 최대 이점이며, 가맹점은 통상 **SAQ B-IP**(IP 연결 독립형 단말) 유형에 해당한다. Square는 PCI DSS Level 1 준수 주체로서 가맹점의 개별 검증 부담을 덜어준다.

**다만 스코프가 0이 되는 것은 아니다.** 물리 단말 관리, POS 소프트웨어, 서비스 제공자로의 전송 구간은 가맹점 책임으로 남는다. 그리고 액세스 토큰 취급은 우리 책임 영역이다(§3, §8.12).

> ⚠️ **미확인**: Square가 PCI SSC의 **validated P2PE 솔루션 목록에 등재**돼 있는지 확인하지 못했다. SAQ P2PE-HW는 등재된 솔루션에만 적용되므로, **"P2PE라서 스코프가 줄어든다"를 전제로 삼으면 안 된다.** 일본 가맹점 계약상 SAQ 제출 의무가 실제로 부과되는지도 미확인 → §10 Q21

### 6.8 대안 — GMO A35

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

1. **1%로 정한 공식 이유가 "0%보다 사업자의 시스템 개수 기간을 단축할 수 있어서"다**(0%는 10~12개월, 1%는 5~6개월로 정리됐다). 제도 자체가 POS 개수를 전제하고 있다.
1-b. **개수는 2회다.** 2029-03-31 종료 = **2029-04 원복**이 예정돼 있다. 1회성 대응으로 설계하면 2년 뒤 같은 작업을 반복한다. 세율 마스터를 **서버 배포 가능한 데이터**로 두면 두 전환을 앱 재배포 없이 넘긴다.
1-c. **경감대상 여부는 상품 속성이 아니라 `상품 × 제공형태(취식/포장)`의 함수다.** 같은 상품이 포장이면 1%(장래), 점내 취식이면 10%가 된다. 이 구조를 지금 확정해야 전환 때 스키마를 안 건드린다. 상품에 `isReducedRate` 같은 단일 불리언을 두면 반드시 다시 짜야 한다.
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

#### ⑤의 선택이 세무 방침을 가른다 — 레이아웃 문제가 아니다

간이청구서는 「세율별 소비세액」과 「적용세율」 중 **하나만** 기재해도 된다. 그런데 이 선택이 신고 방식을 제약한다.

매출세액 계산에는 두 경로가 있다(§8.5). 특례인 **積上げ計算**은 *"교부한 적격청구서 또는 적격간이청구서 사본을 보존하고 있는 경우, **그 서류에 기재한 소비세액 등의 합계액에 100분의 78을 곱해**"* 산출한다(Q&A 問118). 즉 **영수증에 세액을 인쇄하지 않고 「적용세율」만 찍으면 積上げ計算 자체가 불가능**해진다. (덧붙여 매출을 積上げ로 하면 **매입도 積上げ가 강제**된다.)

→ **세액 인쇄 여부는 인쇄 템플릿 취향이 아니라 매장 세무 방침에 직결되는 설정 항목**이다. 기본값은 "세액 인쇄"로 두어 선택지를 닫지 않는다.

#### ③ 「경감세율 대상인 취지」의 표시 — ※ 말고도 있다

軽減通達18 / 軽減Q&A 問13은 *"경감대상 자산의 양도 등임이 **객관적으로 명백하다고 할 수 있는 정도의 표시**"* 면 된다고 하고, 다음을 모두 인정한다.

| 방식 | 내용 |
|---|---|
| 기호 + 범례 | `※`·`☆` 등을 붙이고 「※는 경감대상」 범례를 표시 |
| **세율별 그룹핑** | 한 영수증에서 경감대상과 그 외를 **구분해 묶고**, 묶음 전체가 경감대상임을 표시 |
| 영수증 분리 | 경감대상분과 그 외를 **별도 영수증**으로 작성 |
| **라인별 세율 직접 인쇄** | 개별 거래마다 `10%`/`8%`를 기재 |

**58mm 감열지에서는 라인별 세율 인쇄가 유리할 수 있다** — 범례 줄이 사라지고 스캔이 쉽다. 어느 쪽이든 적법하므로 **인쇄 템플릿 옵션**으로 둔다.

#### 법정 기재 vs 관행 기재

혼동하기 쉬워 분리해 둔다.

- **법정 위치·형식 규정 없음** — 등록번호의 인쇄 위치는 자유(국세청 예시는 헤더), 세액 표기 형식도 자유(예시: `８％対象 ２点 ¥1,080（内消費税額 ¥80）`)
- **税抜/税込 혼재 금지** — 어느 쪽이든 **통일**해야 한다(問59). 통일 과정의 1엔 미만 처리는 사업자 임의이며, 이것은 §8.5의 소비세액 단수처리와 **별개**다
- **관행이지 법정 아님** — お預り/お釣, 점수, 레지 번호, 담당자, 시각, 바코드, 「領収書」 표제 자체

→ 법정 5요건은 **인쇄 실패 시 거래를 막는 하드 검증**으로, 나머지는 템플릿 토글로 분리한다. 등록번호는 매장 마스터 필수 항목으로 두고, **미등록 매장은 인쇄 금지 플래그**를 건다.

### 7.3 경감세율 범위 — 서버 규칙과의 갭

경감세율 8%(→2027-04부터 1%) 대상은 **"주류·외식·케이터링을 제외한 음식료품"**이다.

**→ 포장이어도 주류는 10%다.** 그런데 서버 `sales-closing`은 **주문유형만 보고 "포장 = 8%"를 일괄 적용**한다. 주류를 취급하는 매장에서는 **구조적으로 세액이 틀린다.** 상품 단위 세율 구분이 서버·앱 양쪽에 필요하다 → §10 Q2.

### 7.4 그 밖

| 항목 | 내용 |
|---|---|
| 총액표시 의무 | 소비자 대상 가격은 세포함(内税) 표시. 서버가 내세 기준으로 계산하므로 정합 |
| 領収書 | 요청 시 宛名·但し書き 대응 필요. `kiosk_v3_japan`에 출력 구현 있음. **레시트와 동시 교부는 이중발행** → §8.8·§9.4 |
| 인지세 | 현금 5만엔 이상 영수증은 인지세 대상 |
| **전자장부보존법** | 2022 개정의 유예가 끝나 **2024-01부터 전자적으로 주고받은 거래기록은 전자 형태 그대로 보존 의무**(스캐너 보존은 임의). 원칙 보존기간 **7년**, 법인세법상 결손금 이월이 있으면 최대 **10년**. **보존 주체가 AppFit 서버 원장인지 확인 필요** → §10 Q20. 이것이 §8.2의 로컬 보존기간을 좌우한다 |
| 재정 레지스터 인증 | ✅ **불요(확정)**. 일본은 이탈리아·그리스식 **정부 인증 fiscal 하드웨어**(fiscal memory·실시간 세무당국 전송)를 요구하지 않는다. 인보이스 제도도 인정 레지 사용을 의무화하지 않으며 요건만 충족하면 수기 영수증도 유효하다. **인증 하드웨어 조달·심사를 일정에 넣을 필요가 없다** |
| 주류 연령확인 | 「二十歳未満ノ者ノ飲酒ノ禁止ニ関スル法律」상 판매자에게 연령확인 등 필요조치 의무. 위반 시 최대 **50만엔 벌금 + 주류판매면허 취소**(취소 후 3년 재신청 불가). 유인 카운터이므로 실무 표준은 **「20歳以上ですか」 확인 프롬프트 + 직원 육안 확인**. 주류 취급 매장이면 상품에 연령확인 플래그가 필요하다. ⚠️ **미확인**: "대면 확인"이 조문상 명시된 방법 요건인지 |

### 7.5 返還インボイス(적격반환청구서) — 반품·값인하

1차 조사에 전혀 없던 항목이다. **반품에는 별도의 법정 문서 타입이 있다.**

| 항목 | 내용 |
|---|---|
| 교부 의무 | 적격청구서 발행사업자가 **매출 대가의 반환 등**(반품·값인하·할인)을 할 때 **적격반환청구서 교부 의무**(消法57の4③) |
| **면제** | *"매출 대가의 반환 등에 관한 **税込 가액이 1만엔 미만인 경우** 교부 의무가 면제된다"*(消法57の4③, 消令70の9③二). **기한 없는 항구조치** |
| 판정 단위 | 세율별이 아니라 **청구·채권의 단위마다 감액한 금액**으로 판정한다(基通1-8-17 注: *"適用税率ごとの値引き等の金額により判定するものではなく"*) |
| 기재 5요건 | ①등록번호 ②반환일 **및 원거래일** ③원거래 내용(+경감대상인 취지) ④세율별 반환액 합계 ⑤세율별 소비세액 **또는** 적용세율 |
| 합본 교부 | 적격청구서와 적격반환청구서를 **한 장의 서류로 교부 가능**(問62) |

> ⚠️ **혼동 주의**: 매입측의 **少額特例**(税込 1만엔 미만 매입에 청구서 보존 불요, **2029-09-30 종료**)는 **별개 제도**다. 금액 기준이 같아 섞이기 쉽다. 위 반환 인보이스 면제는 매출측이고 **항구**다.

**설계 귀결**

- 소형 음식점 객단가 특성상 **대부분 1만엔 미만 → 교부 면제가 기본 경로**다. 그러나 **1만엔 이상 반품 경로는 구현해 두어야 한다**
- 기재 ②가 **원거래일**을 요구한다 → **로컬 원장에 원거래 참조 키가 필수**(§8.2 정정 링크와 동일 요구)
- 회계 확정 **전**의 값인하는 대가액에서 **직접 차감**, **후**는 **대가의 반환 등**으로 처리한다(問70). 다만 *"엄밀한 구분이 곤란한 경우에는 ①②의 어느 처리를 해도 무방"* → §8.7의 당일/전일 규칙에 법적 근거가 생겼다

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
| **전송 큐** | 멱등키 = 원장 행 PK. 4xx `parked` 격리 상태 포함. §8.6 |
| **결제 시도 이력** | `pending/unknown/succeeded/failed` 4상태 + 실징수액. §8.6 |
| **카탈로그 버전 pin** | 장바구니가 참조한 카탈로그 버전. §8.5 |

**거래 이력을 JSON 한 덩어리로 두면 안 된다.** kiosk는 "무슨 일이 있었나" 스냅샷이면 충분했지만, POS는 **일마감 집계·세율별 합계·결제수단별 합계·미전송 조회**를 로컬에서 해야 하므로 최소한 `거래 / 거래라인 / 결제 / 세금` 은 조회 가능한 컬럼으로 정규화해야 한다.

**보존 정책**도 새로 필요하다. 서버가 최종 원장이므로 로컬은 N일(예: 90일) 보관 후 정리하되, **미전송 건은 전송 성공 전까지 절대 삭제 금지**다. 다만 **전자장부보존법이 7년(최대 10년) 보존을 요구**하므로(§7.4), 로컬 90일 정리는 **서버가 법정 보존 주체임이 확인된 뒤에야 성립**한다 → §10 Q20.

#### 8.2.1 저장소 내구성 — 기본 설정이 곧 데이터 손실

**여기가 이 문서에서 가장 조용한 사고 지점이다.**

| 쟁점 | 내용 |
|---|---|
| 🔴 **`synchronous` 설정** | SQLite 공식 문서는 **WAL + `synchronous=NORMAL`이 "durable하지 않을 수 있다"**고 명시한다 — 전원 차단·시스템 크래시 시 **마지막 커밋이 롤백**된다. ACID를 얻으려면 **WAL + `synchronous=FULL`**. (앱 크래시에 대해서는 설정 무관하게 durable하다 — 문제는 정전이다) |
| 왜 위험한가 | 롤백된 것은 **현금 매출 몇 건**이고, **앱은 아무 이상 없어 보인다.** 마감 때 시재가 안 맞아야 비로소 발견된다 |
| 적용 방법 | sqflite `onConfigure`에서 설정. Android는 `execute`가 실패할 수 있어 `rawQuery('PRAGMA journal_mode=WAL')` 폴백이 공식 팁 |
| **플래시 powersafe overwrite** | SQLite 3.7.10+는 *"쓰기 범위 밖 바이트는 안 변한다"*를 **기본 참으로 가정**한다. 그런데 플래시에서 부분 섹터 쓰기 중 전원이 끊기면 ECC가 섹터를 못 살려 **쓰지도 않은 인접 바이트가 뭉개진다**. 의심되면 `file:db?psow=0` 보수 모드. ⚠️ **Sunmi eMMC 실측 필요 — 미확인** |
| fsync 거짓 보고 | SQLite는 OS·하드웨어가 거짓말하는지 **탐지할 방법이 없다.** 소비자용 플래시는 실제 기록 전에 sync 완료를 보고한다. 즉 FULL도 만능이 아니며, **최종 방어선은 "언제 죽어도 회수 가능한 구조"**(§8.6) |
| **저장공간 고갈** | 공간이 없으면 `SQLITE_FULL`로 **커밋 자체가 실패**한다(WAL은 checkpoint 전까지 계속 커진다). **반드시 catch해서 결제 진행 자체를 차단**할 것 — 안 하면 "완료 화면은 떴는데 원장에 없는 거래"가 생긴다. `StatFs`로 여유공간 주기 점검(경고 1GB / 위험 300MB), 위험 시 로그·이미지 캐시 자동 정리 |

#### 8.2.2 스키마 마이그레이션 — 미전송 원장이 남아 있을 때

앱을 업데이트하는데 서버로 못 보낸 현금 거래가 로컬에만 있는 상태다. 여기서 실수하면 **돈이 사라진다.**

- **파괴적 폴백 금지** — Room의 `fallbackToDestructiveMigration` 류는 마이그레이션 경로가 없을 때 **테이블 데이터를 영구 삭제**한다. 마이그레이션이 실패하면 **크래시가 낫다**(데이터는 살아있다)
- **직전 백업은 `VACUUM INTO`** — 단순 파일 복사는 WAL 때문에 손상된 사본을 만든다. 백업 성공을 확인한 뒤에만 진행
- **미전송이 있으면 강제 업데이트 보류** — Square도 *"SDK 또는 앱 버전을 업그레이드하기 전에 오프라인 결제 큐가 비었는지 확인하라"*고 명시한다(§8.11 업데이트 정책과 동일 게이트)
- **미전송 행은 전송할 원본 요청 JSON을 통째로 보관** — 컬럼을 재해석할 필요가 없어 스키마 변경에 불변이 된다

#### 8.2.3 `allowBackup=false` — 백업이 매출을 되살린다

Android Auto Backup이 켜져 있으면 **낡은 DB가 복원**될 수 있고, 그러면 **이미 전송 완료된 거래가 되살아나 중복 계상**된다. `allowBackup=false` 또는 DB 디렉터리 백업 제외가 필수다. 기기 교체 시의 데이터 이관은 §8.2.4의 명시적 경로로만 한다.

#### 8.2.4 기기 고장 시 미전송 회수 — 업계는 "회수"를 약속하지 않는다

Square는 오프라인 결제에 **기기당 24시간 / 1000건 한도, 72시간 후 만료**를 걸고, 로그아웃·앱 삭제·공장초기화 시 **영구 소실**이라고 못박으며, 개발자에게 대기 큐를 조회해 판매자에게 **경고할 것을 요구**한다. 즉 표준 대응은 회수 보장이 아니라 **체류 시간 최소화 + 상시 경고**다.

- 홈 화면에 **미전송 건수 + 최장 체류 시간** 상시 표시(§9.1 원칙 6), 임계 초과 시 마감 화면에서 경고
- 보조 회수 경로로 **"미전송 원장 내보내기(USB/SD)"** + 서버 재주입 엔드포인트를 초기 버전에 포함
- 서버가 **기기별 최종 동기화 시각**을 보유해 원격 감시(Fleet과 연계 가능)

#### 8.2.5 다중 단말 확장점 — 지금 심으면 비용 0

1차는 카운터 1대 전제지만(§11.1), 2대째가 추가될 때 깨지는 것은 **채번 충돌·현금 귀속·마감 주체**다. 스키마에 차원 하나만 미리 넣으면 나중에 변경이 없다.

- 로컬 채번을 **`{storeId}-{terminalId}-{businessDate}-{seq}`** 로 (지금은 `terminalId` 고정)
- 현금 원장·드로어 이력·마감 레코드의 키를 **(매장, 영업일, 단말)** 3키로
- **"매장 마감 = 단말별 마감의 합"** 으로 집계식을 정의

지금 컬럼 하나를 넣지 않으면, 2대째에서 **과거 데이터 전체 마이그레이션**이 필요해진다.

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
| **세액을 누가 계산하나** | ⚠️ **주문 등록 요청에 세금 필드가 없다.** 서버가 `orderType`으로 세율을 스스로 정한다. 반면 **적격간이청구서 요건상 세율별 세액을 영수증에 인쇄하는 것은 앱**이다(§7.2). → **앱이 인쇄한 세액과 서버 일마감 세액이 갈릴 수 있다.** 특히 주류(§7.3). 계산 규칙 합의가 필요하다 → §10 Q10·Q17 |
| **세율 스냅샷** | 가격(`itemPrice`/`inShopPrice`)은 요청에 실어 보내므로 거래 시점에 고정된다. 그러나 **세율은 서버가 수신 시점 규칙으로 계산**한다 → **오프라인 큐가 2027-04-01을 넘겨 전송되면 세율이 바뀔 수 있다** → §10 Q11 |
| **3세율 병존** | 1% / 8% / 10%가 한 영수증에 공존할 수 있다(§7.1). 세율별 소계 구조를 처음부터 만든다 |

#### 8.5.1 🔴 단수처리 — 법령이 정한 단위가 있다

> **2차 재검증 정정**: 1차 조사는 이 항목을 *"서버가 주문별로 절사하니 앱도 주문 단위로 맞춘다"*는 **서버-앱 정합성 문제**로 서술했다. 실제로는 **법령 준수 문제**이며, 단위도 "주문별 1회"가 아니다.

**정본 규칙 — 消費税法施行令 第70条の10 / 消費税法基本通達 1-8-15**

> 「…当該消費税額等の１円未満の端数処理は、**一の適格請求書につき、税率の異なるごとにそれぞれ１回**となることに留意する。
> **(注) 複数の商品の販売につき、一の適格請求書を交付する場合において、一の商品ごとに端数処理をした上でこれを合計した金額を適格請求書に記載すべき消費税額等とすることはできない。**」

인보이스 Q&A **問57**도 같은 취지를 반복한다.

> 「**（注）一の適格請求書に記載されている個々の商品ごとに消費税額等を計算し、１円未満の端数処理を行い、その合計額を消費税額等として記載することは認められません。**」

| 항목 | 확정 내용 |
|---|---|
| **단위** | **영수증 1장 × 세율마다 각 1회.** 8%와 10%가 섞인 영수증은 절사가 **2회**다("주문당 1회"가 아니다) |
| **라인별 절사 후 합산** | **명시적 금지.** 근거 3중(消令70の10 / 基通1-8-15 注 / Q&A問57) |
| 「1회」의 단위 | **기재요건을 충족하는 서류 1통.** 問67은 납품서에 세액을 기재하면 「納品書につき税率ごとに１回」이라 한다. POS는 1회계 = 1장이므로 실질적으로 일치 |
| 처리 방식 | **절사·올림·반올림 중 사업자 임의 선택**(問57: 「任意の方法とすることができます」) |
| 適格簡易請求書 | **동일 적용.** 消法57の4②五가 「前項第五号の規定に**準じて**計算した金額」으로 令70の10을 준용 |

> ⚠️ **미확인**: 한번 정한 단수처리 방식의 **継続適用을 요구하는 법령 조문은 확인하지 못했다.** 세무 해설 다수가 일관성을 권고하나 이는 실무 조언이며 법적 의무의 근거는 찾지 못했다.

**설계 귀결**

1. **라인 세액은 표시용으로도 저장하지 않는다.** 존재하면 언젠가 합산된다 — 금지된 계산의 원천을 아예 만들지 않는 것이 유일하게 안전한 설계다
2. 세액은 **`영수증 × 세율` 단위로 1회 산출**하고, 산출 결과를 **원장에 확정 저장**한다. 재발행 시 동일 결과가 나와야 하기 때문이다(마스터 세율이 나중에 바뀌어도 과거 영수증은 불변)
3. 단수처리 방식은 **매장 설정**으로 외부화하되 세율별로 동일 적용한다. **과거 거래는 재계산하지 않는다** — 일본 POS 업계(スマレジ·ユビレジ)가 정확히 이 구조이며, ユビレジ는 *"설정 변경 후에도 과거 회계가 재계산되는 일은 없습니다"*라고 명시한다

#### 8.5.2 계산 경로가 2개다 — 영수증용과 신고용

같은 "소비세액"이라도 **산출식이 다르다.** 세율을 단일 상수로 두면 이 구분을 표현할 수 없다.

| 용도 | 산출식 |
|---|---|
| **영수증 기재용** (令70の10二) | `세율별 税込합계 × 10/110` (경감은 `× 8/108`) → 1엔 미만 단수처리 1회 |
| **신고 — 割戻し計算**(원칙) | `세율별 税込합계 × 100/110(100/108)` = 課税標準額(**1,000엔 미만 절사**) → `× 7.8%`(경감 `6.24%`) |
| **신고 — 積上げ計算**(특례) | `Σ 교부한 영수증의 세액 × 78/100`. 단 **매출을 積上げ로 하면 매입도 積上げ 강제** |

**→ 세율은 상수 3종이 아니라 `{표시세율, 내세역산분수, 국세율}` 세트이고, 여기에 적용개시일이 붙는다.**

```
TaxRate {
  effectiveFrom: Date        // 2019-10-01 / 2027-04-01 / 2029-04-01
  category:      Standard | Reduced
  displayRate:   10% | 8% | 1%      // 영수증·화면 표시
  inclusiveFrac: 10/110 | 8/108 | 1/101   // 내세 역산 (1% 값은 법안 미성립 — 확정 커밋 금지)
  nationalRate:  7.8% | 6.24% | ?          // 신고용
}
```

이 테이블을 **서버 배포 가능한 데이터**로 두면 2027-04 인하와 2029-04 원복 두 번을 앱 재배포 없이 넘긴다(§7.1).

#### 8.5.3 할인 안분 — 공식 규칙이 있다

1차 조사는 *"나머지 1엔을 어디에 붙일지 규칙이 필요"*로 열어두었다. Q&A **問69**에 원칙이 있다.

> 「…**割引券等による値引額をその資産の譲渡等に係る価額の比率によりあん分し、適用税率ごとの値引額を区分し、**値引き後の税抜価額又は税込価額を税率ごとに区分して合計した金額を算出することとされています。」
> 「…**領収書等の書類により適用税率ごとの値引額又は値引き後の…金額が確認できるときは、…適用税率ごとに合理的に区分されているものに該当する**こととされています。」

국세청 예시: 雑貨 3,300(10%) + 牛肉 2,160(8%), 할인 1,000 → `10%: 1,000×3,300/5,460 ≒ 604`, `8%: 1,000×2,160/5,460 ≒ 396`.

| 항목 | 확정 내용 |
|---|---|
| 원칙 | **가액비 안분** |
| 완화 | **세율별 할인액이 영수증에서 확인되면** 임의 배분도 「합리적 구분」에 해당한다. 원문은 *"경감세율 대상이 아닌 것에서만 값인하해도"* 인정된다고 명시 |
| 세액 산출 | **할인 후** 세율별 합계에서 계산한다 |

> ⚠️ **미확인**: 안분 시 **1엔 미만 잔여를 어느 세율에 귀속시킬지의 규정은 없다**(예시가 604+396=1,000으로 맞아떨어질 뿐이다).

**설계 귀결** — 할인은 반드시 **세율별로 분해해 원장에 저장**하고, 잔여 1엔은 한쪽에 몰되 불변식 **`Σ 세율별 할인액 = 총 할인액`** 을 테스트로 고정한다(§11.3). 표시 방식은 "할인 후 세율별 합계"와 "할인 전 합계 + 세율별 할인액" 둘 다 적법하므로 인쇄 레이아웃 선택지가 된다.

#### 8.5.4 취식/포장 가격은 계산으로 유도하지 않는다

일본 POS 업계 관행 확인 결과, **Airレジ는 内税일 때 취식용과 포장용의 税込価格을 각각 따로 등록**하게 한다(세율 선택지에 「注文時に選択」이 있고, 그때 *"標準税率と軽減税率それぞれの場合の税込価格を指定できます"*). 세율을 곱해 유도하지 않는다는 뜻이다.

이유는 総額表示와 맞물린다 — 내세 정본에서는 **표시가격이 딱 떨어지는 값이어야** 하고, 세율에서 역산하면 취식가가 어중간해진다. ユビレジ도 *"상품 가격을 税込으로 설정한 경우 단수처리 설정과 무관하게 합계 금액은 변하지 않습니다"*라고 한다 — **내세 정본이면 단수 정책이 총액을 흔들지 않는다**는 뜻이며, 이 앱의 전제와 정확히 부합한다.

→ **검증 항목**: §2.5의 `inShopPrice`(취식 가산액) 모델이 "취식·포장 각각 딱 떨어지는 税込価格"을 표현할 수 있는지 확인해야 한다. 가산 방식이라도 가산액을 조정하면 표현은 가능하지만, **가격 등록 UI가 두 값을 각각 보여주는지**가 실무 품질을 가른다.

#### 8.5.5 카탈로그 버전 pin

가격은 요청에 실어 보내므로 **완료된 거래**는 고정된다. 그러나 **진행 중인 장바구니**는 다르다 — 백그라운드 동기화가 카탈로그를 갈아끼우면 담아둔 상품의 가격·세율이 바뀔 수 있다.

Square Orders API가 이 문제의 레퍼런스다. 주문 생성 시점에 카탈로그 스냅샷을 취하고 라인아이템에 `catalog_version`을 기록해, 이후 가격이 바뀌어도 **그 주문은 원래 가격으로 계산**된다.

- 라인아이템에 **`unitPrice` · `taxRate` · `catalogVersion`을 참조가 아니라 값으로 복사 저장**
- **카탈로그 스왑은 장바구니가 빈 상태에서만** 수행
- 서버는 카탈로그를 `(catalogVersion, validFrom)` 단위로 배포

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

kiosk의 `pending_payments` 테이블이 정확히 ①의 자리인데 **호출부가 없다.** POS에서는 반드시 실제로 동작해야 한다. 더구나 이식 대상 코드는 취소 폴링 타임아웃 시 **체크아웃을 최종 상태 미확정인 채 버린다**(§4의 결함) — 그대로 옮기면 ①이 재현된다.

전원 차단이 잦은 매장 환경이므로 **로컬 쓰기는 트랜잭션으로 묶고, "결제 시도 중" 레코드는 Square 호출 이전에 커밋**한다.

#### 8.6.1 🔴 결제 상태를 2상태로 모델링하면 안 된다

`성공 / 실패`만 있으면 **"모른다"를 표현할 수 없고**, 모르는 것을 실패로 접는 순간 **손님은 결제됐는데 매출 기록 없이 재결제를 요구받는다 — 이중과금**이다.

Square는 이 상태를 위한 전용 엔드포인트를 따로 둔다: **`CancelPaymentByIdempotencyKey`** — *"요청의 상태를 모를 때(예: 요청 후 네트워크 에러로 응답을 못 받음)"* 사용하며, 해당 키의 결제가 없으면 no-op로 성공을 반환한다. 즉 **불명 상태의 존재를 API 설계가 인정하고 있다.**

| 상태 | 의미 | 해소 방법 |
|---|---|---|
| `pending` | 요청 전송, 진행 중 | 폴링 |
| **`unknown`** | **결과 미확인** (타임아웃·크래시·네트워크 단절) | `GetPayment` 조회 또는 `CancelPaymentByIdempotencyKey`. **자동으로 어느 쪽으로도 접지 않는다** |
| `succeeded` | 승인 확정 | — |
| `failed` | 실패 확정 | — |

- **실징수액을 별도 필드로** 보유한다 — `COMPLETED`여도 팁 등으로 요청액과 다를 수 있다(§6.3)
- **기동 시 `SearchTerminalCheckouts` 정합화**로 `unknown`을 일괄 해소한다
- **재결제 금지** — 반드시 조회로 확정한 뒤 금액을 대조한다

#### 8.6.2 멱등키는 "전송 시점"이 아니라 "원장 커밋 시점"에 만든다

전송할 때 키를 생성하면 **앱이 재시작된 뒤 새 키가 나와 같은 거래가 두 번 등록**된다.

- **로컬 원장 행의 PK(UUIDv4)를 그대로 멱등키로** 삼고, 거래와 **같은 트랜잭션에 커밋**한다. 이후 모든 재시도가 이 키를 재사용한다
- 키는 **충분한 엔트로피의 랜덤 문자열**이며 **민감정보를 넣지 않는다**(Stripe 권고)
- ⚠️ **멱등키의 서버 보관 기간은 유한하다** — Stripe는 **24시간 후 삭제 가능**을 명시한다. Square는 **문서에 명시가 없다(미확인)**. 오프라인 큐가 24시간을 넘기면 멱등 보호가 사라질 수 있으므로 **`externalOrderNo` UNIQUE 제약이 2차 방어선**이어야 한다 → §10 Q4

#### 8.6.3 🔴 전송 큐의 head-of-line blocking

**한 건이 큐를 막으면 그날 매출 전체가 안 올라간다.**

서버가 400을 반환하는 거래(검증 실패 등)는 몇 번을 재시도해도 성공하지 못한다. 그 건이 큐 선두에 박혀 있고 전송이 순서대로만 진행되면, **뒤의 모든 현금 매출이 서버에 도달하지 못한 채 쌓인다.** 점주는 마감할 때 비로소 알게 된다 — 그리고 그때는 §8.3의 "미전송 0 게이트"에 걸려 마감을 못 한다.

| 규칙 | 내용 |
|---|---|
| **전역 FIFO 금지** | 순서 보장은 **같은 주문 내부**(생성 → 취소/환불)에서만. 주문 간에는 병렬 전송 |
| **4xx는 재시도 0회** | 즉시 `parked`로 격리하고 화면에 배너로 노출한다. 재시도해도 성공하지 않는 것을 큐에 남겨두지 않는다 |
| **5xx·네트워크만 재시도** | **full jitter** 백오프 — `sleep = random(0, min(cap, base·2ⁿ))`. 지터 없는 지수 백오프는 네트워크 복구 순간 전 기기가 동시에 몰린다 |
| 격리된 건 | 사람이 처리해야 한다. 목록·사유·재시도 버튼을 마감 화면에서 제공 |

#### 8.6.4 이중 제출 3중 방어

버튼 디바운스만으로는 **"결제 중 방치했다가 다시 탭"** 을 막지 못한다.

1. 결제 시작과 동시에 **화면 전체 잠금**(뒤로가기·홈 포함)
2. 주문당 결제 시도를 **상태 머신 전이로만** 허용 — 중복 호출은 no-op
3. **멱등키를 결제 시도 행 생성 시점에 DB 커밋**(§8.6.2와 동일 키)

클라이언트 방어는 필요조건일 뿐이고, **실제 해결책은 서버 멱등성**이라는 것이 업계의 일치된 결론이다.

### 8.7 거래 생애주기와 정정

POS는 판매 후에 손대는 일이 많다. 기존 두 앱에는 없는 개념들:

- 🔴 **Void(결제 전 취소)와 Refund(결제 후 환불)를 분리한다** — 1차 조사는 이 둘을 "취소"로 뭉뚱그렸다. 업계 표준은 별개 처리이고 회계상 의미도 다르다. Void는 결제가 확정(정산)되기 전 취소라 카드사에 청구가 아예 발생하지 않고, Refund는 확정된 결제를 사후에 되돌리는 별도 거래다. **권한 게이트와 리포트 집계가 둘을 구분해야** 부정 탐지가 가능하다(§8.9)
- **당일 취소 vs 전일 취소(반품)** — 전일 건은 이미 마감된 영업일에 속하므로 당일 매출에 마이너스로 잡을지, 원 영업일을 정정할지 규칙이 필요. **법적 근거는 問70에 있다**(§7.5) — 회계 확정 **전**의 값인하는 대가액 직접 차감, **후**는 대가의 반환 등. 다만 *"엄밀한 구분이 곤란하면 어느 쪽으로 처리해도 무방"*이므로, **앱은 "회계 확정 시점"을 기준으로 단순하게 가르면 된다**
- **반품에는 법정 문서가 따라온다** — 適格返還請求書(§7.5). 税込 1만엔 미만은 교부 면제(항구조치)라 소형 음식점은 대부분 면제 경로지만, **1만엔 이상 경로와 원거래일 보존은 구현해야 한다**
- **부분 취소** — 서버 `payInfos[]`는 결제 건별 매칭을 지원하지만(§2.3), 라인 단위 부분 취소를 어떻게 표현할지 확인 필요
- 🔴 **환불 불가 수단은 조사 항목이 아니라 설계 필수 분기다** — **交通系IC는 Square가 환불을 거부하고**(`REFUND_DECLINED`), **e-money는 오류 후 `CancelTerminalCheckout`도 미지원**이라 손님이 단말에서 직접 취소해야 한다(§6.6). 즉 **환불 UX가 결제수단별로 갈린다.** 실무는 **현금으로 대신 환불**하는데, 이것을 서버에 어떻게 기록할지 정해야 한다 → §10 Q12. UI는 결제수단을 보고 **가능한 환불 경로만 제시**해야 하며, 환불 버튼을 눌러보고 실패를 알게 하면 안 된다
- **정정은 삭제가 아니다** — 세법·전자장부보존법 관점에서 원거래를 지우면 안 되고 **취소 거래를 추가**해야 한다. 로컬 스키마가 이 관계를 표현해야 한다(§8.2 정정 링크)

### 8.8 영수증 발행

- **채번**: 서버 `shopOrderNo`는 등록 **응답**으로 온다 → 오프라인에는 없다. **영수증에 찍을 번호를 로컬에서 먼저 채번**하고(`displayOrderNo`), 나중에 서버 번호와 대응시켜야 한다. 채번 키는 §8.2.5의 **`{storeId}-{terminalId}-{businessDate}-{seq}`**. kiosk의 로컬 채번이 출발점이지만 그것은 **대기표 번호**라 전표 무결성 요구가 없다 — 반례로만 참고할 것(§4)
- 🔴 **결번을 만들지 않는다(gapless numbering)** — 취소된 거래도 **번호를 스킵하지 않고 상태 플래그로 보존**한다. 결번이 있으면 세무 감사에서 그것이 정당한 취소인지, 기술적 실패인지, **고의적 매출 누락인지 구분할 수 없다.** 표준 구현은 **문서 생성이 실제로 성공했을 때만 번호를 부여**해 결번 자체를 예방하는 것이다. ⚠️ **미확인**: 이것이 일본 국세당국의 명문 요건인지는 확인하지 못했다 — **감사 방어 모범관행**으로 채택하는 것이며 일본 고유 법령으로 단정하지 말 것
- **재발행** — 횟수 이력 필요. 재발행본에는 **「再発行」 명기**
- 🔴 **領収書와 레시트는 동시에 주지 않는다** — 둘 다 건네면 **이중발행**이 된다. 일본 실무 규범은 **領収書 발행 시 레시트를 회수해 점포 보관**하고, 재발행 시에는 **원본 회수 + 「再発行」 명기**, **宛名·但し書き 공란 금지**다. → UI에서 領収書를 "추가 출력"이 아니라 **발행 상태를 전환하는 액션**으로 만들어 구조적으로 막는다(§9.4)
- **領収書(료슈쇼)** — 宛名·但し書き 입력 UI + 발행 이력. 5만엔 이상 인지세 안내(§7.4). 출력 구현체는 `kiosk_v3_japan`에 있다(§4)
- **적격간이청구서 5요건**을 레이아웃에 고정하고 **인쇄 실패 시 거래를 막는 하드 검증**으로 둔다(§7.2). 등록번호는 §3 ② 경로로 주입하며 **미등록 매장은 인쇄 금지**
- **반품 시에는 適格返還請求書 레이아웃**이 별도로 필요하다(§7.5) — 원거래일 포함. 적격청구서와 **한 장으로 합본 교부도 가능**

### 8.9 담당자·권한

- 기존 두 앱은 **단일 로그인, 담당자 개념 없음**. POS는 최소한 **누가 팔았고 누가 취소·출금했는지**를 남겨야 현금 과부족을 추적할 수 있다
- 취소·출금·마감 같은 행위에 **관리자 승인(PIN)** 을 걸지 여부는 매장 규모에 따라 결정. 1차에서는 "담당자 식별 + 이벤트 기록"까지만 해도 충분할 수 있다

**업계의 PIN 게이트 관행** — 전부 걸면 피크타임이 막히고, 안 걸면 통제가 없다. 표준은 **금액·수량 임계로 가르는 것**이다: 소액·소량(예: 일정 금액 또는 1품목 이하)은 직원 단독 처리, 그 이상만 **개인별 매니저 PIN**. 그리고 **PIN 공유는 통제를 무력화하므로 금지**한다 — 공유된 PIN은 "누가 했는지"를 기록하지 못해 §8.9의 목적 자체가 사라진다.

**부정·오류 지표는 절대 임계가 아니라 상대 임계로** — 업계의 예외 기반 리포팅(EBR)이 대상으로 삼는 것은 void·refund, 할인, **no-sale 드로어 개방**, 취소, 매니저 오버라이드다. 핵심은 절대 건수가 아니라 **동료 대비 배수**다("void 1건은 무의미하지만 동료 평균의 3배인 캐셔는 신호"). 따라서 X/Z 리포트 하단에 담당자별 **(취소율 · no-sale/시간 · 할인 적용률 · 현금 과부족)** 을 **중앙값 대비 배수**로 표시한다.

> **1차 범위 판단**: 단일 카운터 단계에서는 비교 대상이 없으므로 **알림 없이 기록만 남긴다.** 지표를 산출할 수 있는 이벤트 스키마만 갖춰두면 다인 매장에서 리포트만 추가하면 된다.

**No-sale(판매 없는 드로어 개방)은 별도 리포트로 집계한다** — 판매 없이 서랍을 여는 것은 절도(잔돈 유용, 환불 조작 위장)의 전형적 은폐 수단이라, 표준 POS는 이벤트마다 **사유 입력을 요구하고 별도 리포트로 집계**하며 과다 발생 시 알린다. §8.4의 "드로어 개폐 이력"을 단순 로그가 아니라 **조회 가능한 리포트 대상**으로 설계해야 하는 이유다.

### 8.10 시각 신뢰

**영업일 판정과 세율 적용일이 모두 기기 시각에 의존한다.** 2027-04-01 세율 전환이 기기 시각으로 갈리면 사고가 난다.

- Sunmi 단말의 시각 드리프트, 점원의 수동 변경 가능성을 전제한다
- 서버 응답 시각과 기기 시각의 차이를 감시하고, 임계 초과 시 경고 또는 판매 차단
- `appfit_order_agent`에 `windows_timezone_service.dart`가 있으나 Windows 전용이라 Android용은 새로 필요

**wall clock과 monotonic clock을 구분한다.** `System.currentTimeMillis()`는 사용자·통신사가 바꿀 수 있어 앞뒤로 점프하며, Android 공식 문서가 **경과시간 측정에 쓰지 말라**고 명시한다. 재시도 백오프·타임아웃·프린터 대기 같은 **모든 경과시간은 `SystemClock.elapsedRealtime()`**(단조 보장, deep sleep 포함)으로 잰다. wall clock 기반 타이머는 점원이 시계를 되돌리는 순간 **무한 대기하거나 즉시 폭주**한다.

**원장에는 세 가지를 함께 기록한다.**

| 필드 | 용도 |
|---|---|
| `orderedAt` (wall) | 서버 전송·영업일 귀속 |
| **서버-기기 오프셋** | 동기화 시점에 측정한 델타. 사후에 기기 시각이 틀렸음을 알아낼 수 있는 유일한 단서 |
| **`bootId` + `elapsedRealtime`** | 재부팅 경계 식별(`elapsedRealtime`은 부팅 기준이라 재부팅 시 리셋된다) |

세율 전환일(2027-04-01 / 2029-04-01)과 영업일 판정이 모두 기기 시각에 걸려 있으므로, **오프셋이 임계를 넘으면 판매를 차단**하는 편이 잘못된 세율로 파는 것보다 낫다.

### 8.11 하드웨어 장애 시 판매 지속 정책

- **프린터 용지 소진 / 커버 열림 상태에서 판매를 계속할 것인가.** 결제는 이미 승인됐는데 영수증만 못 나오는 상황이 실제로 발생한다 → 판매는 성립시키고 **영수증을 미출력 큐에 넣어 복구 후 재출력**하는 것이 기존 `output_queue_service`(§4)의 사고방식과 일치. 업계 문서 어디에도 "프린터 장애 시 판매 중단" 권고는 없고, **거래 이력에서 언제든 재출력** 가능한 경로 제공이 표준이다
- **원칙: "결제 성공 = 로컬 원장 커밋"을 인쇄와 완전히 분리한다.** 인쇄는 별도 큐로 처리해 **프린터 장애가 판매를 절대 막지 않게** 한다. 미출력 거래는 "영수증 대기" 배지 + 복구 시 자동 재출력
- 드로어가 안 열릴 때의 대체 동선
- Square Terminal 연결 끊김 시 현금 결제로 폴백하는 동선

#### 8.11.1 장시간 구동

POS는 하루 12~16시간 재시작 없이 돈다. 이 조건에서만 드러나는 문제가 있다.

- **Android 14+ FGS 규칙** — 포그라운드 서비스는 `foregroundServiceType` 선언 + 대응 권한이 **필수**이며 누락하면 예외로 죽는다. 동기화 릴레이는 `dataSync` 타입 + 배터리 최적화 예외(전용 단말이므로 정당)
- **Impeller 메모리 증가** — Flutter에서 **Impeller 활성 시 그래픽 메모리가 계속 증가해 OOM으로 죽는 이슈**가 보고돼 있다. 이 앱은 이미 "매니페스트 값과 런타임 실제 동작이 다를 수 있다"는 실측 이력이 있으므로(T2mini_s), **렌더러 설정을 실기기에서 확인**해야 한다
- 미해제 스트림 구독·컨트롤러, 이미지 캐시가 전형적 누수 지점
- **진짜 방어는 FGS가 아니다** — OEM별 프로세스 kill은 통제 불가다. **"언제 죽어도 원장은 온전하고, 재시작 시 큐가 자동 재개된다"**가 본질이고 FGS는 보조다. 영업 종료 후 **야간 자동 재시작** 스케줄 + 메모리 상시 계측을 둔다

#### 8.11.2 영업 중 강제 업데이트 — 피크타임에 판매를 막지 않는다

앱 업데이트가 피크타임에 화면을 덮으면 그 자체가 장애다. 그렇다고 미루기만 하면 결함이 남는다.

**핵심은 다운로드와 적용을 분리하는 것이다.**

| 단계 | 정책 |
|---|---|
| 다운로드 | 언제든(백그라운드) |
| **적용** | **마감(드로어 클로징) 직후 또는 다음 콜드스타트에만** |
| 차단형(즉시) 적용 | 결제 정합성·보안 결함 등급에서만. 그마저 **"장바구니 빔 + 미정산 Terminal checkout 0 + 미전송 0"** 게이트 통과 시에만 발동 |
| 롤백 | **직전 정상 버전 아티팩트를 상시 보관**해 원클릭 롤백 채널 유지 |

미전송 게이트는 §8.2.2(스키마 마이그레이션)와 같은 조건이다 — Square도 *"업그레이드 전에 오프라인 결제 큐가 비었는지 확인하라"*고 명시한다. 관리형 단말이면 Android Enterprise의 **유지보수 창(maintenance window)** 과 **freeze period**(최대 90일)로 배포 시각 자체를 통제할 수도 있다.

### 8.12 로컬 보안

**카드 PAN은 애초에 앱에 들어오지 않는다** — Square Terminal이 처리한다(§6.7). 따라서 보호 대상은 두 가지로 좁혀진다.

| 대상 | 방침 |
|---|---|
| **API 액세스 토큰** | **Android Keystore 기반 보안 저장소 필수.** 평문 저장은 도난 단말로 서버 매장 데이터를 조작당하는 경로가 된다. 애초에 장기 토큰을 기기에 두지 않는 것이 우선(§3) |
| **매출 원장 DB** | 개인정보·거래정보를 담는다. SQLCipher(AES-256 전체 DB 암호화) + Keystore 키 보관이 표준 구성이나 **쿼리 성능 오버헤드가 있다** |

> ⚠️ **미확인**: sqflite + SQLCipher 조합의 Sunmi 단말 실사용 성능 자료를 찾지 못했다. **성능 실측 후 판정**한다. 마감 집계처럼 로컬 전체 스캔이 필요한 쿼리(§8.3)가 병목이 될 수 있다.

### 8.13 신규 설계 항목 체크리스트

| # | 항목 | 기존 자산 | 신규 난이도 |
|---|---|---|---|
| 1 | 오프라인 완결 판매 + 수렴 | 재시도 큐만 있음 | **높음** |
| 2 | 로컬 원장 정규화 스키마 | JSON 스냅샷뿐 | 중 |
| 3 | 영업일·마감 + 미전송 게이트 | 없음 | **높음** |
| 4 | 현금 관리(준비금·거스름돈·권종계수·과부족) | 없음 | 중 |
| 5 | 금액·세액 결정론(**영수증×세율 1회 절사**·안분·3세율·2계산경로) | 없음 | **높음** |
| 6 | 3단계 원자성·크래시 복구 | `pending_payments` 껍데기 | **높음** |
| 7 | 취소/반품/부분환불·정정 링크 + **Void/Refund 분리** | 단순 취소만 | 중 |
| 8 | 로컬 채번 + 서버번호 대응 + **gapless** | kiosk 로컬 채번(대기표라 반례) | 낮음 |
| 9 | 영수증 재발행·**領収書 배타 발행** 이력 | 출력 구현은 있음 | 낮음 |
| 10 | 담당자·권한 + **PIN 임계 정책** | 없음 | 낮음 |
| 11 | 시각 신뢰 + **monotonic clock 분리** | Windows 전용만 | 중 |
| 12 | 하드웨어 장애 시 판매 지속 | 출력 큐 사고방식 재사용 | 낮음 |
| **13** | **저장소 내구성**(WAL+FULL·psow·`SQLITE_FULL` 차단) — §8.2.1 | 없음 | 중 |
| **14** | **스키마 마이그레이션 안전성**(비파괴·`VACUUM INTO`·미전송 게이트·`allowBackup=false`) — §8.2.2~3 | 없음 | 중 |
| **15** | **전송 큐 격리·멱등성**(4xx parked·full jitter·원장 PK 멱등키) — §8.6.2~3 | 재시도 큐만 있음 | **높음** |
| **16** | **결제 4상태 + `SearchTerminalCheckouts` 정합화** — §8.6.1 | ❌ 이식 코드에 **결함 있음**(§4) | **높음** |
| **17** | **카탈로그 버전 pin** — §8.5.5 | 없음 | 낮음 |
| **18** | **업데이트 적용 정책**(다운로드/적용 분리·롤백) — §8.11.2 | OTA 채널은 있음 | 낮음 |
| **19** | **로컬 보안**(Keystore 토큰·DB 암호화 판정) — §8.12 | 없음 | 중 |
| **20** | **適格返還請求書**(반품 문서·원거래일 보존) — §7.5 | 없음 | 중 |
| **21** | **스캐너 브로드캐스트 입력** — §5.1 | 인텐트 모달 방식만 | 낮음 |
| **22** | **다중 단말 확장점**(3키 스키마) — §8.2.5 | 없음 | 낮음(**지금 하면**) |

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

**현금은 여전히 40%다.** 2025년 캐시리스 비율은 58.0%(경산성)로, 뒤집으면 현금 결제가 40%대라는 뜻이다. **현금 처리 품질이 곧 제품 품질**이며 이 동선이 1차의 핵심이다.

- 받은 금액 **프리셋 버튼**(`¥1,000` / `¥5,000` / `¥10,000` / `ちょうど`)을 먼저, 키패드는 그 아래
- 키패드는 **`NumericKeypadWidget` 재사용**(§9.6)
- **거스름돈을 화면에서 가장 크게** — 계산 실수가 곧 현금 과부족(§8.4)이다
- 드로어는 현금 거래 시 자동 개방, 그 외 **수동 + 사유 선택**(no-sale은 별도 리포트 대상, §8.9)

**마감 실사 UI — 권종별 계수**

표준 방식은 고액권부터 저액권까지 **권종별 개수를 입력 → 액면을 곱해 합산 → 시스템 기대값과 대조**해 과부족을 산출하는 것이다.

- 釣銭準備金 기본값 **100,000엔**(개업 기준. 레지 1대당 5만엔 운용 사례도 흔하다) — 편집 가능
- 은행 양환이 **50매 단위**라 금종 구성이 실무 제약이 된다
- **세포함가를 10엔 단위로 설계하면 1엔·5엔은 원칙적으로 불필요** → 권종 입력에서 **1엔·5엔은 기본 접힘**으로 두어 입력 항목을 줄인다

#### (4) 영수증 동선 — 🔴 배타 발행

> **2차 재검증 정정**: 1차 조사는 *"レシート는 기본 출력, 領収書는 요청 시 **별도** 발행"*이라 적었다. **그대로 만들면 이중발행이 된다.**

일본 실무 규범은 **둘을 동시에 건네지 않는 것**이다. 領収書를 발행하면 **레시트는 회수해 점포가 보관**한다. 같은 거래에 대해 두 장의 지불 증빙이 밖으로 나가면 안 되기 때문이다.

- 「領収書発行」을 **"추가 출력"이 아니라 발행 상태를 전환하는 액션**으로 구현해 **동시 출력을 구조적으로 차단**한다
- 領収書 선택 시 **宛名·但し書き 입력은 필수**(공란 금지)
- 재발행은 **원본 회수 + 「再発行」 각인 + 감사 로그**
- 5만엔 이상은 인지세 안내를 띄운다(§7.4)
- 반품 시에는 **適格返還請求書** 경로가 따로 있다(§7.5)

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

**법적 근거 정리** — 일본 소매·음식점 POS에 **직접 적용되는 법정 접근성 기술기준은 없다**(확정). 참고 규격으로 JIS X 8341-5(사무기기)가 있으나 카운터 POS 앱에 강제되지 않는다. 다만 **2024-04-01 개정 障害者差別解消法**으로 모든 민간사업자(개인사업주 포함)에게 **合理的配慮 제공이 노력의무 → 법적 의무**로 바뀌었다. 이는 기술 규격이 아니라 **"요청이 있고 과중한 부담이 아니면 대응한다"는 절차적 의무**다.

→ **인증·감사 대응 기능은 만들지 않는다.** 위 표의 방침(대비 4.5:1, 터치 타겟, textScaler clamp)은 규정 준수가 아니라 **카운터 사용성**을 근거로 채택한 것이며, 여기에 실질 배려 3가지를 더한다: **① 손님용 합계·거스름돈 대형 표시 ② 색만으로 상태를 구분하지 않기 ③ 합계·거스름돈을 점원이 구두로 읽을 수 있게 상단 고정.**

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
| **전송 큐 head-of-line blocking** — 400 한 건이 하루 매출 전체를 막음 | 전역 FIFO 금지, 4xx는 `parked` 격리, 5xx만 full jitter 재시도 (§8.6.3) |
| **결제 결과 불명(`unknown`)을 표현할 수 없음** | 4상태 모델 + `SearchTerminalCheckouts` 기동 정합화. 재결제 금지 (§8.6.1) |
| **`synchronous=NORMAL`의 조용한 데이터 손실** | 금전 DB는 WAL + `synchronous=FULL`. `SQLITE_FULL`은 catch해 결제 차단 (§8.2.1) |
| **미전송 원장이 있는 상태의 스키마 마이그레이션** | 비파괴 + `VACUUM INTO` 백업 + 미전송 시 업데이트 보류 + 원본 요청 JSON 보관 (§8.2.2) |
| **Android Auto Backup이 전송 완료 거래를 되살림** | `allowBackup=false` + 명시적 내보내기 경로 (§8.2.3~4) |
| **액세스 토큰 기기 저장 위험** | 장기 토큰은 서버 보관, 기기엔 단기 세션 토큰. 부득이하면 Keystore (§3·§8.12) |
| **전표 결번(gapless numbering)** | 취소도 번호 유지 + 상태 플래그. 생성 성공 시에만 채번 (§8.8) |
| **領収書·레시트 이중발행** | 배타 발행 — 領収書 발행 시 레시트 회수 (§8.8·§9.4) |
| **適格返還請求書 미고려** | 1만엔 미만은 교부 면제(항구)이나 1만엔 이상 경로 + 원거래일 보존 필요 (§7.5) |
| **다중 단말 추가 시 채번·시재 귀속 붕괴** | 지금 `{store}-{terminal}-{date}-{seq}` + 3키 스키마로 확장점 확보 (§8.2.5) |
| **스캐너가 모달 인텐트라 상시 스캔 불가** | 브로드캐스트 수신 1차 + HID 폴백 (§5.1) |

### 10.2 확인 질문

| # | 대상 | 질문 |
|---|---|---|
| 1 | 백엔드 | **2027-04 세율 개정 대응 계획.** `sales-closing`의 취식10/포장8 고정 규칙, 1%/8%/10% 병존, 적용시작일 파라미터화 **[최우선]** |
| 2 | 백엔드 | **품목별 세율 구분** — 포장 주류 10% 처리 계획. 경감세율 대상은 「주류·외식을 제외한 음식료품」이므로 **주문유형만으로 세율을 정하면 구조적으로 틀린다**. 더불어 경감대상 여부는 상품 속성이 아니라 **`상품 × 제공형태`의 함수**여야 한다(§7.1) **[세무 리스크]** |
| 3 | 백엔드 | **§3 ② 신규 API 3종** — 세율 테이블 / 적격청구서 등록번호 / 매장별 결제단말 설정. 우선순위와 일정 |
| 4 | 백엔드 | `WALD_POS`가 `externalOrderNo` **유일성 대상 외부사**에 포함되는가. 미포함이면 오프라인 재전송이 중복 주문을 만든다 |
| 5 | 백엔드 | Ex 카탈로그(`/v0/shops/{shopCode}/categories/items`)에 `inShopPrice` 추가 가능한가 |
| 6 | 백엔드 | `sales-closing`이 취소·부분취소·환불을 어떻게 반영하는가 (交通系IC 환불 불가 건 포함) |
| 7 | 개발 | `kiosk_v4_japan` 레포 접근 — Square 구현이 v3 대비 얼마나 진화했는지 |
| 8 | 사업 | Square vs GMO A35 결정 근거. 매장별 Square 계정 개설 주체, e-money/QR 가맹점 승인 절차 담당 |
| 9 | 사업 | 대상 브랜드·파일럿 매장. D3 MINI 신규 도입인지 기존 재사용인지, **프린터 변형(58 vs 80mm)** — 고객 디스플레이 기능 가부가 갈린다 |
| 10 | 백엔드 | **세액 계산 규칙의 정확한 정의.** 주문 등록 요청에 세금 필드가 없어 서버가 자체 계산하는데, 영수증에 세액을 인쇄하는 것은 앱이다. 세율별 소계 산출식·할인이 있을 때의 과세표준(**할인 후** 세율별 합계에서 산출, 안분은 가액비 원칙 — Q&A問69)을 명문화해야 **영수증 세액과 일마감 세액이 일치**한다 (§8.5) |
| 11 | 백엔드 | **오프라인 큐가 세율 전환일을 넘겨 전송될 때 어느 세율이 적용되는가** — `orderedAt` 기준인가 수신 시각 기준인가. 2027-04-01 전후 며칠간 실제로 발생한다 (§8.5) |
| 12 | 백엔드 | **환불 불가 수단의 대체 환불 기록 방법.** 交通系IC 결제를 현금으로 환불했을 때 `payInfos[]`에 어떻게 표현하는가 (§8.7) |
| 13 | 백엔드 | **라인 단위 부분 취소** 지원 여부. `payInfos[]`는 결제 건별 매칭인데 상품 단위 반품을 어떻게 보내는가 (§8.7) |
| 14 | 기획/디자인 | **상품 타일에 이미지를 쓸 것인가.** 서버가 `imageUrls`/`thumbnailImageUrl`을 주지만(§2.4), 이미지를 쓰면 타일이 커져 한 화면 상품 수가 줄고 텍스트+색상칩은 밀도가 오른다 (§9.9) |
| 15 | 개발/기획 | **폰트 번들 용량 상한.** Noto Sans JP는 서브셋팅이 불가해 전체 한자 세트가 필요하고 APK가 10MB 이상 늘어난다 (§9.7) |
| 16 | 사업/개발 | **고객 디스플레이 활용 범위.** 58mm 변형은 2.4" 7세그먼트(숫자 전용)라 금액만 표시 가능하다 — 도입 기종이 정해져야 설계가 갈린다 (§5, §9.9) |
| **17** | 백엔드 | 🔴 **세율별 절사 준수.** `sales-closing`의 "주문별 1엔 절사"가 한 주문에 8%/10%가 섞일 때 **세율마다 각 1회**로 동작하는가. 법령상 단위는 **`영수증 1장 × 세율마다 1회`**이고 **라인별 절사 후 합산은 금지**다(消令70の10 / 基通1-8-15 注 / Q&A問57). Q2가 실현되는 순간 서버도 개수 대상이 된다 (§8.5.1) **[최우선]** |
| **18** | 백엔드 | **積上げ計算 대응.** 신고 매출세액을 **割戻し**(`×100/110` → 課税標準額 1,000엔 미만 절사 → `×7.8%`)로 산출하는가 **積上げ**(`Σ영수증세액 × 78/100`)로 산출하는가. 積上げ를 쓰려면 **영수증에 세액을 인쇄해야** 하므로 앱의 인쇄 기본값이 여기에 묶인다 (§7.2·§8.5.2) |
| **19** | 백엔드 | **適格返還請求書 지원.** 반품 시 **원거래일**과 **세율별 반환액**을 서버가 보유·반환하는가. 税込 1만엔 이상 반품은 교부 의무가 있다(消法57の4③) (§7.5) |
| **20** | 백엔드/법무 | **電子帳簿保存法 보존 주체.** 전자 거래기록 **7년(최대 10년)** 보존 주체가 AppFit 서버 원장인가. 앱 로컬에 보존 의무가 남는다면 §8.2의 로컬 90일 정리 정책이 성립하지 않는다 (§7.4·§8.2) |
| **21** | 사업/법무 | **Square P2PE 등재 여부와 일본 가맹점 SAQ 제출 의무.** 계약서 원문 확인 전까지 "P2PE로 PCI 스코프 축소"를 전제하지 말 것 (§6.7) |
| **22** | 기획 | **2차 이월 3종의 확정**(X 리포트 / 거래 보류·재개 / 훈련 모드 — §11.1 제외 항목). 특히 **훈련 모드는 원장 스키마에 격리 플래그**가 필요해 나중에 넣으면 마이그레이션이 발생한다 — **플래그만 1차에 심을지** 판정 필요 |

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

2차 재검증에서 발견된 레거시 POS 표준 기능 3종도 **1차에서 제외**한다(→ §10 Q22).

| 기능 | 제외 근거 | 지금 남겨둘 것 |
|---|---|---|
| **X 리포트**(중간 정산) | 단일 카운터·소수 인원 전제에서는 Z(마감)만으로 성립. 2인 이상 교대가 확정되면 필요해진다 | Z 로직을 "카운터 리셋"과 "집계 조회"로 분리해 두면 X는 조회만 재사용 |
| **거래 보류/재개** | §9.1 원칙 1(모드리스 — "앱은 언제나 새 판매 상태")과 **정면 충돌**한다. 상태·화면이 늘어 Simple의 정체성을 해친다 | 없음. 필요해지면 원칙을 재검토하는 것이 먼저 |
| **훈련 모드** | 1차 파일럿은 개발자가 동행하므로 실익이 낮다 | 🔴 **원장 스키마의 격리 플래그**는 지금 넣는 편이 싸다 — 나중에 넣으면 전체 마이그레이션이다(§10 Q22) |

### 11.2 단계

| Phase | 내용 | 완료 기준 |
|---|---|---|
| **0** | `kiosk_v4_japan` 확보 + 스테이징 E2E + Square 샌드박스 1건 + **§10.2 백엔드 질문 회신**(특히 **Q1·Q2·Q17·Q18**, 그리고 Q4·Q10·Q11) | 카탈로그 → 주문등록 → 취소 → 일마감이 실제로 돌고, Square 샌드박스 결제 1건 성공. **세액 계산 규칙 합의(절사 단위 포함)** |
| **1** | 신규 레포 골격(`appfit_core` 태그 의존) + AppFit 로그인 / 매장 / 카탈로그 증분 동기화 + **로컬 DB 스키마 확정**(§8.2) + **디자인 토큰·폰트 확정**(§9.5·§9.7) | D3 MINI에 설치되어 메뉴가 뜬다. 오프라인에서도 메뉴가 뜬다. **ja/ko/en 각 화면에서 폰트가 한 문장 안에 섞이지 않는다** |
| **2** | 장바구니 · 옵션(서버 규칙) · **세율 테이블 + 금액 계산 결정론**(§8.5) + 카탈로그 버전 pin | 서버 금액 검증식이 400 없이 통과. **§11.3의 세액 property-based 테스트 통과**(영수증×세율 1회 절사, 할인 안분 불변식). 1%/8%/10% 전환 테스트 통과 |
| **3** | 현금(거스름돈) + Square Terminal 이식(**CFG 의존 제거 + §4 결함 수정**) + **로컬 원장(WAL+FULL) + 3단계 원자성**(§8.6) + 주문 등록 + 오프라인 큐 | 네트워크 단절 후 복구 시 중복 없이 등록. **결제 승인 직후 강제 종료해도 판매가 회수**된다. **§11.3 장애 주입 3종 통과**. 4xx 1건이 큐를 막지 않는다 |
| **4** | 영수증(적격간이청구서 + 領収書) + 로컬 채번 + 재발행 + 캐시드로어(개폐 이력) + 고객 디스플레이 | 기재 5항목이 실물 레시트에 인쇄. 오프라인 판매도 번호가 찍힌다 |
| **5** | **영업일 개시/마감 + 현금 관리(준비금·입출금·실사·과부족)** + 일 매출 마감 조회 | **미전송 0 게이트**가 동작하고, 현금 과부족이 산출된다 |
| **6** | 취소/반품(당일·전일, 부분, 交通系IC 예외, **適格返還請求書**) + 담당자·권한 + 시각 신뢰 + OTA · Fleet 편입 | 운영 투입 가능. **72시간 soak 통과** |

### 11.3 검증 전략

금전을 다루는 앱은 "화면이 뜬다"로 검증할 수 없다. 아래 셋은 **단계별 완료 기준에 직접 걸린다.**

#### (1) 금액·세액 — property-based test

예제 몇 개로는 부족하다. **불변식을 ∀장바구니에 대해 검사**한다.

| 불변식 | 내용 |
|---|---|
| **단수처리 단위** | 세액 = `영수증 × 세율` 단위 1회 산출. **`Σ 라인별 개별 반올림` 은 정본과 다르다**는 것 자체를 테스트로 못박아, 나중에 누가 라인별 합산으로 "최적화"하면 실패하게 만든다 |
| **할인 안분** | `Σ 세율별 할인액 = 총 할인액` (잔여 1엔 귀속 규칙이 없으므로 합계만 고정) |
| **과세표준** | 세액은 **할인 후** 세율별 합계에서 산출 |
| **서버 검증식** | `totalAmount − totalDiscount = paymentAmount = Σ payments[].amount` |
| 세율 전환 | **1% / 8% / 10% 병존** + 적용개시일 경계(2027-04-01 / 2029-04-01) 전후 |

#### (2) 장애 주입(fault injection)

이 앱의 **`NetFaultInjector` 패턴을 확장**해 결제 경로에 적용한다. 소매 POS의 다수가 연 1회 이상 다운타임을 겪는다는 조사가 있는 만큼, 정상 경로만 검증하는 것은 의미가 없다.

| 주입 | 확인할 것 |
|---|---|
| **Terminal checkout 응답 지연** | 폴링이 타임아웃으로 접히지 않고 `unknown`을 유지하는가 |
| **Terminal checkout 타임아웃** | 기동 시 `SearchTerminalCheckouts` 정합화로 회수되는가 (§4 결함의 회귀 테스트) |
| **`PENDING` 고착** | 화면이 잠긴 채 복구 경로를 제시하는가 |
| **결제 승인 직후 강제 종료** | 판매가 회수되는가 (§8.6 ①) |
| **전원 차단** | `synchronous=FULL`에서 마지막 커밋이 살아남는가 (§8.2.1) |
| **4xx 응답 1건** | 큐가 막히지 않고 그 건만 `parked` 되는가 (§8.6.3) |
| **디스크 가득참** | `SQLITE_FULL`에서 결제가 차단되는가 (§8.2.1) |
| **프린터 용지 소진·커버 열림** | 판매는 성립하고 영수증만 대기 큐로 가는가 (§8.11) |

#### (3) 72시간 soak

POS는 하루 12~16시간 재시작 없이 돈다. **24시간은 통과하고 2일차 밤에 잡히는 누수가 흔하므로** 24h로는 부족하다.

- "램프업 → 72h 정상상태 → 램프다운" 구성으로 무인 주문 루프를 돌린다
- **힙·FD·커넥션 수의 추세선**을 본다(절대값이 아니라 기울기)
- Impeller 렌더러 여부에 따라 그래픽 메모리 거동이 달라지므로 **실기기에서 확인**한다(§8.11.1)
- **실매장 파일럿의 게이트**로 삼는다

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

```bash
# 사내 잔여 8개 레포 전수 확인 (2차) — 현금 POS 자산 부재 확인. 결과: 매치 없음
cd ~/Documents/GitHub
grep -ril "영업일\|마감\|시재\|준비金\|釣銭\|과부족\|drawer\|no-sale\|z-report\|suspend" \
  kokonutJapan kokonut_order_agent kokonut_order_agent_v2 \
  kiosk kiosk_new kiosk_new_v2 kiosk_v2 kiosk_v3
```

인용한 사내 파일:

- `kiosk_v3_japan/lib/features/square/provider/repo_square_terminal.dart`
- `kiosk_v3_japan/lib/features/square/provider/square_terminal_provider.dart:405-431` (**이식 전 수정 필요한 결함** — §4)
- `kiosk_v3/lib/shared/provider/order_number_provider.dart` (대기표 채번 — §8.8의 반례)
- `kiosk_v3/lib/features/admin/dialog/d_admin_password.dart` (PIN 다이얼로그 UI 패턴)
- `appfit_order_agent/android/app/src/main/java/co/kr/waldlust/order/receive/MainActivity.java:313` (`hasScanner()`)
- `appfit_order_agent/android/app/src/main/AndroidManifest.xml:9-22` (스캐너 `<queries>` 이중 선언)
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

### 세제 1차 자료 출처 (§7·§8.5)

세액 계산은 이 문서에서 유일하게 **법령 위반이 곧 사고**인 영역이므로, 요약이 아니라 원문에서 인용했다.

| 구분 | 자료 |
|---|---|
| 법령 | 消費税法 第57条の4 / 消費税法施行令 **第70条の10**(단수처리) · 第70条の9③二(반환 인보이스 면제) — e-Gov |
| 통달 | 消費税法基本通達 **1-8-15**(단수처리 1회) · **1-8-17**(반환 1만엔 판정 단위) |
| インボイスQ&A | **問27·28**(반환 인보이스 의무·면제) · **問57**(단수처리) · **問58**(간이청구서 기재사항) · **問59**(税抜/税込 통일) · **問60**(반환 인보이스 기재사항) · **問62**(합본 교부) · **問67**(서류 단위) · **問69**(할인 세율 안분) · **問70**(값인하 시점) · **問118**(割戻し/積上げ) |
| 軽減税率Q&A | **問13** / 軽減通達18 (경감대상인 취지의 표시 방법) |
| 그 밖 | タックスアンサー No.6371(단수계산) · No.6498(적격간이청구서) · 국세청 「少額な返還インボイスの交付義務免除」 |

업계 관행 확인: スマレジ(세율 단수처리 설정) · ユビレジ(금액/세액 단수처리 분리, 과거 회계 무재계산) · Airレジ(세율 매장기본값+상품 오버라이드, 内税 시 취식/포장 税込価格 개별 등록).

---

## 12. 정정 이력

이 문서는 두 차례 재검증을 거쳤다. **정정된 서술은 지우지 않고 여기에 남긴다** — 같은 오판이 반복되는 것을 막는 것이 목적이다.

### 1차 재검증 (초판 직후)

| # | 정정 |
|---|---|
| 1 | "Square 연동 = 최대 리스크, 신규 개발" → **사내 프로덕션 구현이 이미 있다**(`kiosk_v3_japan`) |
| 2 | "영수증이 CP949라 일본어 재작업 필요" → Sunmi 내장은 **AIDL이라 인코딩 무관** + Shift_JIS 구현이 이미 존재 |
| 3 | 서버 준비도 과소평가 → `sales-closing` 등 **일본 세제가 이미 서버에 구현돼 있다** |
| 4 | (신규 발견) **2027-04 소비세 개정** |

### 2차 재검증 (POS 도메인 지식 기준)

§8이 "사내 두 레포에 없는 것"을 역으로 나열해 만들어졌다는 구조적 한계를 검증했다.

| # | 절 | 정정 내용 |
|---|---|---|
| 1 | **§8.5** | 단수처리를 *"서버가 주문별로 절사하니 앱도 주문 단위로"*(정합성 문제)로 서술했으나, 법령상 단위는 **`영수증 1장 × 세율마다 각 1회`**이고 **라인별 절사 후 합산은 명시적 금지**다 → **법령 준수 문제로 승격**. 아울러 세액 계산 경로가 **영수증용/신고용 2개**임을 반영 |
| 2 | **§6.3** | *"웹훅을 쓰지 않는다 → 백엔드 컴포넌트 불필요"*를 무조건으로 단정했으나, Square가 웹훅을 권고하는 이유는 **`CANCELED → COMPLETED` 역전**이다 → **기동 시 `SearchTerminalCheckouts` 정합화를 전제로 한 조건부 결론**으로 정정 |
| 3 | **§9.4(4)** | *"レシート 기본 출력 + 領収書 요청 시 별도 발행"*은 일본 실무상 **이중발행**이다 → **배타 발행**으로 정정 |
| 4 | **§3** | Square 액세스 토큰을 다른 설정값과 같은 층위로 두고 "기기 로컬 입력"을 허용했으나 Square 보안 가이드에 어긋난다 → **장기 토큰은 서버 보관, 기기엔 단기 세션 토큰** |
| 5 | **§4** | `kiosk_v3_japan`의 Square 구현을 무조건 재사용 자산으로 기재했으나, **취소 폴링 타임아웃 시 최종 상태 미확정인 채 체크아웃을 버리는 결함**이 있다 → **이식 전 수정 필수**로 표기 |

**정정되지 않고 재확인된 것**: §8의 "그린필드" 판정. 사내 12개 레포 전수 확인 결과 현금 취급 POS 자산은 없다(§4).

### 이 문서의 갱신 트리거

- **2027-04 개정 법안이 국회를 통과할 때** — 대상 품목 세목·경과조치가 확정된다(§7.1)
- §10.2 백엔드 질문에 회신이 올 때 — 특히 Q17(세율별 절사)·Q18(積上げ)·Q20(보존 주체)
- `kiosk_v4_japan` 확보 시 — §4 재사용 자산 재평가
- **미확인 항목이 실측으로 확정될 때** — psow / SQLCipher 성능 / Square 멱등키 보관기간 / P2PE 등재
