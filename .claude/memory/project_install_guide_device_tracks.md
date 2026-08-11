---
name: project-install-guide-device-tracks
description: 점주용 설치 가이드는 T2mini/D3mini 권한 순서가 달라 기기별 트랙 구조. 강조 오버레이 좌표는 이미지 기준 %라 캡션 추가 시 어긋남
metadata: 
  node_type: memory
  type: project
  originSessionId: d7ec74e3-2e48-4b8b-bb87-4e77fc2475bd
  modified: 2026-08-11T04:27:43.706Z
---

`docs/guide/Sunmi-appfit-agent-install-guide.html`(2026-08-11 커밋 bf11403)는 공통 1~3단계 → **기기별 트랙**(T2mini 4~6 / D3mini 4~8) → 공통 로그인 구조.

- 권한 순서가 기기마다 다름: T2mini = 파일 액세스 허용 → 권한필요/설정하기 → '다른 앱 위에 **그리기** 허용'(앱 지정 화면 직행, 목록 단계 없음). D3mini = 모든 파일 관리 허용 → **알림 허용** → 권한필요/설정하기 → 목록에서 Appfit 선택 → '다른 앱 위에 **표시** 허용'. 항목 이름·단계 수가 달라 단일 순서로 못 씀.
- 해상도: T2mini 1920×1080, D3mini 1280×800(16:10). 캡처 파일명에 기기를 표기해 구분.
- 강조는 캡처 위에 CSS `.hl` 절대배치 + `%` 좌표. **좌표는 부모 컨테이너 기준**이라 figure 안에 캡션을 추가하면 세로 %가 밀린다 → 이미지+오버레이를 전용 wrapper(`.step-shot`)로 감싸고 캡션은 그 바깥에 둘 것.

**Why:** 기기별 차이를 한 줄 문구로 뭉개면 점주가 없는 화면을 찾아 헤맨다. 좌표 함정은 겉보기엔 렌더가 멀쩡해 놓치기 쉽다.

**How to apply:** 캡처 교체·단계 추가 시 headless Chrome(`--headless=new --screenshot --window-size=980,11000`)으로 전체 렌더 후 강조 위치를 눈으로 검증. 좌표 산출은 PIL 로 사각형을 그려 미리 확인하면 빠르다. 관련: [[reference-brand-asset-large-canvas-bbox-crop]]
