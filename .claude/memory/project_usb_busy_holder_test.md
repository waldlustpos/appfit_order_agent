---
name: project-usb-busy-holder-test
description: Android 외부 영수증 프린터 BUSY backoff 재현용 helper APK 신규 작성 + 검증 진행 중. helper HOLDING 까지 도달했으나 본 앱이 startup 시 잡은 fd 를 들고 있어 helper claim 이 무력화되는 상태에서 멈춤. 다음 세션에서 force-stop/케이블 분리/외부 프린터 토글로 재시도 필요.
metadata: 
  node_type: memory
  type: project
  originSessionId: 54e9475d-c125-4b10-846b-4b2e8b55cb52
---

# Android USB 외부 프린터 점유 충돌 테스트 helper APK (진행 중)

Windows 의 PowerShell COM 점유 테스트와 같은 효과를 Android USB CDC 외부 영수증 프린터(D3MINI/PR800 등 NXP LPC 칩 공유 모델, VID 0x0D28 PID 0x4C59)에서 재현하려는 작업. 본 앱 `appfit_order_agent` 코드는 **건드리지 않고** 별도 helper APK 작성.

**Why**: 본 앱의 `ExternalReceiptPrinter` / `PrinterJobQueue` backoff (7회 / 누적 137s) 가 운영 단말에서 실제로 도는지 검증. 점유 충돌 backoff 정책은 이미 코드에 들어가 있지만 실제 BUSY 시나리오는 운영 사례로만 확인됐고 시뮬레이션 테스트가 없었음.

**How to apply**: 다음 세션에서 이어갈 때 plan 파일 `/Users/kimsungchun/.claude/plans/indexed-bouncing-sparrow.md` 와 같이 참조. helper APK 코드는 이미 완성 + 빌드 검증 완료, 남은 건 운영 단말에서의 시나리오 검증.

## 완료된 작업

- helper APK 신규 작성 + 빌드 성공 — 위치 `/Users/kimsungchun/Documents/GitHub/usb_busy_holder/`
  - `app/build/outputs/apk/debug/app-debug.apk` (3.2 MB)
  - 패키지 `co.kr.waldlust.usbbusyholder`, AGP 8.7.3 / Kotlin 2.1.0 / Gradle 8.10 (본 앱 stack 동일)
  - 구성: `MainActivity.kt` (UI), `HoldForegroundService.kt` (dataSync FG svc 로 hold 유지), `UsbSelector.kt` (본 앱 `UsbReceiptPrinter.selectInterfaceAndEndpoint` Tier 0~3 미러)
  - intf/ep NumberPicker 자동 prefill (NXP composite → CDC-DATA intf=2) + 수동 override
  - README 에 빌드/설치/시나리오 A~D 정리
- 본 앱 logcat 으로 helper 가 같은 디바이스 (vid=0xd28 pid=0x4c59) 의 같은 intf=2 ep=0 을 잡는 것 확인. logcat: `HoldFG: doClaim: HOLDING /dev/bus/usb/003/002 intf=2 ep=0`

## 검증에서 막힌 지점 (2026-05-19)

helper 가 HOLDING 상태인데도 본 앱에서 영수증 재출력이 **그냥 정상 출력됨** — BUSY backoff 가 안 돔.

원인 가설:
- 본 앱이 startup 시 `discover()` → `openLocked` 로 connection 을 잡아 멤버 변수에 보관. 그 후 `writeBytes` 호출 시 `attemptOpenIfNeededLocked` 를 건너뛰고 기존 fd 로 바로 `bulkTransfer` → helper 의 claim 과 무관하게 데이터 송출.
- Android `UsbDeviceConnection.claimInterface(intf, true)` 의 force quirk 가 모호. helper HOLDING 로그는 helper 입장의 view 일 뿐, 본 앱 fd 가 살아 있는 한 실효 점유 X.

결정적 진단 로그 (다음 세션에서 확인할 것):
- 본 앱 logcat 에 `openLocked: claimInterface failed` 또는 `attemptOpenIfNeededLocked: claimInterface failed` 가 보여야 helper 가 진짜 단독 점유에 성공한 것.
- 안 보이면 helper claim 은 본 앱에게 무효.

## 다음 세션에서 시도할 절차 (우선순위 순)

테스트 대상은 **외부 프린터** (D3MINI 내장 아님). VID/PID 가 0x0D28/0x4C59 인 건 외부 프린터도 같은 NXP LPC 칩을 쓰기 때문. 외부라서 USB 케이블 분리 가능.

1. **본 앱 외부 프린터 enable 토글이 있다면 그게 가장 깔끔**:
   - 본 앱 설정에서 외부 프린터 OFF → helper CLAIM → 본 앱 토글 ON → 본 앱 claim false → BUSY 경로 진입.

2. **USB 케이블 분리 + 본 앱 force-stop 절차**:
   ```bash
   adb logcat -c
   # USB 케이블 분리 → 본 앱 logcat 에 "onUsbDetached: closing" 확인
   adb shell am force-stop co.kr.waldlust.order.receive
   adb shell pidof co.kr.waldlust.order.receive   # 빈 출력 확인
   # USB 케이블 재연결
   # helper APK 실행 → CLAIM → HOLDING
   # 본 앱 시작 → "openLocked: claimInterface failed" 확인  ← 결정적
   # 영수증 재출력 → "[PrinterQueue] attempt 1/7 ... BUSY" 시퀀스 확인
   ```

3. **NXP USB stack 의 동시 claim enforcement 가 약한 펌웨어 특성**일 가능성도 배제 못함. 위 절차 다 해도 BUSY 가 안 뜨면, helper APK 접근 자체가 이 모델군에서는 한계. 대안은 운영 사례 reproduce 가능한 환경 찾기 (다른 ESC/POS 외부 프린터로 같은 테스트).

## 변경 파일

본 앱 (`appfit_order_agent`): **0개** — 어떤 파일도 수정 안 함.

helper repo (`/Users/kimsungchun/Documents/GitHub/usb_busy_holder/`, 미 git init):
- `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `local.properties`, `.gitignore`
- `gradle/wrapper/gradle-wrapper.properties` + `gradle-wrapper.jar` (본 앱에서 복사)
- `gradlew`, `gradlew.bat` (본 앱에서 복사)
- `app/build.gradle.kts`
- `app/src/main/AndroidManifest.xml`
- `app/src/main/java/co/kr/waldlust/usbbusyholder/{MainActivity.kt, HoldForegroundService.kt, UsbSelector.kt}`
- `app/src/main/res/layout/activity_main.xml`
- `app/src/main/res/values/strings.xml`
- `README.md`

git init / 첫 commit 은 아직 안 함 — 사용자가 별도로 지시할 때 진행.

## 참조 문서

- plan: `/Users/kimsungchun/.claude/plans/indexed-bouncing-sparrow.md`
- 본 앱 진단 가이드: `.claude/agents/external-receipt-printer-inspector.md`
- 본 앱 ground truth: `android/app/src/main/java/co/kr/waldlust/order/receive/util/print/UsbReceiptPrinter.java` (Tier 0~3 선택, BUSY 판정), `lib/services/printer_job_queue.dart` (backoff `[0,2,5,10,20,40,60]s`)

연관: [[project-label-ack-patch]] 와는 다른 영역 — 라벨이 아닌 외부 영수증 프린터.
