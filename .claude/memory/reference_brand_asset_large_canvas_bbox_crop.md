---
name: reference_brand_asset_large_canvas_bbox_crop
description: 브랜드 로고 원본이 대형 정사각 캔버스+큰 여백이면 표준 변환 파이프라인 전에 alpha bbox 크롭 필수
metadata: 
  node_type: memory
  type: reference
  originSessionId: 62a91fcc-7494-4cc6-b3b7-fa3db9cbcda8
  modified: 2026-08-03T06:50:38.432Z
---

`docs/BRAND_ASSETS.md` §4.1 PIL 스크립트(라벨 BMP)와 `tool/gen_receipt_logo.dart`(영수증 PNG) 둘 다 **입력 PNG가 이미 타이트하게 크롭돼 있다는 전제**로 짜여 있다 — 캔버스 전체를 그대로 리사이즈할 뿐 자체 bbox 크롭을 하지 않는다. 기존 브랜드 소스(mammoth 구버전 128×85, mahataste 246×217 등)는 실제로 그렇게 타이트했지만, 브랜드 키트에 따라 **4500×4500 같은 대형 정사각 캔버스에 로고가 15~20%만 차지**하는 형태로 export되는 경우가 있다(2026-08 MHST 새 브랜드 키트). 이걸 그대로 표준 파이프라인에 넣으면:
- 라벨 BMP: 캔버스 전체(거의 1:1)가 50×50에 눌려 들어가면서 실제 도형이 한쪽 구석에 점처럼 작아짐
- 영수증 PNG: `gen_receipt_logo.dart`가 전체 캔버스 크기로 80×384 박스 fit을 계산해 완전히 잘못된(거의 빈 화면) 결과가 나옴 — 특히 원본이 가로로 긴 한 줄 워드마크인데 정사각 캔버스에 담겨 있으면 치명적

**해결**: 표준 파이프라인 실행 전에 alpha 채널 `getbbox()`로 콘텐츠 영역을 구해 3~4% 여백을 더해 먼저 크롭한 임시 PNG를 만들고, 그 크롭본을 src로 표준 스크립트/도구에 넣는다. 패턴 A/B 판별(§3.2)은 크롭 여부와 무관 — bbox 크롭은 그 이전 단계.

판별 신호: 원본 PNG 크기가 정사각(가로=세로)이고 파일 크기가 로고치고 과하게 크면(수백KB~수MB급 4500px대) 의심. `Image.open(src).convert('RGBA').split()[3].getbbox()`로 실제 콘텐츠 영역과 캔버스 크기를 비교해 여백 비율을 먼저 확인할 것.

**후속 함정(2026-08-03 실기기에서 발견): bbox 크롭만으로 안 끝남 — 크롭 후에도 다운스케일 필수.** 라벨(50×50)·영수증(80×384 박스 fit)은 파이프라인 자체가 작은 출력 크기를 강제해서 문제없지만, **로그인 로고(`BrandTheme.logoAsset` → `BrandLogo` 위젯, PNG 분기)처럼 리사이즈 로직이 없는 대상**은 크롭 결과(예: 4125×2709, alpha bbox 크롭만 하고 다운스케일 안 함)를 그대로 저장하면 실기기(Sunmi D3 mini)에서 로그인 화면 로고가 **깨짐**으로 나타났다. Flutter `Image.asset`의 `cacheHeight`(런타임 디코드 다운샘플)가 있어도 원본 픽셀 크기 자체가 GPU 텍스처 한도(보통 4096px)에 근접/초과하거나 저사양 기기 디코딩 부담이 크면 깨진다. **해결**: 크롭 후 표시 높이(`BrandLogo(height: 120)`)의 hi-DPI 헤드룸을 감안해 목표 높이 500~700px 선으로 LANCZOS 다운스케일 후 저장(마모스 사례: 4125×2709 → 975×640, 42KB). D3mini 세컨모니터 이미지(`dm_mammoth.png`, 네이티브 drawable)는 애초에 1600px로 다운스케일해서 저장했기 때문에 이 문제가 없었음 — 리사이즈 로직 없는 asset은 전부 사전에 크기를 맞춰야 한다는 게 일반 원칙.

관련: [[reference_brand_logo_solid_bg_color_mask]] (같은 §4.1 파이프라인의 다른 함정 — solid bg는 alpha 매핑 자체가 안 통함), [[project_mhst_brand_image_2026_08]] (이 문제를 처음 발견한 세션).
