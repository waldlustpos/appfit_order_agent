# 브랜드별 인쇄 자원 가이드

매장 ID prefix에 따라 라벨/영수증 프린터에 다른 로고 자원을 사용하는 구조와, 새 브랜드 추가 시 자산 변환 절차를 정리한다.

## 1. 자원 분기 구조

- 헬퍼: [lib/utils/brand_assets.dart](../lib/utils/brand_assets.dart)
- 분기 기준: [`PreferenceService.isMHSTStoreId`](../lib/services/preference_service.dart) / `isTPCPStoreId` — 매장 ID prefix
- 캐시 무효화: `label_painter.dart` / `external_receipt_printer.dart` 양쪽이 매 호출마다 `BrandAssets.{label,receipt}LogoPath`를 캐시된 path와 비교 → 다르면 자동 재로드 (lazy invalidation). 별도 후크 불필요.

| 브랜드 | ID prefix | 라벨 로고 | 영수증 로고 |
|---|---|---|---|
| tokyoplatz | `TPCP` | `assets/images/brand/tokyoplatz_label_logo.bmp` | (없음 — null 분기) |
| mammoth | `MHST` | `assets/images/brand/mammoth_label_logo.bmp` | `assets/images/brand/mammoth_receipt_logo.png` |
| 기타/미로그인 | — | tokyoplatz로 fallback | null |

영수증 로고가 null이면 ESC/POS 빌더([receipt_escpos_builder.dart](../lib/services/receipt_escpos_builder.dart))의 `if (logoImageBytes != null)` 가드로 자동 skip.

## 2. 라벨 로고 BMP 사양

| 항목 | 값 |
|---|---|
| 포맷 | PC bitmap, Windows 3.x format |
| 비트심도 | 1-bit (단색, 2-color palette: black/white) |
| 해상도 | 50×50 px (정사각형 권장) — tokyo는 50×55로 약간 squish됨 |
| DPI | 3780 px/m (≈ 96 DPI) |
| 파일 크기 | ~ 462~502 B |
| palette[0] | black (0x000000) |
| palette[1] | white (0xFFFFFF) |
| 픽셀 의미 | 0=검정 잉크, 1=흰 종이 (인쇄 안 됨) |

라벨 painter는 캔버스 50×50 영역(`logoWidthDefault=50`, `logoHeight=logoWidthDefault`)에 로고를 그린다. 정사각형이 아닌 비율은 squish되므로 BMP 자체를 50×50 캔버스 + 흰 패딩으로 만들 것.

## 3. 핵심 노하우 (시행착오 산출물)

### 3.1 `FilterQuality.none` 필수 — 안티앨리어싱 노이즈 방지

커밋 [`6959307`](https://github.com/.../commit/6959307) `fix(print): use FilterQuality.none for label logo to prevent binarization distortion on older Android versions`

`canvas.drawImageRect`로 1-bit BMP를 50×50 영역에 그릴 때 [`FilterQuality.high`](../lib/utils/print/label_painter.dart) 보간을 쓰면 픽셀 경계에 회색 그라데이션이 생기고, 라벨 프린터(Caysn SDK)가 이를 디더링으로 이진화하면서 노이즈/얼룩으로 변환된다. **반드시 `FilterQuality.none`(NEAREST 보간)** 사용. label_painter.dart:117 참조.

### 3.2 PNG → BMP 변환 시 alpha 임계값 방향 주의

Figma 등에서 export된 PNG는 두 가지 디자인 패턴이 섞여 들어온다.

**패턴 A: 일반 PNG** — 도형은 alpha 불투명(255), 배경은 alpha 투명(0). 흰 배경에 합성하면 도형이 그대로 보임.
- 변환: `alpha > 128 → 검정(0)`, `alpha ≤ 128 → 흰(255)`

**패턴 B: 어두운 화면용 export** — "검정 배경 + 흰색 로고" 디자인을 export하면 흰 도형이 alpha 255, 검정 배경 영역이 alpha 0인 형태가 나온다. 흰 배경 합성 시 완전 흰색으로 보여 헷갈리기 쉽다.
- **여전히 변환 방향은 패턴 A와 동일**: alpha 불투명 영역이 디자이너가 페인팅한 진짜 도형. `alpha > 128 → 검정(0)`.

판별 팁:
1. 검정 배경에 합성한 PNG를 시각화 — 흰색으로 보이는 영역이 디자이너의 페인팅 영역(진짜 도형).
2. 불투명 픽셀의 평균 luminance — 255(흰)이면 패턴 B, 0(검정)이면 일반 검정 도형.
3. tokyo 참조값: 검정 픽셀 비율 **65%**. 새 브랜드 BMP가 변환 결과 10% 미만 또는 90% 초과면 alpha 임계값 방향이 반대일 가능성 높음. 일반적 로고는 **30~65% 검정** 범위.

### 3.3 비율 유지 + 50×50 캔버스 패딩

가로로 긴 디자인(예: mammoth 128×85)을 50×50으로 강제 resize하면 squish 변형. 50px 폭 기준 비율 유지 NEAREST 다운샘플 후, 50×50 흰 캔버스에 위아래 패딩 추가하여 중앙 정렬.

### 3.4 NEAREST 다운샘플만 사용

원본 PNG 다운샘플 시 BICUBIC/LANCZOS 등 안티앨리어싱 보간을 쓰면 회색 픽셀 발생 → threshold 이진화에서 노이즈. **PIL `Image.NEAREST`** 만 사용. 결과적으로 픽셀 거칠음은 있으나 라벨 프린터의 1-bit 출력 특성상 더 깔끔.

### 3.5 검정 비율 가독성 가이드

- 13% 미만: 너무 가늘어 작은 디테일이 라벨에서 사라짐
- 30~65%: 가독성 양호 (tokyo·mammoth 모두 이 범위에 안착)
- 65% 초과: 너무 무거움, 인접 영역이 뭉칠 수 있음

## 4. 새 브랜드 추가 절차

다음 단계로 진행. 자동화 스크립트는 없으며 운영자가 수동 실행.

### 4.1 자산 파일 변환 (PIL 스크립트)

```bash
python3 <<'EOF'
from PIL import Image

SRC = '/path/to/원본_logo.png'
DST = '/Users/kimsungchun/Documents/GitHub/appfit_order_agent/assets/images/brand/<brand>_label_logo.bmp'

src = Image.open(SRC).convert('RGBA')
_, _, _, alpha = src.split()

# 패턴 A 기본 매핑 — 도형(alpha 불투명) → 검정 잉크
mask_L = alpha.point(lambda x: 0 if x > 128 else 255, mode='L')

# 비율 유지: 폭 50px 기준
src_w, src_h = mask_L.size
new_w = 50
new_h = round(src_h * 50 / src_w)
if new_h > 50:  # 세로로 더 긴 디자인이면 높이 기준으로
    new_h = 50
    new_w = round(src_w * 50 / src_h)
resized = mask_L.resize((new_w, new_h), Image.NEAREST)

# 50×50 흰 캔버스 중앙 paste
canvas = Image.new('L', (50, 50), 255)
canvas.paste(resized, ((50 - new_w) // 2, (50 - new_h) // 2))
canvas.convert('1').save(DST, format='BMP')

# 검정 비율 확인 (가독성 가이드)
pixels = list(canvas.convert('L').getdata())
black = sum(1 for p in pixels if p < 128)
print(f'black: {black}/{len(pixels)} ({black*100//len(pixels)}%)')
EOF

# 결과 검증 — tokyo와 동일한 포맷 확인
file assets/images/brand/<brand>_label_logo.bmp
# 기대: PC bitmap, Windows 3.x format, 50 x 50 x 1, ..., resolution 3780 x 3780 px/m
```

**변환 후 검정 비율이 의외로 낮거나(10% 미만) 높으면(85% 초과)** 패턴 B 가능성 — 다음으로 시도:

```python
# 패턴 B 역매핑 — cut-out(alpha 투명) 영역 → 검정 잉크
mask_L = alpha.point(lambda x: 255 if x > 128 else 0, mode='L')
```

판단이 어려우면 두 옵션 모두 BMP로 만들고 PNG 5x preview로 시각화 비교.

### 4.2 영수증 로고 추가 (선택)

영수증 로고가 필요한 브랜드는 8-bit PNG 그대로 사용 가능. `assets/images/brand/<brand>_receipt_logo.png`로 배치. ESC/POS 빌더가 raster 변환을 알아서 처리한다. 권장 크기 ~ 200~400 px 폭 (실제 ESC/POS 빌더의 다운샘플 로직에서 처리).

영수증에 로고를 출력하지 않는 브랜드는 [BrandAssets.receiptLogoPath](../lib/utils/brand_assets.dart)에서 해당 분기를 `null` 반환하면 됨 — 빌더 자체 가드로 자동 skip.

### 4.3 코드 변경

1. [lib/services/preference_service.dart](../lib/services/preference_service.dart): `isXXXXStoreId` / `isXxxxStore` 메서드 추가 (tokyo의 `isTPCPStoreId`, mammoth의 `isMHSTStoreId` 패턴 참고)
2. [lib/utils/brand_assets.dart](../lib/utils/brand_assets.dart): 새 브랜드 상수 + `labelLogoPath` / `receiptLogoPath` 분기 추가

### 4.4 검증

```bash
flutter analyze
flutter clean && flutter pub get  # 새 asset 인식 위해
```

실기기 시나리오:
- 해당 브랜드 매장 ID로 로그인 → 설정 > 라벨/영수증 테스트 출력
- 다른 브랜드 매장으로 전환 후 다시 출력 → 캐시 자동 무효화 확인
- TPCP/MHST/기타 prefix 매장 각각에서 출력물 비교

## 5. 사례 기록

### tokyoplatz (TPCP)
- 라벨: 50×55 1-bit BMP (정사각형 50×50보다 살짝 세로 김 — painter에서 50×50으로 squish됨)
- 검정 비율: 65% (굵은 글자 디자인)
- 영수증: 없음 (null 분기)

### mammoth (MHST)
- 라벨: 50×50 1-bit BMP, 462B, 검정 비율 52%
- 원본 PNG: 128×85 RGBA, **패턴 B 형태로 export됨** (검정 배경 + 흰 로고 디자인에서 도형이 alpha 불투명 흰색으로 저장)
- 변환 시행착오 — 시각만으로 패턴 판별이 어려웠음:
  - 1차: 패턴 A 매핑 시도 → 라벨에서 색상 반대로 출력
  - 2차: 패턴 B 역매핑 시도 → 라벨에서 색상 또 반대
  - 3차: 패턴 A로 복귀, 검정 비율 52%(tokyo 65%와 근접) 확인하고 적용 → 성공
- 영수증: 기존 `assets/images/logo.png`를 `mammoth_receipt_logo.png`로 리네임만 이동
