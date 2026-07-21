---
name: reference_brand_logo_solid_bg_color_mask
description: 브랜드 로고 원본이 solid(불투명) 배경이면 docs alpha 매핑 대신 색상 마스크로 1-bit 변환
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1fe53070-80aa-4e25-b3f4-82a9749d1c80
  modified: 2026-07-21T04:56:35.223Z
---

브랜드 로고 원본 PNG가 **알파 없이 solid 배경**(예: PAIK 새 BI = 노란 배경 정사각 아이콘)이면 `docs/BRAND_ASSETS.md` §4.1 의 alpha 기반 패턴 A/B 매핑을 못 쓴다. 대신 **색상 마스크**를 쓴다: `ImageChops.subtract(b, r).point(lambda v: 0 if v>40 else 255)` → 파랑(브랜드 잉크)만 검정(0), 노랑/흰 knockout 은 흰 종이(255). 이후 파이프라인(NEAREST 다운샘플 → 50×50 흰 캔버스 중앙 paste → convert('1') BMP)은 docs 와 동일.

주의: 가로로 긴 워드마크를 50×50 에 넣으면 상하 여백 때문에 **검정비율이 13~16%로 낮게 나와도 획 자체는 굵어** 가독 양호할 수 있음 — 수치보다 5x 프리뷰 육안이 우선. docs §3.5 의 "13% 미만=너무 가늘" 는 여백 큰 크롭엔 오해 소지.

**영수증 로고는 컬러 원본을 검정으로 변환해 저장할 것** — 앱이 인쇄 시 `gray<128→검정`으로 이진화하지만, 저장 자산 컨벤션은 전 브랜드 검정/그레이스케일(mahataste `(0,0,0)`, mammoth `(48,48,48)`)이다. 파랑 워드마크를 그대로 두면 파란 PNG로 저장돼 어색(초기 실수, 사용자가 지적). 변환: 흰 평탄화→`convert('L')`→휘도 레벨 스트레치 `lo=min lum(~17~37)` 을 0으로 당겨 잉크는 순검정, 흰(종이+COFFEE knockout)은 255, AA는 회색 보존.

2026-07-21 PAIK BI 교체 결정 이력: 라벨=`Paik's` 필기체만 크롭(B안), 영수증=가로 워드마크 80×384 fit(151×80, 검정 변환), 세컨 모니터=투명 워드마크 `dm_paik.png` + 배경 `#FECE00`. 세컨 배경은 네이티브 `MainActivity.java setImage()` 가 전 브랜드 공통 흰색 하드코딩이라 `slug` 필드로 `"paik".equals(slug)` 스코핑해 첫 브랜드별 예외를 추가(타 브랜드 흰 배경 회귀 없음). 라벨 소스와 세컨/영수증 소스가 **다른 파일**이었음(정사각 아이콘 vs 가로 워드마크). 관련: [[project_variant_rename_japan_korea]] 의 매장ID 프리픽스 브랜드 해석.
