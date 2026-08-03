# 원격 화면제어 확장 — 공수 분석

Fleet 관제([DEVICE_MONITORING.md](DEVICE_MONITORING.md))를 **원격 화면제어 + 파일탐색기 다운로드**로 확장할 때의 공수를 산정한 문서.

> **상태: 분석만 완료(2026-08-03), 실행 착수 없음.** 다음 행동은 코딩이 아니라 §10 의 결정 게이트 실험 3개다.
>
> TeamViewer/AnyDesk 급 전기능이 아니라 화면제어·파일다운로드 2개로 범위를 제한한 전제다.

**확정된 전제**

| 축 | 결정 | 파급 |
|---|---|---|
| 사용 시나리오 | **무인 원격 점검** (사람이 동의창을 눌러줄 수 없음) | Android 실현 가능성의 결정 변수 |
| 제어 범위 | **기기 전체 화면** (OS 홈·설정·타 앱 포함) | 앱 내부 미러링 우회로가 봉쇄됨 |
| 배포 형태 | **별도 에이전트 앱/서비스 허용** | 기성품 경로가 선택지에 들어옴 |
| 플랫폼 | **Android(Sunmi) + Windows POS 동시** | QA 매트릭스 2배 |

---

## 결론

**자체 구현하지 말 것을 권고한다.** 90~148 person-day 를 들여 만들 결과물이, Sunmi 가 이미 시스템 레벨로 제공하는 것보다 나쁘다.

| 경로 | 초기 공수 | 연간 유지보수 | 월 비용 | 무인 동작 |
|---|---|---|---|---|
| **A. 자체 구현** | **90~148 PD** (1인 5~7개월) | 20~35 PD | $5~15 | Android 조건부 (기기별 ADB 필수) |
| **B. 기성품 조합** | **13~22 PD** (1인 3~4주) | 2~5 PD | $0~10 | Android 정식 지원 |

경로 B = **Sunmi MDM Remote Assistance(Android) + MeshCentral(Windows) + Fleet 대시보드는 디렉터리·감사 계층**.

공수 차이는 6~8배지만, 진짜 격차는 **품질과 유지보수**다. 자체 구현은 일반 사용자 앱의 권한 한계 안에서 Android 를 흉내내야 하고 OS 메이저 업그레이드마다 깨진다. Sunmi MDM 은 OS 벤더가 시스템 권한으로 제공한다 — 격차가 좁혀질 수 없는 종류다.

---

## 1. 기술적 실현 가능성 — 진짜 벽은 "무인 Android 화면 캡처"

### Android: 앱의 현재 특권 수준이 결정적

`android/app/build.gradle.kts` 와 매니페스트를 확인한 결과, 이 앱은 **평범한 사용자 앱**이다.

| 확인 항목 | 실제 | 의미 |
|---|---|---|
| `android:sharedUserId` / 플랫폼 서명 | 없음 (`SignKey` 자체 키스토어) | `CAPTURE_VIDEO_OUTPUT`·`INJECT_EVENTS` 사용 불가 |
| `DevicePolicyManager` / Device Owner | 코드 0건 | 정책 우회 경로 없음 |
| Sunmi SDK 사용 범위 | 프린터·스캐너·LCD **주변기기만** (`com.sunmi:printerlibrary`) | MDM/원격제어 SDK 미도입 |
| `targetSdk` | **35 (Android 15)** | MediaProjection 최신 제약 전부 적용 |
| `FOREGROUND_SERVICE_MEDIA_PROJECTION` | 미선언 | 캡처 쓰려면 추가 필요 |
| `MANAGE_EXTERNAL_STORAGE` | **이미 선언 + 런타임 요청 구현됨** (`MainActivity.java:600`) | 파일 탐색은 절반 이미 됨 |

Android 14 이상을 타깃하면 **캡처 세션마다 사용자 동의가 필수**이고, Android 15 QPR1 부터는 진행 중 화면공유 상태바 칩까지 강제된다. 즉 **정식 경로로는 무인 캡처가 성립하지 않는다.**

우회는 두 가지뿐이고 둘 다 대가가 있다:

1. **`adb shell appops set <pkg> PROJECT_MEDIA allow`** — 동의를 영구 허용으로 미리 굽는다. TeamViewer Host·TSplus 가 무인 모드 안내에 쓰는 업계 표준 수법이다. 대가: **기기 1대씩 ADB 로 물리 접촉해야 한다.** 이미 매장에 나가 있는 기기는 방문하거나 회수해야 한다.
2. **AccessibilityService 로 동의창 자동 클릭** — 접근성 서비스를 켜는 것 자체가 또 사용자 조작이고, OS 버전·OEM 스킨마다 다이얼로그 문자열/레이아웃이 달라 매년 깨진다.

> RustDesk 공식 문서조차 Android 는 "set-and-forget 무인 접속이 아니라 **동석 지원**으로 취급하라"고 명시한다. 자체 구현이 이 벽을 더 잘 넘을 이유가 없다.

### Windows: 사실상 벽이 없음

- `windows/runner/main.cpp:69` 에서 이미 `CoInitializeEx` 호출 — WGC/DXGI 캡처 API 가 COM 기반이라 유리
- 입력 주입은 `SendInput` 으로 권한 없이 가능
- 파일 접근은 `dart:io` 로 전부 가능
- 제약: `windows/CMakeLists.txt:44` 가 **`/W4 /WX`**(경고=에러) + `_HAS_EXCEPTIONS=0`, 그리고 CLAUDE.md 의 **네이티브 소스 ASCII 전용** 규율을 새 C++ 모듈이 전부 지켜야 함
- 실제 제약은 OS 가 아니라 **세션**: 잠금화면/로그오프 상태에서는 캡처가 죽는다 → 자동로그인 정책이 선행돼야 함

### 파일 탐색 — Android 는 "기기 전체"가 애초에 불가능

| | Windows | Android |
|---|---|---|
| 전체 파일시스템 | 가능 | **불가** |
| `/sdcard`, Documents, 앱 외부저장소 | — | 가능 (`MANAGE_EXTERNAL_STORAGE` 기선언) |
| 타 앱 `/data/data/*` | — | **영원히 불가** (root/시스템앱만) |

즉 Android 에서 "파일탐색기"는 어떤 구현을 쓰든 `/sdcard` 범위가 천장이다. 이건 공수 문제가 아니라 OS 설계다. 다행히 실무에서 필요한 로그·자산은 전부 이 범위 안에 있다.

---

## 2. 현재 Fleet 아키텍처와의 거리

현행 Fleet 은 **HTTP 폴링 piggyback** 이다 (`appfit_core/lib/src/fleet/fleet_reporter.dart`). 백엔드는 D1 단일 바인딩 — **R2·KV·Durable Objects·Queues·WebSocket 전부 미사용**(`appfit-fleet/wrangler.jsonc`).

| 자산 | 화면제어에 재사용 가능? |
|---|---|
| 기기 인벤토리·liveness·매장 그룹핑 (`devices` 테이블) | 그대로 |
| 명령 큐 (`commands`, 원자적 `UPDATE...RETURNING`) | **세션 개시 신호로** 그대로 |
| 기기 식별자 정본 (`DeviceIdentityService`) | 그대로 |
| 대시보드 UI | △ 329줄 HTML 문자열 — 인터랙티브 뷰어 얹으면 붕괴, 프론트 빌드 도입 필요 |
| **전송 계층** | ✗ **15~60초 폴링. 실시간 화면에 근본적으로 부적합** |
| AppFit WebSocket (`notifier_service.dart`) | ✗ **수신 전용**(`sink.add` 없음). 서버팀 의존 없이는 못 씀 |
| 파일 업로드 (`SlackDirectSink` 3-step) | △ 로그 zip 전용. 일반 파일엔 인메모리 zip → 스트리밍 전환 필요 |

**핵심**: 관제의 "카탈로그" 절반은 재사용되지만, **실시간 전송 계층은 통째로 신규**다. 이게 자체 구현 공수의 최대 덩어리다.

---

## 3. 자체 구현(경로 A) 공수 산정

> 전제: 시니어 1인, Flutter/Cloudflare 익숙, Win32 캡처·Android MediaProjection 은 신규 학습 포함. H.264 제외(JPEG 프레임 기준).

| 영역 | 항목 | PD |
|---|---|---|
| **전송/세션** | Durable Object 세션 허브 (viewer↔device WS 릴레이, 수명, 토큰) | 5~8 |
| | 세션 개시 명령 + 기기측 WS 연결/재연결/종료 | 3~4 |
| | 프로토콜 정의(프레임/입력/파일), 백프레셔·품질 적응 | 4~6 |
| **뷰어** | 프론트 빌드 파이프라인 도입 (현 대시보드는 HTML 문자열) | 2~3 |
| | 캔버스 렌더 + 입력 캡처/전송 + 세션 UI | 6~10 |
| **Windows** | DXGI/WGC 캡처 + GDI 폴백, 커서 합성 | 5~8 |
| | 더티렉트 diff + JPEG(WIC) 인코딩, 적응 품질/FPS | 4~6 |
| | `SendInput` 주입 (좌표 스케일, 다중 모니터, 한글 IME) | 4~6 |
| | 잠금/로그오프/UAC 세션, 자동로그인 정책 | 3~5 |
| **Android** | MediaProjection + VirtualDisplay + ImageReader + 포그라운드 서비스 | 5~7 |
| | **무인 동의 우회** (appops 프로비저닝 또는 접근성 자동수락) | 5~10 ⚠ |
| | 입력 주입 AccessibilityService (`dispatchGesture`, 키) | 5~8 |
| | 인코딩 `Bitmap.compress` (MediaCodec H.264 시 +8~12) | 3~5 |
| | 회전·해상도·**32비트(D2s_KDS)**·저사양 프레임 예산 | 4~6 |
| **파일** | 프로토콜 + 경로 allowlist / traversal 방어 | 3~4 |
| | Windows 구현 / Android 구현 | 2~3 / 2~4 |
| | R2 바인딩 추가 + 청크·재개 업로드 + 다운로드 UI | 4~6 |
| **보안** | 운영자 인증 개편 (공유 비밀번호 → per-operator) | 3~5 |
| | 세션 감사 로그 + 스키마 + 조회 UI | 3~5 |
| | 기기측 세션 표시 (온스크린 인디케이터·알림·로컬 로그) | 2~3 |
| | 세션 토큰 수명·스코프 분리 | 2~4 |
| **QA** | 실기기 매트릭스 (D3MINI / D2s_KDS / Win POS × OS 버전) | 8~12 |
| | 매장 네트워크(NAT·저대역) 튜닝 | 4~6 |
| | 문서·런북 | 3~4 |
| | **합계** | **90~148 PD** |

**1인 5~7개월 / 2인 3~4개월.** 법무·현장 공수는 이 표에 없다(§5·§6).

가장 위험한 줄은 `무인 동의 우회 5~10 PD` 다 — 여기가 실패하면 **나머지 85~138 PD 가 무인 시나리오에서 무의미해진다.**

---

## 4. 기성품 조합(경로 B) 공수

### 4-1. Android(Sunmi) → SUNMI MDM Remote Assistance

- D3 MINI 포함 현행 전 기종 지원, Partner Portal 기반 브라우저 원격제어
- **Unattended Mode 지원** — 활성화 후 인가된 MDM 계정의 접속을 기기가 자동 수락 (매장 조작 불필요)
- 시스템 레벨이라 MediaProjection 동의·접근성 서비스 문제가 **아예 발생하지 않음**
- 키오스크 모드와 공존하도록 설계됨

### 4-2. Windows POS → MeshCentral (Apache-2.0, 무료, 대수 무제한)

- 셀프호스팅 웹 기반. **원격 데스크톱 + 파일 관리자 + 터미널** — 요구 범위(화면제어 + 파일 다운로드)와 정확히 일치
- 에이전트가 NAT/방화벽 뒤에서 리버스 터널로 상시 접속 → 매장 네트워크 그대로 통과
- 기존 Lightsail(OTA 배포 서버)에 얹을 수 있음
- Windows 인스톨러(Inno Setup)에 에이전트를 동봉하면 배포 경로도 기존 것 재사용

### 4-3. Fleet 은 디렉터리 + 감사 계층으로 남긴다

투자한 관제 자산이 버려지지 않는다. 대시보드가 진입점이 되고 접속 이력이 D1 에 남는다.

| 항목 | PD |
|---|---|
| Sunmi Partner Portal 계정·기기 SN 등록·Unattended Mode 활성화 | 2~4 |
| MeshCentral 셀프호스팅 (Lightsail) + TLS/도메인 + 백업 | 2~3 |
| 에이전트 패키징·무인 설치 (Inno Setup 동봉) | 2~3 |
| **Fleet 연동 글루** — 스냅샷에 `sunmiSn`/`meshNodeId` 필드 추가 → 대시보드에서 딥링크 | 1~2 |
| 운영자 인증 개편 + 세션 감사 기록 | 3~5 |
| 실기기 파일럿 + 런북·문서 | 3~5 |
| **합계** | **13~22 PD** |

앱 코드 변경은 사실상 **`order_agent_fleet_snapshot.dart` 에 필드 2개 + `dashboard.ts` 에 링크 1개**다.

---

## 5. 현장·운영 공수 — 코드보다 크고, 대개 계산에서 빠진다

| 경로 | 기기당 필요한 물리 접촉 | 100대 환산 |
|---|---|---|
| A. 자체 구현(Android) | **ADB 연결 1회 필수** (`appops PROJECT_MEDIA`) — 이미 출고된 기기는 매장 방문 또는 회수 | 방문 100회 |
| B. Sunmi MDM | SN 일괄 등록이 포털에서 되면 **원격 완결**. Unattended 활성화가 기기 조작을 요구하면 1대당 5~15분 | 0 ~ 25시간 |
| B. MeshCentral(Win) | 다음 OTA 업데이트에 에이전트 동봉 → **원격 완결** | 0 |

> **이것이 경로 A 의 진짜 킬러다.** 개발 5~7개월을 감수하더라도, 그 끝에 "전 매장 방문"이라는 되돌릴 수 없는 물류 비용이 붙는다. 대수가 늘수록 선형으로 커진다.

---

## 6. 보안·법무·개인정보 — 별도 예산으로 잡아야 하는 축

**무인 원격제어 + 기기 전체 = POS 화면 전체를 언제든 볼 수 있다.** 주문 내역, 고객 연락처, 결제 승인 화면이 전부 포함된다.

| 항목 | 현재 상태 | 필요 조치 |
|---|---|---|
| 운영자 인증 | **단일 공유 비밀번호** (`appfit-fleet/src/auth.ts:124`) + `/api/login` **레이트리밋 없음** (`src/index.ts:459`) | per-operator 신원 + 브루트포스 방어. **원격제어를 붙이기 전 필수 선행** |
| 접속 감사 | 없음 | 누가·언제·어느 기기·몇 분·무슨 파일 — D1 테이블 + 조회 UI |
| 기기측 고지 | 없음 | 온스크린 인디케이터 + 로컬 로그 (법적·윤리적 요구) |
| 매장 동의 | 없음 | **위탁계약 조항 + 사전 고지.** 무단 원격제어는 정보통신망법 이슈 |
| 개인정보 | — | PIPA 접근기록 보관 의무, 처리방침 개정 |

**비개발 공수 5~15 PD.** 경로 A/B 공통이며, 경로 B 라 해서 면제되지 않는다.

> 현 대시보드는 workers.dev 퍼블릭 URL + 비밀번호 1개다. **이 인증 구조 위에 원격제어를 얹으면 비밀번호 1개가 전 매장 POS 장악 권한이 된다.** 어느 경로를 택하든 이 개선이 첫 번째 작업이어야 한다.

---

## 7. 인프라·라이선스 비용

| | 경로 A | 경로 B |
|---|---|---|
| Cloudflare | Workers Paid $5 + DO(세션 온디맨드라 미미) + R2 | 변동 없음 |
| 서버 | — | MeshCentral 자원 (기존 Lightsail 재사용 시 $0, 별도 시 $5~10) |
| 라이선스 | $0 | MeshCentral Apache-2.0 무료 / Sunmi MDM 은 Partner Portal 제공 — **계약 조건 확인 필요** |
| **월 합계** | **$5~15** | **$0~10** |

참고: TeamViewer/AnyDesk 상용 무인접속은 대수 과금이라 수백~수천 대 규모에서 연 수천만원대 → 검토 제외.

프레임 트래픽은 CF/Lightsail 모두 이그레스가 병목이 아니다. **실제 병목은 매장 인터넷 상향 대역폭**이다.

---

## 8. 유지보수 공수 (연간) — 격차가 가장 벌어지는 축

| | 경로 A | 경로 B |
|---|---|---|
| Android OS 메이저 업그레이드 | 캡처·주입·동의우회 회귀 대응 **10~20 PD/년** | 벤더 흡수 |
| Flutter/Windows 툴체인 업그레이드 | 네이티브 모듈 회귀 3~8 PD | 무관 |
| 보안 패치·의존성 | 5~10 PD | 서버 업데이트 2~5 PD |
| **연간 합계** | **20~35 PD** | **2~5 PD** |

Android 화면 캡처 정책은 **매 버전 조여지는 방향**이다 (14: 세션마다 동의 → 15 QPR1: 상태바 칩 강제). 자체 구현은 이 흐름을 영구히 따라가는 부채가 된다.

---

## 9. 리스크 등급

| 리스크 | 경로 A | 경로 B | 비고 |
|---|---|---|---|
| Android 무인 캡처 실현 실패 | **치명** | 낮음 | A 는 여기서 막히면 전체가 무의미 |
| 이미 배포된 기기 재접촉 물류 | **높음** | 낮음 | 대수 비례 선형 증가 |
| 저사양 기기 성능 (D2s_KDS 32bit) | **높음** | 중간 | "관제가 주문 흐름을 막으면 안 된다"는 기존 원칙과 정면충돌 |
| 보안 사고 시 피해 범위 | 높음 | 높음 | **공통** — 인증 개편이 선행 조건 |
| 법적 리스크 (무단 원격제어) | 높음 | 높음 | **공통** — 계약 조항 필수 |
| 벤더 종속 | 없음 | 중간 | Sunmi 이탈 시 Android 경로 재설계 |
| 유지보수 부채 | **높음** | 낮음 | §8 |

---

## 10. 권고 실행 순서

**Step 0 — 결정 게이트 (1일, 코드 0줄).** 아래 실험이 경로를 확정한다. 답이 나오기 전에는 아무것도 만들지 않는다.

**Step 1 — 보안 선행 (3~5 PD).** 대시보드 운영자 인증 개편 + `/api/login` 레이트리밋 + 감사 로그 스키마. 어느 경로든 공통이고, 원격제어보다 먼저다.

**Step 2 — 경로 B 파일럿 (10~15 PD).** Sunmi 1대 + Windows 1대. 실사용 후 판단.

**Step 3 — Fleet 글루 (1~2 PD).**
- `lib/services/fleet/order_agent_fleet_snapshot.dart` — 스냅샷에 `sunmiSn` / `meshNodeId` 추가
  (Sunmi SN 은 `DeviceIdentityService` 가 이미 조달 중 — 새 조회 불필요)
- `appfit-fleet/src/dashboard.ts` — 기기 행에 원격접속 딥링크 + 접속 기록 POST
- `appfit-fleet/schema.sql` — `remote_sessions` 테이블
- **`appfit_core` 는 건드리지 않는다.** 스냅샷 필드는 앱 전용 파일이라 태그 릴리즈 왕복이 불필요하다.

**Step 4 — 법무·계약 (병렬, 5~15 PD 비개발).** 위탁계약 원격지원 조항, 매장 사전 고지, 처리방침 개정.

### 함께 처리할 것

`fleet_reporter.dart` 의 `maxIntervalSeconds = 600` → `3600`. `appfit-fleet/SCALING.md` 의 액션 아이템인데 아직 미적용이다. **기기가 매장에 나간 뒤에는 전 기기 앱 업데이트가 필요해진다** — 원격제어 파일럿으로 기기를 만질 때 같이 넣는 게 맞다. (DEVICE_MONITORING.md §6-1)

---

## 11. 검증 (Step 0 결정 게이트)

세 실험 모두 반나절 이하다. **이 결과 없이 경로를 고르면 안 된다.**

**실험 1 — Sunmi 무인 원격제어 (반나절, 가장 중요)**
1. Sunmi Partner Portal 계정 확보 → D3 MINI 1대 SN 등록
2. Remote Assistance **Unattended Mode** 활성화
3. 기기를 매장 상태로 두고(아무도 안 만짐) 브라우저에서 접속 시도
4. 확인: 무인 접속 성립 / 응답성 / **D2s_KDS 도 동일하게 되는지** / 한국 계정 이용 조건·과금

성공하면 경로 B 확정. Android 자체 구현은 즉시 폐기.

**실험 2 — MeshCentral Windows (반나절)**
1. Lightsail 에 MeshCentral 설치 → Windows POS 1대에 에이전트 설치
2. 브라우저에서 화면제어 + 파일 관리자로 로그 폴더 다운로드
3. 확인: 매장 NAT 통과 / 잠금화면 상태 동작 / 대역폭 / 기존 앱과의 간섭

**실험 3 — 경로 A 생존 확인 (30분, 경로 A 를 진지하게 볼 경우만)**

```
adb shell appops set co.kr.waldlust.order.receive.appfit PROJECT_MEDIA allow
```

D3 MINI 실기의 실제 Android 버전에서 **동의창 없이** MediaProjection 이 시작되는지.

- 실패 → **경로 A 의 무인 시나리오는 성립 불가. 90~148 PD 안 전체가 폐기된다.**
- 성공 → 성립하되 기기별 ADB 물리 접촉이 영구 전제로 확정 (§5)

**공통 확인** — 실험 1·2 성공 후, 실제 장애 티켓 3건을 원격제어로 해결해 본다. "화면이 보이면 해결되는 문제"의 실제 비율이 이 투자의 정당성이다.

---

## 참고 자료

- [Media projection | Android Developers](https://developer.android.com/media/grow/media-projection)
- [Android 15 Features and APIs Overview](https://developer.android.com/about/versions/15/features)
- [Android – RustDesk Documentation](https://rustdesk.com/docs/en/client/android/)
- [Permanently enable PROJECT_MEDIA permission on Android | TSplus](https://docs.tsplus.net/remote-support-v3/android-permanently-enable-project-media-permission/)
- [MeshCentral (GitHub)](https://github.com/Ylianst/MeshCentral) / [MeshCentral Documentation](https://docs.meshcentral.com/)
- [Turning on Remote Assistance (Unattended Mode) on your Sunmi Terminal](https://help.myorderboxhq.com/en/article/turning-on-remote-assistance-unattended-mode-on-your-sunmi-terminal-e2aj66/)
- [SUNMI D3 MINI](https://www.sunmi.com/en/d3-mini/)
