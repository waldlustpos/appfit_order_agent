---
name: reference-font-coverage-pretendard-notosansjp
description: Pretendard 와 NotoSansJP 의 커버리지·숫자폭 실측 — 한 벌로는 ja/ko 를 못 덮는다
metadata: 
  node_type: memory
  type: reference
  originSessionId: 63d816ff-a848-4835-861f-76dd56b13cbb
  modified: 2026-08-28T06:51:25.377Z
---

번들 폰트 두 벌의 커버리지가 **상호 배타적**이다. cmap 직접 파싱 실측(2026-08-28):

| | 한글 `가` | 일본어 한자 `円税領直骨` | 숫자 advance |
|---|---|---|---|
| **Pretendard-Regular.otf** | ✅ | ❌ **없음** | **불균등** 898~1278 (upm 2048) · `tnum` 피처 있음 |
| **NotoSansJP** | ❌ **없음** | ✅ (17,936 글리프) | **균등** 555 (upm 1000) · `tnum` **없음** |

**귀결 1 — `fontFamilyFallback` 은 선택이 아니다.** ja/ko 를 함께 서빙하는 앱에서 한 벌만
지정하면 반드시 시스템 폴백이 끼어들고, Android 폴백이 Noto Sans CJK **SC(중국어 간체)** 로
잡히면 直/骨/類 자형이 일본 관습과 달라진다. `appfit_order_agent` 가 `fontFamily: 'Pretendard'`
만 지정하고 fallback 을 안 둔 상태라 **ja 문자열 484개 중 412개(85%)가 혼합 렌더**된다 —
운영 중인 실제 이슈다. `label_painter.dart` 도 Pretendard 로 래스터화하므로 라벨·영수증 이미지에도 해당.

**귀결 2 — `FontFeature.tabularFigures()` 는 항상 붙여도 안전하다.** NotoSansJP 는 이미 등폭이라
no-op 이고 Pretendard 는 `tnum` 이 실제로 적용된다. 금액을 세로로 나열하는 화면에 필수.

**귀결 3 — google/fonts 는 NotoSansJP 가변폰트만 배포**(`NotoSansJP[wght].ttf`, 9.6MB)하는데
**기본 축 값이 wght=100(Thin)** 이다. `fontVariations` 를 빠뜨린 TextStyle 이 전부 얇게 렌더되는
함정이라, `python3 -m fontTools.varLib.instancer 'NotoSansJP[wght].ttf' wght=400` 로 정적 인스턴스를
뽑아 쓰는 편이 낫다(2종 11.5MB — 가변보다 1.9MB 크지만 footgun 이 사라진다).

[[project-simple-pos-jp-pilot]] 에서 이 구성을 채택했고 실기기(D3 MINI)에서 혼합 없음을 확인했다.
