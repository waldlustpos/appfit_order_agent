---
name: project-log-server-plan
description: LocalServerService를 상품 상태 API에서 로그 파일 다운로드 서버로 재구성하는 계획 수립 완료(미구현)
metadata: 
  node_type: memory
  type: project
  originSessionId: 1d9e2ca4-a232-4481-95a6-d061d5493790
---

`lib/services/local_server_service.dart` 전면 재구성 계획을 2026-07-06에 수립해 `/Users/kimsungchun/.claude/plans/tender-noodling-bumblebee.md`에 저장함. 사용자가 "플랜만 저장하고 우선 마무리하자"고 해서 **구현은 아직 착수하지 않음**.

**Why:** 기존 기능(`GET /api/product/{productId}` 상품 판매상태 조회 JSON API, 키오스크용)을 완전히 걷어내고, PC/기기에 쌓인 로그 파일(`Documents/appfit/appfit_YYYY-MM-DD.txt`, Windows/Android 공통 규격, 6개월 보관)을 브라우저로 조회·다운로드하는 순수 개발용 도구로 교체하기로 함.

확정된 설계 방향(다시 물어볼 필요 없음):
- 설정 화면의 기존 ON/OFF 토글 UX는 유지(제거 안 함, 문구만 "로그 서버"로 교체)
- 브라우저 접속 시 날짜별 목록 페이지 → 개별 파일 클릭 다운로드 (즉시 다운로드/zip 일괄 방식 아님)
- Android 로그 디렉토리는 네이티브 코드 추가 없이 Dart에서 두 후보 경로(`/storage/emulated/0/Documents/appfit`, `getExternalStorageDirectories()+/logs`)를 직접 확인하는 방식으로 해결 — `feature/remote-log-collection` 브랜치(미병합)가 썼던 `getLogDirPath()` 네이티브 추가 방식은 의도적으로 따르지 않음

**How to apply:** 이 작업을 재개하면 위 계획 파일을 먼저 읽고 이어서 구현. 호출부 9곳(home_screen.dart/settings_screen.dart/login_screen.dart/settings_right_panel.dart/product_provider.dart) 조사 결과와 파일명 검증 정규식·HTTP 헤더 설계 등 구현 세부사항도 계획 파일에 이미 정리되어 있어 재조사 불필요.
