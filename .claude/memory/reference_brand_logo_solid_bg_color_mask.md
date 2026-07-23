---
name: reference_brand_logo_solid_bg_color_mask
description: 브랜드 로고 원본이 solid(불투명) 배경이면 docs alpha 매핑 대신 색상 마스크로 1-bit 변환
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1fe53070-80aa-4e25-b3f4-82a9749d1c80
  modified: 2026-07-23T00:30:23.248Z
---

브랜드 로고 원본 PNG가 **알파 없이 solid 배경**(예: PAIK 새 BI = 노란 배경 정사각 아이콘)이면 `docs/BRAND_ASSETS.md` §4.1 의 alpha 기반 패턴 A/B 매핑을 못 쓴다. 대신 **색상 마스크**를 쓴다: `ImageChops.subtract(b, r).point(lambda v: 0 if v>40 else 255)` → 파랑(브랜드 잉크)만 검정(0), 노랑/흰 knockout 은 흰 종이(255). 이후 파이프라인(NEAREST 다운샘플 → 50×50 흰 캔버스 중앙 paste → convert('1') BMP)은 docs 와 동일.

주의: 가로로 긴 워드마크를 50×50 에 넣으면 상하 여백 때문에 **검정비율이 13~16%로 낮게 나와도 획 자체는 굵어** 가독 양호할 수 있음 — 수치보다 5x 프리뷰 육안이 우선. docs §3.5 의 "13% 미만=너무 가늘" 는 여백 큰 크롭엔 오해 소지.

**영수증 로고는 컬러 원본을 검정으로 변환해 저장할 것** — 앱이 인쇄 시 `gray<128→검정`으로 이진화하지만, 저장 자산 컨벤션은 전 브랜드 검정/그레이스케일(mahataste `(0,0,0)`, mammoth `(48,48,48)`)이다. 파랑 워드마크를 그대로 두면 파란 PNG로 저장돼 어색(초기 실수, 사용자가 지적). 변환: 흰 평탄화→`convert('L')`→휘도 레벨 스트레치 `lo=min lum(~17~37)` 을 0으로 당겨 잉크는 순검정, 흰(종이+COFFEE knockout)은 255, AA는 회색 보존.

2026-07-21 PAIK BI 교체 결정 이력: 라벨=`Paik's` 필기체만 크롭(B안), 영수증=가로 워드마크 80×384 fit(151×80, 검정 변환), 세컨 모니터=투명 워드마크 `dm_paik.png` + 배경 `#FECE00`.

**2026-07-23 라벨 변경(B안 뒤집음):** 사용자 요청으로 PAIK `label_logo.bmp` 를 `Paik's` 크롭 대신 `receipt_logo.png` **전체**(151×80 가로 워드마크)에서 재생성. 원본이 RGB 흑백(알파 없음)이라 §4.1 alpha 매핑도 노랑-배경 색상 마스크도 아닌 **휘도 임계값** `L.point(0 if x<128 else 255)` → NEAREST 다운샘플 → 50×50 흰 캔버스 paste → `convert('1')` BMP (462B). 트레이드오프 확인·수용: 50×50 에선 `Paik's` 필기체만 판독되고 아래 `DABANG COFFEE`·`ベクスダバン` 작은 글자는 노이즈. **크기 조정(같은 세션 후속):** painter 가 BMP 를 항상 50×50 정사각형으로 stretch(`label_painter.dart` drawImageRect, src전체→50×50) 하고 원본 워드마크는 4변 여백 0 이라, 가로형을 키우는 유일한 방법은 **세로 stretch(위아래 여백 축소)**. 폭50 고정·높이 26→**32px(+23%)** 로 resize 후 중앙 paste 채택 → 검정 18%. 더 키우려면 H 만 올리면 됨(34=+30% 등).

**2026-07-23 영수증 로고 교체:** `receipt_logo.png` 를 `~/Documents/Group.png`(512×149 RGBA, 순검정 잉크 on 투명, "Paik's + DABANG/COFFEE 반전박스 + ペクスダバン" 넓은 락업) 로 대체. §4.2 표준(흰 평탄화 → LANCZOS 80×384 fit) → **275×80 RGB**, 1비트 검정 28%, 획 온전·판독 양호. 잉크가 이미 (2,2,2) 검정이라 색변환 불필요. 주의: 현행 `label_logo.bmp` 는 **이전** 151×80 receipt_logo 에서 파생된 것이라 이번 교체와 무관하게 그대로 둠(별개 자산). 새 락업에서 라벨 재파생 시 aspect 3.44 라 50×50 에서 더 압축됨. 실기 출력으로 최종 판단 예정(불만족 시 `git checkout` 원복). 코드 변경 없음(표준 파일명 + label_painter lazy 재로드). 세컨 배경은 네이티브 `MainActivity.java setImage()` 가 전 브랜드 공통 흰색 하드코딩이라 `slug` 필드로 `"paik".equals(slug)` 스코핑해 첫 브랜드별 예외를 추가(타 브랜드 흰 배경 회귀 없음). 라벨 소스와 세컨/영수증 소스가 **다른 파일**이었음(정사각 아이콘 vs 가로 워드마크). 관련: [[project_variant_rename_japan_korea]] 의 매장ID 프리픽스 브랜드 해석.
