# C4 모델 가이드 — 우리 프로젝트에 적용하는 방법

> 버전 0.1 (초판) · 2026-07-03
>
> 적용 저장소: `kiosk_v4`(원조) · `appfit_order_agent` · `kokonut_order_agent_v2` · `did`

---

## 1. C4 모델이란

**C4 모델**(Simon Brown 고안)은 소프트웨어 아키텍처를 **4단계 줌 레벨**로 그리는 다이어그램 체계다. 지도의 축척처럼, 독자가 필요한 만큼만 확대해서 본다. "하나의 만능 다이어그램"을 그리려다 아무도 못 읽는 그림이 되는 문제를 줌 분리로 해결한다.

| 레벨 | 이름 | 보여주는 것 | 독자 | 우리 파일 |
|------|------|------------|------|----------|
| **L1** | System Context | 우리 시스템 1개 + 사용자(Person) + 외부 시스템의 관계 | 비개발자 포함 전원 | `c4core-context.html` |
| **L2** | Container | 시스템 내부의 실행/논리 단위와 통신 방식 | 개발자·운영자 | `c4core-l2.html` |
| **L3** | Component | 컨테이너 내부의 주요 모듈(Provider·Service·Manager)과 의존 관계 | 해당 영역 작업자 | `c4core-l3-*.html` |
| **L4** | Code | 핵심 클래스 1개의 의존성·메서드·상태 상세 | 그 코드를 고칠 사람 | `c4core-l4-*.html` |

핵심 원칙 세 가지:

1. **모든 박스에 이름 + [기술] + 책임 한 줄** — 다이어그램만 보고 설명 없이 읽히게 한다.
2. **레벨을 섞지 않는다** — L1에 클래스명이 나오거나 L3에 외부 시스템 상세가 나오면 줌이 깨진 것.
3. **정확성 > 완전성** — 확인 안 된 컴포넌트를 그리지 않는다. 다이어그램의 거짓말은 문서의 거짓말보다 오래 산다.

여기에 우리는 정통 C4 외에 **views/ 별첨**을 추가로 둔다: 특정 도메인 흐름(주문 흐름, 출력 파이프라인, race 처리 등)을 시간축/플로차트로 그린 특화 뷰다. 정통 C4가 "구조"라면 별첨은 "동작"이다.

---

## 2. 우리 방식의 구현 — 손수 작성한 정적 HTML

mermaid·structurizr 같은 도구 대신 **의존성 없는 정적 HTML**을 손으로 작성한다. 브라우저로 열면 끝이고, 빌드 단계도 서버도 없다. 유일한 외부 의존은 Google Fonts(Inter + JetBrains Mono).

### 2.1 저장소별 폴더

| 저장소 | C4 폴더 | As-Is 문서 |
|--------|---------|-----------|
| kiosk_v4 | `kioskc4model/` (+ `posapic4model/`) | `docs/v4_architecture_proposal.md` 등 |
| appfit_order_agent | `agentc4model/` | `docs/AS-IS.md` |
| kokonut_order_agent_v2 | `kokonutc4model/` | `docs/AS-IS.md` |
| did | `didc4model/` | `docs/AS-IS.md` |

### 2.2 폴더 내부 구조

```
{프로젝트}c4model/
├── c4core.css            # L1~L4 공용 디자인 (전 저장소 동일 — 수정 금지)
├── c4core.js             # SVG 곡선 화살표 엔진 c4Graph(EDGES) (동일 — 수정 금지)
├── c4core-context.html   # L1 — 진입점. 여기서부터 연다
├── c4core-l2.html        # L2 — 컨테이너. 클릭하면 L3로
├── c4core-l3-*.html      # L3 — 컨테이너당 1페이지
├── c4core-l4-*.html      # L4 — 핵심 클래스 상세
└── views/
    ├── c4.css            # 별첨 공용 (수정 금지)
    ├── c4.js             # 탭 네비 — VIEWS[] 배열이 별첨 목록의 단일 정본
    └── c4-*.html         # 특화 뷰 (도메인 흐름)
```

### 2.3 탐색 동선

- **L1 중앙 노드 클릭** → L2 · **L2 컨테이너 클릭** → L3 · **L3의 `▶ L4` 셀 클릭** → L4
- 우하단 **zoom 인디케이터**(L1/L2/L3/L4)로 레벨 간 점프, 좌상단 back 링크로 상위 복귀
- L1 우측 **도크**에서 별첨 뷰로 이동, 별첨 안에서는 상단 탭으로 뷰 전환
- 노드는 드래그로 옮겨볼 수 있다(저장은 안 됨 — 좌표 확정은 HTML의 인라인 `left/top` % 수정)

---

## 3. 작성 규약 (새 페이지를 추가할 때)

### 3.1 색상 = 노드 타입

| 색 | 타입 | CSS 클래스 |
|----|------|-----------|
| 파랑 `#60a5fa` | 우리 시스템 / 내부 컨테이너 | `.center-node` `.container-node` |
| 에메랄드 `#34d399` | 사용자 (Person) | `.actor` |
| 보라 `#a78bfa` | 외부 시스템 | `.external` |
| 시안 `#22d3ee` | 하드웨어 | `.hardware` |
| 앰버 `#fbbf24` | 데이터 스토어 | `.datastore` |

엣지도 같은 색을 따르고, **점선 애니메이션은 비동기 채널**(WebSocket·TCP 소켓·Firestore 스트림)을 뜻한다.

### 3.2 표기 언어

노드명·클래스명·메서드명은 **영문**, 설명·엣지 라벨·범례·콜아웃은 **한국어**. 타입 태그는 `[Person]` `[External System]` `[Data Store · KV]` 형식.

### 3.3 id 규칙과 가장 흔한 버그

- L1 위성 노드 `n-*`, L2 컨테이너 `c-*`, 엣지 라벨 `el-*`
- `c4Graph([{from, to, type, label, dash}, ...])`의 모든 `from`/`to`/`label` 값에는 같은 파일 안에 대응하는 `id="..."`가 **반드시** 있어야 한다. 없으면 엔진이 그 엣지를 **조용히 건너뛴다**(에러 없음) — 엣지가 안 보이면 십중팔구 id 오타다.

### 3.4 레벨별 작법

- **L1/L2**: 절대 위치(`left/top` %) `.node` div + `c4Graph()` 엣지 선언. L2는 `.boundary`(점선 경계) + `data-href` 드릴다운.
- **L3**: 페이지마다 인라인 `<style>`로 맞춤 레이아웃(격자·2열·파이프라인). 공용 그래프 엔진을 쓰지 않는다.
- **L4**: 대상 Dart 소스를 **읽고 나서** 작성한다. 클래스 카드 + 의존성 grid + 메서드 아코디언(실존 시그니처만) + 상태/모델 entity 카드.
- **views**: `<header id="c4-hdr"></header>` 한 줄이면 탭이 자동 주입된다. 새 뷰 추가 시 `views/c4.js`의 `VIEWS[]` 배열에만 등록하면 전 뷰의 탭이 갱신된다.

### 3.5 하지 말 것

- 공용 자산(`c4core.css/js`, `views/c4.css/js`의 헤더 주입부) 수정 — 전 페이지가 공유한다
- 외부 CDN 스크립트·이미지 추가 — 오프라인에서 열리는 문서여야 한다
- 코드에서 확인 안 한 컴포넌트/메서드를 그리는 것 — 뺄지언정 지어내지 않는다

### 3.6 수정 후 검증 (필수)

`appfit_order_agent/agentc4model/verify_c4.py` 가 id 대조·링크 무결성·외부 의존성·VIEWS[] 등록을 자동 검사한다. 페이지를 추가·수정했으면 반드시 돌린다:

```bash
python3 agentc4model/verify_c4.py                    # 자기 폴더 검사
python3 agentc4model/verify_c4.py ../did/didc4model  # 다른 repo 폴더도 인자로 검사 가능
```

특히 §3.3의 "조용한 엣지 누락"은 이 스크립트만이 확실히 잡는다. 오류 0이 커밋 조건.

---

## 4. As-Is 문서와의 관계

각 저장소의 `docs/AS-IS.md`는 C4 뷰의 **텍스트 요약본**이다 (Outline 게시용 · GFM 표 중심). C4 HTML이 "지도"라면 As-Is 문서는 "지명 사전"이다. 아키텍처가 바뀌면 **둘 다** 갱신한다: 코드 → C4 뷰 → As-Is 문서 → Outline 재게시 순.

| 문서 | 위치 | 용도 |
|------|------|------|
| C4 HTML 뷰 | 각 repo `{이름}c4model/` | 구조·흐름 시각화, 온보딩·설계 리뷰 |
| As-Is 아키텍처 | 각 repo `docs/AS-IS.md` | Outline 게시, 검색 가능한 사실 표 |
| 본 가이드 | `appfit_order_agent/docs/C4_GUIDE.md` | C4 개념·작성 규약의 단일 정본 |
