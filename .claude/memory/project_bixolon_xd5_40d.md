---
name: project-bixolon-xd5-40d
description: "BIXOLON XD5-40d 라벨 프린터 Android 지원 — SDK 함정(connect 인자 무시·pdflib NoClassDefFoundError catch·생성자 loadLibrary), VID 라우팅, submit-wins 규칙, APK +15MB, 실기기 검증 대기 항목"
metadata:
  type: project
---

BIXOLON XD5-40d 라벨 프린터 Android 지원 구현 (2026-07-23, 계획 plans/glistening-sauteeing-chipmunk.md).

**구조**: 기존 PNG(490×600) 파이프라인 완전 재사용. MethodChannel `printLabel` 계약 불변 — NativeMethodHandler 가 매 인쇄마다 UsbManager 로 VID 0x1504 존재를 재평가해 `BixolonLabelDriver`(신규) vs Caysn `LabelPrinter` 분기. 동시 연결 시 BIXOLON 우선. Dart 변경은 print_service.dart 라벨 whitelist `vendorId == 0x1504` (VID-only) 한 곳.

**SDK 함정 (V2.1.1 jar bytecode 검증 + 실기기)**:
- `connect(UsbDevice)` 는 **인자를 무시**하고 내부에서 VID 0x1504 + printer class 7/1/2 를 자체 enumerate. 성공 판정은 반환 String 아닌 `isConnected()` 로.
- 생성자가 `System.loadLibrary("bxl_common")` 직접 호출 → **libbxl_common.so 필수** (UnsatisfiedLinkError 는 catch 안 됨). 반면 pdflib(License/PdfCore) 참조는 `catch (NoClassDefFoundError)` 로 감싸져 있어 **Bixolon_pdf.aar 는 불필요** — 생성 시마다 logcat 에 찍히는 `NoClassDefFoundError: com.bixolon.pdflib.License` 스택트레이스는 SDK catch 블록의 printStackTrace() **무해한 소음** (핵심 초기화 PrinterControl/SLCSEmul/BXLQueue 는 그 전에 완료, pdf 필드만 null).
- `getStatus(boolean): byte[]` / `endTransactionPrint(): int` 는 동기 API — Handler 이벤트 불필요 (Handler 는 상태 로깅 전용). read 는 500ms 단위 최대 3초.
- **상태 응답은 1바이트일 수 있음** (실기기 XD5-40d 확인, 샘플도 `report.length == 2` 가드) — length<2 를 실패 처리하면 정상 응답을 "상태조회 불가" 로 오판 (첫 실기기 테스트 사고). 드라이버는 getStatus(true) 1회 프로브로 variant 학습(extended=2바이트 byte1 게이트 활성 / basic=byte1 0 패딩, busy 게이트 no-op) 후 연결당 고정, 빈 응답만 실패. SDK 는 미연결 시 null 아닌 **빈 배열** 반환.
- **`endTransactionPrint()` 는 RC 코드를 반환하지 않음** (bytecode): 성공=**3**(write OK+응답 수신), 실패=-1 뿐. `!= RC_SUCCESS` 검사는 성공을 실패로 오판(2차 실기기 사고 — 출력됐는데 "테스트 출력 실패"+Dart 재시도=중복 위험). -1 은 write 실패/응답 없음 미구분 → 상태조회 2차 판별: 응답하면 submit-wins true, 상태조회도 불가면 연결사망=false 재시도.
- **drawBitmap 의 level 이진화는 저임계 동작** (실기기 level=50: 순흑 로고/큰 글자만 선명, AA 얇은 글자·1px 구분선·black26 구분자(≈189) 소실) → SDK 이진화 포기, Java `binarizeForPrint` 사전 이진화(luminance<**210**→흑; black26≈189 포함+흰배경 여유). level 인자는 무의미해짐. Caysn 은 같은 PNG 를 자체 thresholding 으로 잘 찍으므로 임계가 높은 쪽.
- SDK 는 USB 권한을 요청하지 않음 → 드라이버가 requestPermission + hasPermission 200ms 폴링 (device_filter attach 승계가 1차).
- RC 코드는 음수/양수 혼재 (RC_FAIL=-1, RC_FAIL_WRITE_PORT=50, RC_FAIL_READ_PORT=100…) → 판정은 `!= RC_SUCCESS(0)`.

**중복 인쇄 방지 (Caysn 745번 2장 사고 계승)**: `endTransactionPrint` 성공(또는 RC_FAIL_READ_PORT=write 완료·read 만 실패) 이후는 submit-wins — 상태조회 실패/USB detach/인쇄중 용지소진 모두 true 반환. 인쇄 중 용지소진→복구 후 **펌웨어 자동 재인쇄를 전제**로 함 (미검증 가정 — 실기기에서 아니면 waitPrintCompleteLocked 의 recoverable 분기만 false 로 조정).

**onUsbDetached 는 논블로킹**: printBitmap 이 복구대기로 클래스 lock 을 오래 쥘 수 있어, 메인 스레드 리시버는 volatile `sDetachRequested` 만 세우고 close 는 백그라운드 스레드 위임. 모든 대기 루프가 이 플래그+interrupt 를 탈출 조건으로 검사.

**패키징**: jar 2개(`android/app/libs/`) + `src/main/jniLibs/<abi>/libbxl_common.so` 4 ABI(release 는 abiFilters 로 arm 2종). proguard `-keep com.bixolon.**` + `-dontwarn com.bixolon.**` (dontwarn 이 부재 pdflib 참조도 커버 — 없으면 R8 실패). **APK +15MB (release 18.75→34.5MB)** — .so 가 크고 필수라 불가피, OTA 대역폭 참고.

**실기기 확인 완료 (2026-07-23, 테스트 출력 성공)**: PID **0x0106(262)** — whitelist 는 타 BIXOLON 라벨 기종 호환 위해 VID-only 유지(주석에 기록). VID 라우팅·USB 연결·미디어 설정·물리 출력·품질(이진화 210)·UI 성공 표시 모두 정상. 3회 왕복 수정: ①1바이트 상태 오판→정규화, ②endTransactionPrint=3 오판→END_TRANSACTION_OK, ③level 저임계 품질 불량→사전 이진화 210.
- **이 기기는 확장 2바이트 상태 지원** (byte1 게이트 활성) + **PAUSED_IN_PEELER(0x20) = 배출 라벨 회수 대기** — 8장 주문 실증: 라벨마다 떼기대기 진입, 사용자가 떼는 즉시 다음 인쇄(빨리 떼면 print≈1.9s, 늦게 떼면 6~8s — 시간이 사용자 행동과 정확히 상관). 표준기에도 paper-taken 센서가 활성이며 Caysn PAPERNOFETCH 와 동일 운영 모델(떼야 다음 장). 8/8 전량·중복 0·연결 재사용(첫 장만 connect ≈1s 포함) 확인 (2026-07-23).
- **pdflib 스택트레이스 소음은 스텁으로 제거**: `android/app/src/main/java/com/bixolon/pdflib/`{License,PdfCore,PdfDocument,util/Size} — SDK 참조 멤버 bytecode 전수 조사 기반 최소 스텁. PDF 인쇄 도입 시 스텁 삭제 후 진짜 Bixolon_pdf.aar 로 교체.

- **커버열림 복구 = 프린터 재개버튼 필요** (실기기 검증): 커버 열림 중 수신된 잡은 커버를 닫아도 자동 인쇄되지 않고, **본체 재개(resume) 버튼을 눌러야** 인쇄된다(잡 유실 아님 — 버튼 후 정상 출력). 드라이버는 status 해제를 보고 출력끝 처리하므로 로그와 실물 시점이 어긋날 수 있으나 운영상 정상. 매장 안내 사항: 커버 연 뒤엔 닫고 재개버튼까지.

**실기기 검증 대기 (P3 잔여)**: 인쇄중 용지소진 자동재인쇄 가정, RXLA-561 회귀(Caysn 라우팅), 동시연결 라우팅. 완료: 다중 라벨 8장 직렬화·떼기대기·품질·pdflib 스텁 소음 제거·커버열림 복구(재개버튼). Windows(P5) 미착수 — BIXOLON Windows SDK V310 FFI + 백엔드 인터페이스 분리는 후속.

관련: [[project-store-printer-topology]], [[project-label-ack-patch]]
