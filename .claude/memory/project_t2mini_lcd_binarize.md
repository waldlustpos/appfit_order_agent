---
name: project_t2mini_lcd_binarize
description: T2mini 전면 LCD(MHST 브랜드 대기화면) 텍스트 vs 이미지 비교 검증 + 곡선 튐 도트 이진화 수정
metadata: 
  node_type: memory
  type: project
  originSessionId: 01850203-8990-43a3-993a-bd07d6dee078
  modified: 2026-08-06T01:43:47.196Z
---

`MainActivity.java`의 `refreshBrandLcd()`가 MHST(맘모스커피) 매장일 때 전면 고객용 LCD(128×40 기준,
Sunmi `sendLCDBitmap`/`sendLCDDoubleString`)에 무엇을 띄울지 실기기로 비교 검증했다.

**경과**: 로고 비트맵(`mmth_print_logo.bmp`, 341×24 워드마크 "MAMMOTH COFFEE")을 128×40 캔버스에
비율유지 축소하면 세로 ~9px로 얇아지는 문제가 있어, 임시 플래그(`LCD_PREFER_TEXT`)로 텍스트("MAMMOTH"/
"COFFEE" 두 줄, `sendLCDDoubleString` 재사용)와 나란히 실기기 비교함. **결론: 이미지가 더 적합** —
텍스트 경로/플래그는 코드에 흔적 없이 제거(원래 비트맵 우선 구조로 복귀).

**후속 발견**: 이미지 방식은 잘 보였지만 O/C 처럼 윗부분이 곡선인 글자의 12시 방향에 불필요한 도트 1개가
찍히는 아티팩트 발견. 원인 조사: `mmth_print_logo.bmp` 원본 자체가 이미 안티에일리어싱(회색 경계 픽셀
253종, PIL 로 확인)된 워드마크였고, Java 쪽 `buildLcdLogoBitmap()`도 bilinear 축소(`Paint.ANTI_ALIAS_FLAG
| FILTER_BITMAP_FLAG`)라 회색 픽셀이 그대로 `sendLCDBitmap`으로 넘어감 → Sunmi SDK 내부 흑백(1bpp)
변환(디더링 추정)이 곡선 정점의 얇은 회색 그라디언트에서 튐 도트를 만든 것으로 추정.

**수정**: `buildLcdLogoBitmap()` 합성 직후 새 헬퍼 `binarizeForMonoLcd()`로 RGB 휘도 128 기준 하드
스레숄드(흑/백 강제 이진화)를 적용해 SDK 에 회색 픽셀이 아예 넘어가지 않도록 함. 텍스트/로고 같은
저해상도 흑백 콘텐츠는 디더링보다 하드 스레숄드가 아티팩트 없이 더 선명하다는 게 핵심 판단.

**상태**: 사용자가 실기기 확인 후 "현재 상태정도면 만족"으로 완료 승인. 커밋은 아직 안 함(사용자가 명시
요청 시 진행).

**교훈**: 저해상도 monochrome LCD/프린터에 비트맵을 보낼 때, 소스 이미지가 브랜드 자산 표준 파이프라인
(`docs/BRAND_ASSETS.md` §4.1, 라벨 BMP 등)을 거치지 않고 그레이스케일/안티에일리어싱이 섞인 채로 있으면
다운스트림 SDK 디더링이 예측 못한 아티팩트를 만들 수 있음 — 이런 출력 경로는 소스 자체의 비트 심도를
먼저 확인하고, 필요하면 우리 쪽에서 명시적으로 이진화해 넘기는 게 안전.
