---
name: project_mhst_brand_image_2026_08
description: MHST(맘모스커피) 라벨/영수증/로그인/D3mini 세컨모니터 이미지 4종 교체 + D3mini 영상/이미지 우선순위 반전
metadata: 
  node_type: memory
  type: project
  originSessionId: 62a91fcc-7494-4cc6-b3b7-fa3db9cbcda8
  modified: 2026-08-03T06:50:50.777Z
---

2026-08-03, `fix/label-duplicate-on-ack-timeout` 브랜치 위에서 진행(무관한 다른 작업과 같은 브랜치에 공존 — 커밋 시 분리 주의). 맘모스커피 새 브랜드 키트(`~/Downloads/MAMMOTH COFFEE Logo/`)로 4개 자산 교체:
- `assets/images/brand/mammoth/label_logo.bmp` ← `Mammoth_Symbal_Black.png` (검정비율 42%)
- `assets/images/brand/mammoth/receipt_logo.png` ← `Mammoth_English Logotype Single-line_Black.png` (384×29px, 매우 얇지만 볼드체라 1비트 프리뷰로 가독 확인함)
- `assets/images/brand/mammoth/logo.png`(신규, `.svg` 대체) ← `Mammoth_Symbol + English Logotype_White.png` — `lib/constants/brand_theme.dart`의 `logoAsset` 갱신, `BrandLogo` 위젯이 확장자로 svg/png 자동분기라 위젯 코드 변경 없음
- `android/app/src/main/res/drawable/dm_mammoth.png` ← `Mammoth_Symbol + English Logotype_Black.png` (1600×1051로 다운스케일)

원본이 4500×4500 대형 캔버스+큰 여백이라 표준 파이프라인 전에 bbox 크롭 전처리 필요했음 — 기술 세부는 [[reference_brand_asset_large_canvas_bbox_crop]].

**사용자 확인으로 원 요청과 달라진 두 가지:**
1. 로그인화면: 원래 지정한 `Symbol + Korean Logotype_Black`은 로그인 배경(#5B443B 어두운 브라운)에서 안 보여서(검정 on 어두운배경), 사용자가 `Symbol + English Logotype_White`로 변경 지정.
2. D3mini 세컨모니터: 기존 `dm_mammoth.mp4`가 네이티브 로직상 이미지보다 항상 우선이라 PNG 교체만으론 화면에 반영 안 됨. 사용자가 영상 삭제 대신 **우선순위 반전(이미지>영상)**을 요청 → `MainActivity.java` `DualMonitorPresentation.onCreate()`(auto-default 분기만, 운영자 명시선택 `"video"`/`"image"` 모드는 그대로) + `lib/widgets/settings/settings_dual_monitor_section.dart` `_effectiveMode()`(네이티브 규칙 미러링 지점, 반드시 같이 바꿔야 설정화면 하이라이트 안 어긋남) 양쪽 다 image-first로 반전. mp4를 가진 브랜드는 mammoth 유일이라 다른 브랜드(paik/milkypresso/tokyoplatz/mahataste) 동작엔 영향 없음 — 전역 변경이지만 사실상 mammoth-only 효과.

**상태**: 실기기(Sunmi D3 mini, MHST 매장) 검증 완료(사용자 확인) — 단, 로그인 로고를 크롭만 하고 다운스케일 없이(4125×2709 그대로) 저장해서 실기기에서 깨짐 발견. 975×640(42KB)로 재축소해서 해결. 상세: [[reference_brand_asset_large_canvas_bbox_crop]] 후속 함정 섹션. 커밋은 아직 안 함 — `fix/label-duplicate-on-ack-timeout` 브랜치에 무관한 다른 작업과 같이 있어 분리 필요.
