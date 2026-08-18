---
name: feedback_brand_artifact_visual_only
description: "브랜드 전용 빌드는 화면 요소(초기 테마·앱 이름·아이콘)만 다르다 — 아티팩트/매장 브랜드가 어긋나도 안내·경고·제약을 두지 않는다"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-08-18T00:00:00.000Z
---

브랜드 전용 아티팩트(Tier 1, 현재 매머드)로 **타 브랜드 매장에 로그인해도 아무 문구도 띄우지 않는다.** 반대 방향(공통 앱 + 매머드 매장)도 마찬가지다. **로그인에 제약을 두지 않는 것이 원칙**이며, 모든 로직은 아티팩트와 무관하게 완전히 동일하고 전용 빌드가 다른 것은 초기 테마·앱 이름·런처 아이콘 같은 **화면 요소뿐**이다.

**Why**: 2026-08-18 사용자 지시로 오설치 안내 배너를 기능째 삭제했다(`BrandInstallBanner` 위젯 · `brandInstallMismatchProvider` · `BrandInstallMismatch` enum · i18n `common.brand_install.*` 3로캘 · home/kds 삽입부). 원래 "차단 아닌 안내"로 설계됐지만, 브랜드 동작이 100% 런타임(`BrandRegistry`)이라 어긋남의 실제 증상이 "런처 아이콘·이름이 브랜드와 다름"뿐이었고, 매장 입장에서는 정상 동작 중에 뜨는 경고 = 소음이었다. 이 삭제로 `brand_provider.dart` 는 `BuildBrand` 를 더 이상 참조하지 않아 `test/config/build_brand_scope_test.dart` 화이트리스트에서도 빠졌다.

**How to apply**: 아티팩트와 매장 브랜드의 불일치를 근거로 배너·다이얼로그·로그인 차단·기능 게이팅을 새로 만들지 말 것. 브랜드로 갈리는 동작은 전부 `BrandRegistry` 런타임 정본에 두고, `BuildBrand` 는 applicationId·런처 label/icon·OTA 채널·로그인 전 테마 프리시드까지만 손댄다. "아티팩트 정체성 vs 런타임 설정값" 구분은 [[feedback_flavor_preseed_vs_explicit_choice]], 티어 체계 전반은 [[project_mammoth_dedicated_build]].
