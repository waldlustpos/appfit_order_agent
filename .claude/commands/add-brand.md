---
description: 새 브랜드를 대화형으로 추가 (brand_registry/brand_theme/settings/i18n 3로캘/pubspec/qr_payload_strategy 6개 지점 편집 + 라벨 BMP/영수증 PNG 로고 자산 변환 + slang 재생성 + analyze + l10n 감사 + 선택: 브랜드 전용 Sentry 에러 알림 채널 라우팅)
---

새 브랜드를 매장 ID prefix 기반으로 앱 전반에 통합한다. 아래 STEP 순서대로 진행한다.
참고 문서: [docs/BRAND_ASSETS.md](../../docs/BRAND_ASSETS.md). 기존 사례(MATA/MHST/TPCP)의 코드를 anchor 로 복제한다.

---

## STEP 0 — 입력 수집 (AskUserQuestion)

다음 값을 받는다. **필수 1~4 가 없으면 진행하지 말고 재질문**한다. 선택 5~8 은 기본값으로 진행 가능.

1. **표시명** (필수) — 설정 테마 버튼/번역에 보일 이름. ko/en/ja 가 다르면 각각, 같으면 공통 1개.
2. **ID prefix** (필수) — 매장 ID 앞 4자. `^[A-Z]{4}$` 검증, 기존 prefix(TPCP/MHST/MATA…)와 중복 금지.
3. **slug** (필수) — `assets/images/brand/<slug>/` 폴더명. `^[a-z][a-z0-9_]*$` 검증, 기존 폴더와 중복 금지. 기본값=표시명 음역.
4. **enum 키** (필수) — `BrandKey`/`BrandTheme.id`/i18n `options`/`_labelFor` 에 **단일 토큰으로 공통 사용**. snake_case(slang `key_case: snake`). 기본값=prefix 소문자.
5. **브랜드 색상** (선택) — "지금 hex 지정" / **"placeholder(appfit 핑크)+TODO 로 두고 나중 확정"**(기본).
6. **영수증 로고 사용** (선택) — 기본 "아니오". → `hasReceiptLogo`. "예" 면 STEP 3-2 에서 `receipt_logo.png` 자동 생성.
7. **라벨 로고 PNG 경로** (선택) — 절대경로. 입력 시 STEP 3-1 에서 `label_logo.bmp` 로 변환. 없으면 코드만(tokyoplatz 폴백).
7-2. **영수증 로고 PNG 경로** (선택) — 절대경로. 입력 6 이 "예" 일 때만 의미. 입력 시 STEP 3-2 에서 `receipt_logo.png`(높이 80px 정규화) 생성. 미입력이고 입력 6 이 "예" 면 입력 7(라벨 PNG)을 재사용해 생성, 그것도 없으면 STEP 6 수동 안내. (라벨=정사각 심볼 / 영수증=가로 락업으로 원본이 다른 경우가 많으니 가능하면 별도 지정.)
8. **특수 분기**(일본/JPY 등) (선택) — 기본 "아니오(한국 live/KRW)". **"예" 면 이 커맨드 범위 밖** → 코드 통합 후 STEP 6 에서 사람에게 안내만.
9. **듀얼모니터 영상** (선택) — D3 MINI 전면(고객용) 보조 디스플레이에 재생할 `.mp4` 절대경로. 입력 시 STEP 3-3 에서 `android/app/src/main/res/raw/dm_<slug>.mp4` 로 배치.
10. **듀얼모니터 이미지** (선택) — 같은 디스플레이에 표시할 `.png`(또는 `.jpg`→png 변환) 절대경로. 입력 시 STEP 3-3 에서 `android/app/src/main/res/drawable/dm_<slug>.png` 로 배치. (영상·이미지 둘 다 입력 가능 — 설정 화면에서 운영자가 택1, 미설정 시 영상 우선 자동 표시. 둘 다 없으면 전면 모니터는 검은 화면.)
11. **브랜드 전용 Sentry 알림 채널 ID** (선택) — 이 브랜드의 에러를 별도 Slack 채널로 받고 싶을 때 채널 ID(`C0...`). 입력 시 STEP 5 에서 `sentry_alerts/routes.json` 에 라우팅을 추가한다. **미입력이면 catch-all(appfit-alert-test)로 흡수** — STEP 5 스킵. (채널은 사전에 Slack 에서 생성돼 있어야 함.)

치환 토큰을 확정한다: `<PREFIX>`(대문자4), `<slug>`, `<KEY>`(enum 키), `<EnumCase>`(BrandTheme 항목명, camelCase, 예: `mahaTaste`), `<KeyPascal>`(인스턴스 헬퍼명, 예: `Maha`→`isMahaStore`), `<NAME_ko/en/ja>`.

---

## STEP 1 — 멱등성·중복 검증 (Grep 가드)

각 지점이 이미 적용됐는지 Grep 한다:

```
grep -n "BrandKey.<KEY>\|storeIdPrefix: '<PREFIX>'\|assetFolder: '<slug>'" lib/utils/brand_registry.dart
grep -n "BrandKey.<KEY>" lib/services/label_printer/qr_payload_strategy.dart   # QR 전략 exhaustive switch case
grep -n "id: '<KEY>'" lib/constants/brand_theme.dart
grep -n "options.<KEY>" lib/widgets/settings/settings_brand_theme_section.dart
grep -n "\"<KEY>\"" lib/i18n/strings_ko.i18n.json lib/i18n/strings_en.i18n.json lib/i18n/strings_ja.i18n.json
grep -n "assets/images/brand/<slug>/" pubspec.yaml
ls android/app/src/main/res/raw/dm_<slug>.mp4 2>/dev/null        # 듀얼모니터 영상(선택)
ls android/app/src/main/res/drawable/dm_<slug>.png 2>/dev/null   # 듀얼모니터 이미지(선택)
```

- **전부 MISS** → 신규. STEP 2.
- **일부 HIT** → 부분 적용. 적용/미적용 지점을 표로 보고하고, AskUserQuestion 으로 "남은 지점만 마저 추가?" 확인 후 미적용 지점만 STEP 2.
- **전부 HIT** → "이미 존재 — 변경 없음" 으로 종료.

---

## STEP 2 — 6개 코드 지점 Edit

각 파일을 **Edit 전에 Read** 한다. anchor 매칭이 실패하면(이미 적용/구조 변경 신호) 그 지점만 건너뛰고 STEP 6 에 보고한다.

> 브랜드 식별·자산·통화·환경·기능이 모두 `BrandRegistry` 한곳으로 모였다. `PreferenceService.isXXXStoreId` 같은 prefix 헬퍼는 더 이상 새로 추가하지 않는다(레지스트리가 prefix 매칭 전담).

### 2-1. `lib/utils/brand_registry.dart` (2곳)
- enum: `enum BrandKey { ... }` 끝에 `, <KEY>` 추가.
- `_all` Map 마지막 항목(`);`) 뒤에 `BrandMeta` 항목 추가:
```dart
    BrandKey.<KEY>: BrandMeta(
      key: BrandKey.<KEY>,
      storeIdPrefix: '<PREFIX>',
      assetFolder: '<slug>',
      hasReceiptLogo: <true 영수증 시 / 아니면 줄 생략>,
      theme: BrandTheme.<EnumCase>,
      currency: CurrencyUnit.<krw|jpy>,        // 입력 8(일본/JPY) → jpy
      serverEnvironment: '<live|japanLive>',   // 입력 8 → japanLive
      features: {<지원 기능, 예: BrandFeature.labelCategoryFilter> },  // 없으면 줄 생략
    ),
```
입력 8(특수 분기)이 "아니오"면 currency=krw / serverEnvironment='live' / features 생략. "예"(일본)면 jpy / japanLive / 필요 기능 등록.

### 2-2. `lib/constants/brand_theme.dart` — ⚠️ 세미콜론 함정
마지막 enum 항목이 `);` 로 끝난다. anchor 에 `  );` + 빈 줄 + `  const BrandTheme({` 를 포함해 종료부만 유일 매칭하고, `);`→`),` 로 바꾼 뒤 새 항목 + `);` 를 넣는다.
- **placeholder 색상**(기본): MATA TODO 패턴 복제 — primary `0xFFfb3e7e`, primaryAlpha `0x14fb3e7e`, loginBackground `0xFFfb3e7e`, onLoginBackground `Colors.white`, logoAsset `null`, loginGradient `[Color(0xFFfb3e7e), Color(0xFF9843cb)]`. 위에 `// TODO(<PREFIX>): 색상 확정 시 교체 … logo.svg 배치 후 logoAsset 지정` 주석.
- **hex 지정 시**: primary=`0xFF<hex>`, primaryAlpha=`0x14<hex>`, loginBackground/onLoginBackground/loginGradient 를 입력값으로, TODO 생략.

### 2-3. `lib/widgets/settings/settings_brand_theme_section.dart`
`_labelFor` switch 마지막 case 뒤에:
```dart
      case BrandTheme.<EnumCase>:
        return t.settings.theme.options.<KEY>;
```

> 별도 편집점 없음. STEP 2-2 에서 추가한 `BrandTheme` 는 개발자 옵션 picker(전체)뿐 아니라
> **일반 설정에도 자동 노출**된다 — `BrandMeta.selectableThemes`(brand_registry.dart)가
> `[기본, 브랜드테마]` 2종을 파생하고, 해당 prefix 매장 로그인 시 설정 오른쪽 패널 상단에
> 테마 카드로 뜬다. `theme` 를 `BrandTheme.appfitDefault` 로 두면(고유 테마 없음) 선택지가
> 1개라 일반 설정 picker 는 자동 숨김(개발자 picker 에는 여전히 노출). 즉 색상을 placeholder
> 핑크로 두더라도 **별도 `BrandTheme.<EnumCase>` 항목(2-2)** 만 추가하면 운영자에게 노출된다.

### 2-4. i18n `strings_ko` / `strings_en` / `strings_ja` (3파일 모두)
각 파일 `settings.theme.options` 의 마지막 키 끝에 콤마를 추가하고 새 줄 `                "<KEY>": "<NAME_xx>"` 추가(들여쓰기 16칸). **3파일 누락 없이.**

### 2-5. `pubspec.yaml`
assets 의 마지막 brand 폴더 줄 뒤에 `    - assets/images/brand/<slug>/` (들여쓰기 4칸).

### 2-6. `lib/services/label_printer/qr_payload_strategy.dart` — ⚠️ exhaustive switch (BrandKey 추가의 필연적 후속)
`qrPayloadStrategyProvider` 의 switch 는 `default:` 없이 모든 `BrandKey` 를 명시한다. 따라서 STEP 2-1 에서 `BrandKey.<KEY>` 를 추가하면 이 switch 가 비망라(non-exhaustive)가 되어 **STEP 4 의 `flutter analyze` 에서 에러**가 난다(의도된 강제 — 새 브랜드의 QR 포맷을 반드시 결정하게 함). 라벨 프린터를 쓰는지와 무관하게 **모든 새 브랜드에 필수**.

새 brand 의 QR 포맷을 정해 case 를 추가한다:
- **기본 포맷 그대로**(대부분): Default 반환 그룹에 `case BrandKey.<KEY>:` 한 줄 추가.
```dart
    case BrandKey.tpcp:
    case BrandKey.mhst:
    case BrandKey.mata:
    case BrandKey.<KEY>:       // ← 추가
    case null:
      return const DefaultQrPayloadStrategy();
```
- **커스텀 포맷 필요**: `DefaultQrPayloadStrategy` 를 복제해 `class <KeyPascal>QrPayloadStrategy extends QrPayloadStrategy` 를 정의하고 `buildPayload` 본문만 교체한 뒤, switch 에 `case BrandKey.<KEY>: return const <KeyPascal>QrPayloadStrategy();` 추가. payload 에 필요한 필드(orderNo/shopItemId/labelSeq/storeId/orderedAt/displayNum 등)는 `LabelOrderInfo`/`LabelMenuInfo` 에 이미 다 있으므로 모델 수정 불필요.

> QR 출력 ON/OFF 토글 자체는 일반설정(프린터 카드, 라벨프린터 사용 시 노출)의 전 브랜드 공통 운영자 설정이라 브랜드 추가 시 건드릴 게 없다. 브랜드별로 달라지는 건 **payload 포맷뿐**이고 그게 이 전략이다.

---

## STEP 3 — 자산 변환 (선택)

### 3-1. 라벨 로고 (`label_logo.bmp`)
- **라벨 PNG(입력 7)가 있으면**: `brand-asset-converter` 서브에이전트를 호출한다 (인자: SRC=PNG 절대경로, slug=<slug>). 결과 검정 비율이 30~65% 면 패턴 A 채택. 애매(경계/패턴 B 의심)하면 보고된 두 비율을 사용자에게 보여주고 AskUserQuestion 으로 채택 패턴을 확인한다. 채택 안 한 `label_logo_B.bmp` 는 정리하도록 안내.
- **없으면**: 변환 생략. 코드는 라벨→tokyoplatz 폴백으로 안전 동작.

### 3-2. 영수증 로고 (`receipt_logo.png`) — 입력 6 이 "예" 일 때만
외부 ESC/POS 프린터와 내장 Sunmi 프린터 모두 **같은 `receipt_logo.png` 를 앱 측 스케일 없이 1픽셀=1도트로 출력**한다 (escpos_builder.dart `addImageRaster` / NativeMethodHandler `decodeByteArray` 둘 다 리사이즈 없음 — 상세는 docs/BRAND_ASSETS.md §4.2). 따라서 **PNG 픽셀 크기 = 영수증 출력 도트 크기**이고, 높이 정규화는 자산 단계에서 한 번만 하면 두 프린터에 동시 적용된다.

- **소스 결정**: 입력 7-2(영수증 PNG) → 없으면 입력 7(라벨 PNG) 재사용 → 둘 다 없으면 생성 생략하고 STEP 6 수동 안내.
- **생성**: 아래 스크립트(= docs/BRAND_ASSETS.md §4.2)로 `receipt_logo.png` 를 만든다. RGBA → 흰 배경 평탄화 → **높이 80px 기준 비율 유지 LANCZOS 리사이즈**, 단 폭이 용지(384도트, 58mm)를 넘으면 폭 384 기준으로 축소(높이<80) → 저장. 결과 `W×H` 와 "폭 ≤ 384(안 잘림)" 여부를 보고한다. (mammoth 참조 341×24 / mahataste 187×80. 80px 는 심볼+다줄 락업도 가독되는 높이.)

```bash
python3 <<'EOF'
from PIL import Image
import os
SRC = '<RECEIPT_SRC 또는 라벨 SRC 절대경로>'
DST = 'assets/images/brand/<slug>/receipt_logo.png'
TARGET_H, MAX_W = 80, 384  # 높이 80px, 용지 폭(58mm=384도트) 캡
src = Image.open(SRC).convert('RGBA')
bg = Image.new('RGBA', src.size, (255, 255, 255, 255))   # 흰 종이에 평탄화
flat = Image.alpha_composite(bg, src).convert('RGB')
w, h = flat.size
s = min(TARGET_H / h, MAX_W / w)                          # 80x384 박스 fit
out = flat.resize((max(1, round(w * s)), max(1, round(h * s))), Image.LANCZOS)
os.makedirs(os.path.dirname(DST), exist_ok=True)
out.save(DST, format='PNG')
print(f'receipt_logo.png: {flat.size} -> {out.size} (W x H), 폭<=384: {out.size[0] <= MAX_W}')
EOF
```

> 라벨 PNG 도 없어 폴더가 미생성 상태일 수 있으니 스크립트가 `os.makedirs` 로 폴더를 보장한다. 단 STEP 2-1 의 `BrandMeta.hasReceiptLogo: true` 가 설정돼 있어야 호출부가 이 PNG 를 읽는다(입력 6=예면 이미 반영됨).

### 3-3. 듀얼모니터 콘텐츠 (`res/raw/dm_<slug>.mp4` / `res/drawable/dm_<slug>.png`) — 입력 9/10 이 있을 때만

D3 MINI 전면(고객용) 보조 디스플레이는 **`dm_<slug>` 이름의 네이티브 리소스를 런타임 해석**(`getResources().getIdentifier("dm_" + slug, "raw"|"drawable", pkg)`)해 표시한다(데이터 기반 — Java 코드 수정 불필요). 따라서 **파일명이 곧 `dm_<slug>`** 여야 한다. slug 는 STEP 0 에서 `^[a-z][a-z0-9_]*$` 로 검증되어 유효 Android 리소스명을 보장한다(대문자/하이픈 불가).

> ⚠️ **`dm_` 접두사 필수** — 릴리즈 빌드는 `isShrinkResources=true` 라 `getIdentifier` 동적 참조 리소스를 R8 이 제거한다. `res/raw/keep.xml` 의 `tools:keep="@raw/dm_*,@drawable/dm_*"` 가 `dm_` 접두사 리소스를 보존하므로 **반드시 `dm_<slug>` 로 둘 것**(접두사 없으면 디버그는 되지만 릴리즈에서 사라져 섹션·표시가 안 됨). keep.xml 은 와일드카드라 브랜드 추가 시 수정 불필요.

- **영상(입력 9)**: 원본 `.mp4` 를 `android/app/src/main/res/raw/dm_<slug>.mp4` 로 복사(변환 없음). H.264 mp4 권장, 무음(네이티브가 볼륨 0 처리), 자동 루프. 용량 참고: 기존 mammoth ≈ 585KB. 해상도는 보조 디스플레이 실해상도 권장.
- **이미지(입력 10)**: `.png` 를 `android/app/src/main/res/drawable/dm_<slug>.png` 로 배치(jpg 입력 시 png 변환). `fitCenter` 표시이며 **배경은 흰색**(여백 포함). 따라서 로고/그래픽은 **밝은 배경용(어두운색 또는 컬러)** 이어야 한다 — 흰색 로고는 흰 배경에서 보이지 않으니 브랜드색/검은색 버전을 사용. (예: mammoth 는 브랜드색 #4A3730, mahataste 는 #e31f26.)
- 둘 다 없거나 운영자가 "노출안함" 선택 시 → 전면 모니터는 **검은 화면**(모니터는 켜진 채 검정). 콘텐츠가 아예 없으면 설정 섹션도 비노출. (보조 패널만 끄는 표준 API 가 없고, screenBrightness 강제는 메인 화면까지 어둡게 하므로 전원 off 는 하지 않음.)
- ⚠️ 표시 우선순위(effectiveMode): 운영자 명시 선택이 없으면 **영상 > 이미지 > 노출안함** 자동. 설정 화면 "전면 모니터 콘텐츠" 섹션에서 변경 가능. 배경: **영상=검정(레터박스), 이미지=흰색, 노출안함/무콘텐츠=검정**.
- ⚠️ 레거시 `*_dual_monitor_logo.{png,jpg}` 네이밍은 **미사용**(런타임 해석 안 됨). 새 규약은 반드시 `dm_<slug>.{mp4,png}`.

---

## STEP 4 — 검증

순서대로 Bash 실행:
1. `flutter pub run slang` — strings.g.dart 재생성. **⚠️ build_runner 아님** (이 프로젝트는 slang_build_runner 미설치라 build_runner 로는 strings.g.dart 가 갱신되지 않음). `dart run slang` 은 Flutter SDK 의존성 때문에 실패하므로 반드시 `flutter pub run` 경로.
2. `flutter analyze` — 신규 에러 0 확인 (기존 info/warning 은 무시, 새 error 만 본다). 특히 `qr_payload_strategy.dart` 에 비망라 switch 에러(`The type 'BrandKey?' is not exhaustively matched`)가 보이면 **STEP 2-6 누락** — case 추가로 해소.
3. `l10n-auditor` 서브에이전트 호출 — ko/en/ja 에 `<KEY>` 가 모두 동기화됐는지 감사.

실패 시 어느 STEP/파일에서 멈췄는지, 부분 적용 상태를 명시한다.

---

## STEP 5 — Sentry 알림 라우팅 (선택)

입력 11(브랜드 전용 Sentry 알림 채널 ID)이 주어졌을 때만. 없으면 이 브랜드 에러는
catch-all(appfit-alert-test)로 흡수되므로 **스킵**한다. 전용 채널로 보내려면
`sentry_alerts/routes.json`(라우팅 정본)에 항목을 추가하고 스크립트를 적용한다.
상세: [sentry_alerts/README.md](../../sentry_alerts/README.md).

> 앱 코드(Dart)는 변경 없음 — `store_id` 태그는 이미 appfit_core `MonitoringService`
> 가 심는다. 브랜드 전용 채널은 순수 Sentry 운영 설정이다.

1. `sentry_alerts/routes.json` 의 `branded[]` 에 항목 append (동일 `value` 이미 있으면 스킵):
```json
{ "label": "<PREFIX>", "match": "sw", "value": "<PREFIX>",
  "channel": "<Slack 채널명>", "channel_id": "<입력 11>" }
```
   - 브랜드 전체를 한 채널로(권장): `match: "sw"` + 4자 prefix.
   - 특정 매장만: `match: "eq"` + 정확한 store_id.
   - 운영 서버 이벤트만 받고 싶으면 `"environment": "<브랜드 serverEnvironment>"`(선택) 추가.
     스크립트가 `[auto] <PREFIX>(non-<env>) -> #<catchall 채널>` spillover 규칙을 함께 만들어
     나머지 환경(staging 등)을 흘려보낸다. 사내 QA 매장이 많은 브랜드에 유용(MHST 선례).
2. 적용(멱등):
```bash
python3 sentry_alerts/sentry_alerts.py apply --dry-run   # payload 확인(토큰 불필요)
python3 sentry_alerts/sentry_alerts.py apply             # 규칙 생성 + catch-all 제외필터 자동 갱신
python3 sentry_alerts/sentry_alerts.py list              # 결과 확인
```
3. `.env` 에 `SENTRY_AUTH_TOKEN`(스코프 `alerts:write`)이 없으면 스크립트가 안내하며
   멈춘다 → 이 STEP 은 "토큰 발급 후 위 명령 실행" 으로 STEP 6 체크리스트에 넘기고 계속.

---

## STEP 6 — 요약 + 사람 체크리스트

변경 파일 표로 요약 후, 자동화 못 한 작업을 체크리스트로 출력:
- [ ] `assets/images/brand/<slug>/` 폴더 (자산을 1개라도 생성했으면 폴더는 이미 존재. 자산을 아예 안 만들었으면 `.gitkeep` 으로 폴더 추적)
- [ ] `label_logo.bmp` 최종 채택 (PNG 변환했으면 검정비율 검토)
- [ ] `receipt_logo.png` — 입력 6 "예" + 소스 있으면 STEP 3-2 에서 높이 80px 로 자동 생성됨 (`W×H`·폭≤384 검토). 소스 없었으면 §4.2 스크립트로 높이 80px 정규화 후 수동 배치 + brand_registry `BrandMeta.hasReceiptLogo: true` 확인
- [ ] (선택) `logo.svg` 배치 → brand_theme `logoAsset` 경로 지정
- [ ] 색상 placeholder 면 최종 hex 확정 + TODO 제거
- [ ] `flutter clean && flutter pub get` (신규 asset 인식)
- [ ] (입력 9/10) 듀얼모니터 콘텐츠는 **네이티브 res 변경 → 풀 리빌드 필요**: `flutter clean && flutter pub get` 후 APK 재빌드(hot reload/restart 로는 반영 안 됨). `dm_<slug>.mp4`/`dm_<slug>.png` 파일명이 `dm_`+slug 와 정확히 일치하는지 확인. **릴리즈 빌드(`--release`)로도 섹션·표시가 나오는지 확인**(접두사 누락 시 릴리즈에서만 사라짐).
- [ ] 실기기 D3 MINI + 보조 디스플레이: 설정 → "전면 모니터 콘텐츠" 섹션 노출 → 영상/이미지/노출안함 전환 즉시 반영. 배경 확인(영상=검정 레터박스, 이미지=흰색, 노출안함/무콘텐츠=검정). 보조 디스플레이 없는 기기에선 섹션 미노출.
- [ ] 로그아웃/앱 종료 시 전면 모니터가 흰 이미지 잔류 없이 검정으로 돌아오는지 확인.
- [ ] APK 비대화 주의: 모든 브랜드의 raw/drawable 이 universal APK 에 번들된다. 영상은 길이/용량 최소화.
- [ ] 실기기: 해당 prefix 매장 로그인 → 라벨/영수증 테스트 출력, 브랜드 전환 시 캐시 무효화 확인
- [ ] **테마 노출** — 해당 prefix 매장 로그인 → 설정 오른쪽 패널 상단에 테마 카드(`기본 / <NAME>`) 2종 노출 확인. 색상 placeholder 면 핑크로 보이지만 노출은 정상(STEP 2-2 항목만 있으면 동작). `theme: BrandTheme.appfitDefault` 로 둔 브랜드는 일반 설정 picker 미노출이 정상.
- [ ] **QR 페이로드** — STEP 2-6 에서 `BrandKey.<KEY>` case 추가됨(기본 `DefaultQrPayloadStrategy`). 이 브랜드가 다른 QR 포맷이면 커스텀 `<KeyPascal>QrPayloadStrategy` 로 교체했는지 확인. (QR 출력 ON/OFF 는 일반설정 토글이라 코드 변경 없음.)
- [ ] (입력 8 이 "예" 였다면) 일본/JPY 등은 `BrandMeta.currency`/`serverEnvironment` 로 처리됨. 추가로 다른 동작이 필요하면 `BrandFeature` + Strategy/Hook(라벨필터=`label_filter_strategy.dart`, 외부전송=`soundgraph_hook.dart`, QR페이로드=`qr_payload_strategy.dart`) 패턴 참고
- [ ] (입력 11 이 있었다면) **Sentry 알림 라우팅** — `SENTRY_AUTH_TOKEN` 발급 후 `sentry_alerts.py apply` 실행 → `list` 로 `[auto] <PREFIX> -> #채널` 규칙 생성 확인. **소급 발화 없음** → 해당 브랜드에서 새 에러 1건 유발해 전용 채널 도착 + test 채널 미도착 확인
