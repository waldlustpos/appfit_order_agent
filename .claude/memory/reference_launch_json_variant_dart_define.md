---
name: reference_launch_json_variant_dart_define
description: "launch.json standalone 구성은 --flavor 만으로 부족, Windows 는 --dart-define=APPFIT_VARIANT 필요"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 3d56811f-efea-4095-80d5-295ebe76ea65
---

`.vscode/launch.json` 의 변형(update/standalone) 구분은 **반드시 `--dart-define=APPFIT_VARIANT=<variant>` 로** 한다. `--flavor` 는 Android/iOS 전용이라 **Windows 에선 무시**되고, `AppEnv.isStandalone` 은 `APPFIT_VARIANT` dart-define 만 참조(기본값 `update`)한다. 따라서 `--flavor standalone` 만 있는 구성으로 Windows run 버튼을 누르면 조용히 update 변형으로 떨어진다(`isStandalone==false`).

증상 사례: standalone 전용 버블 그라데이션이 Windows "standalone (debug)" run 버튼에서 반영 안 됨 → 6개 구성 모두에 `--dart-define=APPFIT_VARIANT=update|standalone` 추가로 해결(2026-06-26, 확인 완료).

주의: `app_env.dart` 의 `static const isStandalone` 분기는 **cold restart** 로만 재평가됨(hot-reload/restart 무효). 관련: [[project_app_env_gitignored_variant]], [[feedback_hot_reload_cold_restart]], [[project_dual_variant_build]].
