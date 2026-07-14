---
name: reference_impeller_flag_reports_optout
description: EnableImpeller=true 매니페스트 플래그가 런타임에서 Impeller opt-out(→Skia)으로 보고됨. Flutter 업그레이드 시 구형 기기 렌더러 절벽 리스크.
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6fba2735-4ee5-4cd1-931f-ef0298454aa9
---

`AndroidManifest.xml` 의 `io.flutter.embedding.android.EnableImpeller="true"`(주석: "Explicitly enable Impeller to avoid opt-out warning")는 **의도대로 동작하지 않는다.** T2mini_s(Adreno 505, Android 7.1, Flutter 3.38.4) 실기기 로그에서 엔진이 `[IMPORTANT:shell.cc(527)] Impeller opt-out deprecated. The application opted out of Impeller by ... the EnableImpeller AndroidManifest.xml entry` 를 매 콜드스타트 출력하고, Impeller 백엔드 성공 마커(`Using the Impeller rendering backend`)는 로그에 전무. 즉 엔진은 이 앱을 **Impeller opt-out(=Skia GL 렌더링)** 으로 보고. 소스/병합/패키지 매니페스트 모두 value="true" 확인했는데도 그러함.

**의미:** "지금까지 구형 기기에서 문제 없음"의 유력한 이유 = 검증된 성숙한 Skia 경로를 타고 있어서. 반대로 **잠재 절벽**: Skia는 곧 제거 예정("going to go away in an upcoming Flutter release")이라, Flutter를 Skia 제거 버전으로 올리면 필드 다수 구형 기기가 **처음으로 Impeller-GLES로 강제 전환**되며 미검증 상태가 됨.

**How to apply:** Flutter 업그레이드 전 반드시 구형 기기(Adreno 505급)에서 Impeller-GLES 실렌더 검증. 확정 A/B는 플래그 제거/false 빌드와 로그 비교로. 잔여 모호성: 이 "opted out" 메시지가 value=true에도 뜨는 게 (a)실제 Skia인지 (b)플래그 자체 deprecation 오표기인지는 A/B로만 100% 확정 — 단 권고(사전 Impeller 검증)는 양쪽 해석에서 동일하게 유효. [[project_dual_variant_build]] 와 함께 렌더러/빌드 정합성 점검 대상.
