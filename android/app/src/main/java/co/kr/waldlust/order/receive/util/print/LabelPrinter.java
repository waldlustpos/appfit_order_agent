package co.kr.waldlust.order.receive.util.print;

import android.content.Context;
import android.graphics.Bitmap;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.util.Log;

import com.caysn.autoreplyprint.AutoReplyPrint;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.ptr.LongByReference;

import java.util.concurrent.atomic.AtomicInteger;

import co.kr.waldlust.order.receive.MainActivity;

public class LabelPrinter {
    private static final String TAG = "LabelPrinter";
    private static Pointer hPrinter = Pointer.NULL;
    private static int currentAutoReplyMode = 0;
    // 라벨 재출력 버튼 연타 등 동시 호출 시 카운터 경쟁을 방지하기 위해 Atomic 사용
    private static final AtomicInteger printCount = new AtomicInteger(0);
    private static MainActivity sActivity = null;

    // ── printBitmap 반환 코드 ────────────────────────────────────────────────
    // bool 하나로는 "아직 안 보냈다"와 "보냈는데 응답이 없다"를 구분할 수 없어,
    // 후자에서 Dart 재시도가 같은 페이지를 재발사해 라벨이 2장 인쇄되는 사고가
    // 발생했다 (2026-08-03 아오야마점 #0906/#0956). 재시도 가능 여부를 호출자가
    // 알 수 있도록 3분류로 반환한다.

    /** 인쇄 완료가 확인됨. */
    public static final int RESULT_SUCCESS = 0;
    /** PagePrint 발사 전에 실패 — 종이가 나가지 않았으므로 재시도해도 안전. */
    public static final int RESULT_RETRYABLE = 1;
    /**
     * PagePrint 를 이미 발사한 뒤 완료 응답을 못 받음.
     * 페이지는 펌웨어에 들어간 상태라 <b>재시도하면 중복 인쇄</b>가 된다.
     * 호출자는 재시도 없이 성공으로 취급하고 별도 집계만 할 것.
     */
    public static final int RESULT_SUBMITTED_NO_ACK = 2;

    /** 완료 대기 총 상한. samplelabel 표준값. 줄이면 미인쇄 페이지를 넘겨 펌웨어 버퍼에 쌓인다. */
    private static final int QUERY_PRINT_RESULT_TIMEOUT_MS = 30_000;

    /**
     * 완료 대기를 쪼개는 슬라이스 크기. 정상 인쇄(~1.1초)는 첫 슬라이스 안에서 끝나 기존과
     * 동일하게 동작하고, 보류는 이 간격마다 peel edge 를 확인해 최대 이만큼만 늦게 감지된다.
     */
    private static final int QUERY_RESULT_SLICE_MS = 2_000;


    /** ERROR_OCCURED 상태에서 클리어 까지 짧게 대기 — 피크타임 큐 막힘 방지. */
    private static final long ERROR_QUICK_GATE_MS = 500L;

    /** RECVIDLE/PRINTIDLE 동기화 timeout — 직전 라벨 처리 완료 대기. */
    private static final long IDLE_WAIT_MS = 5_000L;

    /**
     * 복구대기 중 운영자 조치가 확인된 뒤 active clear 까지의 최소 대기.
     *
     * <p>비트가 자연스럽게 내려갈 시간을 조금 준다 — 정상 단말에서는 이 시간 안에
     * 해제되므로 clear 를 호출할 일이 없다. Windows 경로와 같은 값.
     */
    private static final long RECOVERY_CLEAR_MIN_MS = 200L;

    /**
     * active clear 후에도 비트가 안 내려갈 때 강제로 진행하기까지의 대기.
     *
     * <p>펌웨어가 host 호출로도 비트를 안 풀어주는 케이스의 최종 안전망. 이 지점은
     * PagePrint 발사 전이라 강제 진행에 중복 인쇄 위험이 없다. Windows 경로와 같은 값.
     */
    private static final long RECOVERY_CLEAR_GIVEUP_MS = 1_500L;


    /**
     * 자발적 STATUS 비콘 콜백.
     */
    private static AutoReplyPrint.CP_OnPrinterStatusEvent_Callback statusCallback = null;
    private static boolean statusCallbackRegistered = false;

    // ── statusCallback 이 갱신하는 마지막 비콘 캐시 (volatile, 게이팅 용도) ──────────
    /** 마지막 비콘이 한 번이라도 도착했는지 (0=미수신 → 게이트 fallback 통과). */
    private static volatile long lastStatusTime = 0L;
    private static volatile boolean lastErrorOccurred = false;
    private static volatile long lastErrorStatusBits = 0L;
    private static volatile long lastErrorTime = 0L;
    /** 운영자 개입(용지 교체 / 커버 닫음) 으로 회복 가능한 에러 분기용. */
    private static volatile boolean lastErrorIsNoPaper = false;
    private static volatile boolean lastErrorIsCoverUp = false;
    private static volatile boolean lastInfoRecvIdle = false;
    private static volatile boolean lastInfoPrintIdle = false;
    private static volatile boolean lastInfoNoPaperCanceled = false;
    private static volatile boolean lastInfoPaperNoFetch = false;

    /**
     * PAPERNOFETCH 의 false→true 상승 edge 누적 횟수.
     *
     * <p>"내 라벨이 물리적으로 나왔는가" 를 {@code CP_Pos_QueryPrintResult} 와 독립적으로
     * 확인하는 신호다. 인쇄 시작 ~0.83초 뒤 라벨이 peel 에 도달하며 edge 가 발생한다
     * (2026-08-03 실측). 레벨이 아니라 edge 를 세는 이유는 필드 주석 참조.
     */
    private static volatile int paperNoFetchRiseCount = 0;

    /** 동일 phase 연속 출력을 막기 위한 dedup 캐시 (null = 아직 미로깅). */
    private static volatile String lastLoggedPhase = null;

    /**
     * PAPERNOFETCH 전이 로깅용 dedup 캐시 (null = 아직 미로깅).
     *
     * <p>이 비트는 QueryPrintResult 가 실패했을 때만 로그에 남아 왔다. 즉 "이 단말에서
     * 비트가 동작하긴 하는가" 를 확인할 방법이 없었고, 2026-08-03 라벨 2장 사고 분석에서
     * 이 공백이 오판(비트가 아예 안 온다고 단정)의 원인이 됐다. 전이 시점만 기록한다.
     */
    private static volatile Boolean lastLoggedPaperNoFetch = null;

    /**
     * 마지막 ACK timeout 의 진단 스냅샷. Dart 가 Sentry 이벤트에 실어 보낸다.
     *
     * <p>{@link #diagnosticSnapshot} 은 판정에 필요한 값을 전부 만들어 두고도 기기 로그
     * 파일로만 나가서, Sentry 에 쌓인 이벤트로는 "왜 timeout 했는가" 를 되물을 수 없었다.
     * 특히 비콘 age 가 핵심이다 — timeout 순간 비콘이 살아 있었으면 유실된 것은 print-result
     * 응답 하나뿐이고, 비콘도 함께 끊겼으면 IN 엔드포인트 전체가 멎은 것이라 원인이 다르다.
     *
     * <p>{@code printBitmap} 진입 시 null 로 초기화한다. 직전 라벨의 스냅샷이 다음 라벨
     * 이벤트에 잘못 붙는 것을 막기 위함.
     */
    private static volatile String lastAckDiagnostic = null;

    /**
     * 현재 활성 라벨의 표시 prefix (예: "[0812]" 또는 "[0812 1/7]").
     * ERROR phase 비콘에 컨텍스트 prefix 로 사용 — 어느 라벨에서 에러가 났는지 식별용.
     * printBitmap 시작 시 갱신되고, 다음 printBitmap 이 시작되거나 close() 까지 유지된다.
     */
    private static volatile String currentOrderTag = null;

    /**
     * 마지막으로 남긴 {@code [CONNECT]} 실패 진단. 같은 내용이 반복되면 억제한다.
     *
     * <p>프린터가 뽑혀 있으면 인쇄마다 재연결을 시도하므로, dedup 없이는 실패 줄이
     * 주문 수만큼 쌓인다. 성공은 항상 남기고(드물고 의미가 크다) 실패는 진단 내용이
     * 바뀌었을 때만 남긴다 — {@link #lastLoggedPhase} 와 같은 방식.
     */
    private static volatile String lastLoggedConnectDiag = null;

    /**
     * USB 권한 다이얼로그를 이미 띄웠는지. 프로세스당 1회로 제한한다.
     *
     * <p>warm-up 백오프 재시도가 매 회차마다 다이얼로그를 다시 띄우면 매장에서
     * 팝업이 반복 노출된다. 승인 여부와 무관하게 "요청은 한 번" 이 규칙이다.
     */
    private static volatile boolean permissionRequested = false;

    public static void init(MainActivity activity) {
        sActivity = activity;
        ensureStatusCallbackRegistered();
    }

    // ── 포트 후보 ────────────────────────────────────────────────────────────
    // 라벨 전용 고정 모델만. 범용 USB-Serial 칩(PL2303 0x067B:0x2303 등) 은 넣지
    // 말 것 — 외부 ESC/POS 영수증 프린터를 라벨로 오인 점유한다.
    // 아래 세 배열은 index 로 동기된다.

    /** {@code CP_Port_OpenUsb} 에 넘기는 포트 문자열. */
    private static final String[] PORT_CANDIDATES = {
            "VID:0x4B43,PID:0x3538", // Caysn D2
            "VID:0x4B43,PID:0x3830", // Caysn D3
            "VID:0x0FE6,PID:0x811E"  // REXOD RXLA-561 (운영 모델)
    };

    /** 로그 가독성 전용 축약명. */
    private static final String[] PORT_LABELS = {"D2", "D3", "REXOD"};

    /** {@code UsbManager} 조회용 {VID, PID}. */
    private static final int[][] PORT_IDS = {
            {0x4B43, 0x3538}, {0x4B43, 0x3830}, {0x0FE6, 0x811E}
    };

    /**
     * 라벨 한 장을 인쇄한다. samplelabel 의 표준 흐름과 동일하게
     * {@link AutoReplyPrint#CP_Pos_QueryPrintResult} 를 동기 블로킹으로 호출하여
     * 인쇄 완료 (또는 30초 timeout) 까지 다음 호출의 진입을 자연스럽게 차단한다.
     *
     * <p>피크타임 race 차단: PageBegin 직전에 비콘 캐시 기반 idle 게이트(최대 5초)
     * 로 직전 라벨의 수신/인쇄가 완료될 때까지 대기. ERROR 상태면 0.5초 짧은 게이트
     * 후 false 반환 → Dart 측 재시도가 처리.
     *
     * <p>장시간 방치 누락 0: QueryPrintResult timeout 후 PAPERNOFETCH 가 set 이면
     * 비콘 polling 으로 사용자 떼기까지 무한 대기. PagePrint 추가 발사 안 하므로
     * 펌웨어 큐에 한 번만 보관됨 → 사용자 떼는 순간 펌웨어가 자동 인쇄 → ACK.
     *
     * <p>비프음 흐름: 사용자가 라벨을 안 떼면 펌웨어가 다음 PagePrint 명령 진입 시
     * buzzer 를 울려 알린다. PAPERNOFETCH 비트는 게이트 조건에서 의도적 제외.
     *
     * @return {@link #RESULT_SUCCESS} / {@link #RESULT_RETRYABLE} /
     *         {@link #RESULT_SUBMITTED_NO_ACK} — 호출자는 RETRYABLE 일 때만 재시도할 것.
     */
    public static synchronized int printBitmap(Bitmap bitmap,
                                       int autoReplyMode,
                                       boolean useFeedToTear,
                                       boolean useBackToPrint,
                                       boolean useCalibrate,
                                       String orderNo,
                                       int labelIndex,
                                       int totalLabels) {
        int result = RESULT_RETRYABLE;
        // PagePrint 발사 여부. 예외/timeout 시 재시도 가능 여부를 가르는 기준.
        boolean submitted = false;
        final int seq = printCount.incrementAndGet();
        long startTime = System.currentTimeMillis();

        // 운영자 시점의 식별자: 주문번호 + (다중 라벨일 때) 인덱스. 모든 라이프사이클 로그에 prefix.
        // 예: "[0795]" 또는 "[0795 1/7]"
        final String orderTag = "[" + orderNo
                + (totalLabels > 1 ? " " + labelIndex + "/" + totalLabels : "") + "]";
        // 활성 라벨 컨텍스트 등록 — ERROR phase 비콘에 prefix 로 사용.
        currentOrderTag = orderTag;
        // 직전 라벨의 진단 스냅샷이 이번 라벨 이벤트에 붙지 않도록 초기화.
        lastAckDiagnostic = null;
        log("#" + seq + " " + orderTag + " 출력시작");

        try {
            // autoReplyMode 가 변경됐거나 포트가 죽었으면 재연결.
            // QueryPrintResult timeout 으로 USB 가 손상된 케이스도 이 분기가 자동 회복한다.
            //
            // ★ 여기에 재시도·대기를 추가하지 말 것. 상위 runLabelPrintWithRetry 가 이미
            //   1.5초 후 1회 재시도를 갖고 있고, 하위에 대기를 더하면 인쇄 큐가 막힌다.
            //   시작 시점의 선제 연결은 warmup() 이 담당한다.
            if (!ensureConnected(autoReplyMode, "인쇄")) {
                long elapsed = System.currentTimeMillis() - startTime;
                log("#" + seq + " " + orderTag + " 실패 [연결오류] (" + elapsed + "ms)");
                return RESULT_RETRYABLE;
            }

            // 1-B-① ERROR 게이트 분기:
            //   • paper-out / cover-up / NoPaperCanceled 인 경우 → 운영자 개입 신뢰, 무한 대기 후 인쇄 재개
            //     (PAPERNOFETCH 무한 대기 패턴과 동일. 큐의 후속 항목은 자동 일시정지)
            //   • 그 외 ERROR (engine/voltage/cutter 등) → 0.5초 짧은 게이트 후 false 반환 (Dart 재시도 위임)
            if (lastErrorOccurred || lastInfoNoPaperCanceled) {
                boolean recoverable = lastErrorIsNoPaper || lastErrorIsCoverUp
                        || lastInfoNoPaperCanceled;
                if (recoverable) {
                    long waitStart = System.currentTimeMillis();
                    long lastNotice = waitStart;
                    // 진입 phase 라벨 — 운영자가 어떤 조치를 해야 하는지 즉시 식별 가능하도록.
                    // 펌웨어 특성상 paper/cover 비트가 동시에 뜨는 케이스도 커버.
                    final String entryPhase;
                    if (lastErrorIsNoPaper && lastErrorIsCoverUp) entryPhase = "용지없음+커버열림";
                    else if (lastErrorIsNoPaper)               entryPhase = "용지없음";
                    else if (lastErrorIsCoverUp)               entryPhase = "커버열림";
                    else if (lastInfoNoPaperCanceled)          entryPhase = "용지없음취소";
                    else                                       entryPhase = "복구대기";
                    // lastErrorStatusBits 는 에러 발생 시에만 갱신되므로 마지막 에러의
                    // 잔상일 수 있다. 판정에 실제로 쓰이는 현재 비트를 함께 남긴다.
                    log("#" + seq + " " + orderTag + " 복구대기 진입 [" + entryPhase
                            + "] lastError=0x" + String.format("%04X", lastErrorStatusBits)
                            + " " + recoveryBits());
                    boolean interrupted = false;
                    // 운영자 조치(커버 개폐 / 용지 교체) 감지용 진입 스냅샷.
                    final boolean entryCover = lastErrorIsCoverUp;
                    final boolean entryNoPaper = lastErrorIsNoPaper;
                    // 취소 비트만으로 진입한 경우(용지·커버는 멀쩡). 이때는 감시할
                    // error 비트가 없어 sawUserAction 이 영영 참이 되지 않으므로, 조치
                    // 관측을 기다리지 않고 곧바로 해제를 시도해야 한다. 그러지 않으면
                    // 이 진입 경로만 여전히 무한 대기로 남는다.
                    final boolean canceledOnlyEntry =
                            !entryCover && !entryNoPaper && lastInfoNoPaperCanceled;
                    boolean sawUserAction = false;
                    boolean clearTried = false;
                    boolean forcedBreak = false;
                    long clearTime = 0L;
                    while (lastErrorIsNoPaper || lastErrorIsCoverUp
                            || lastInfoNoPaperCanceled) {
                        try {
                            Thread.sleep(200);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                            interrupted = true;
                            break;
                        }
                        long now = System.currentTimeMillis();
                        long elapsed = now - waitStart;

                        // 진입 시점과 비트가 달라졌다 = 운영자가 뭔가 조치했다.
                        if (lastErrorIsCoverUp != entryCover
                                || lastErrorIsNoPaper != entryNoPaper) {
                            sawUserAction = true;
                        }

                        // 조치가 끝나 ERROR 는 해제됐는데 NoPaperCanceled(info 0x10) 만
                        // 남은 stuck. 이 비트는 error status 가 아니라서 용지를 갈아도
                        // 내려가지 않는 단말이 있고(REXOD RXLA-561), 그것을 내릴 유일한
                        // 계기인 다음 인쇄 명령은 이 루프 뒤에 있다 — 대기가 자신을 깨울
                        // 사건을 스스로 막는 구조였다. host 측에서 능동 해제한다.
                        //
                        // ★ canceled 를 조건에 넣는 이유: 세 비트가 모두 내려간 정상 복구
                        // 에서도 while 조건 재평가는 다음 iteration 이라, 이 검사가 한 발
                        // 먼저 실행된다. canceled 를 안 보면 잔류 비트가 없는데도 clear 를
                        // 부르게 되고(2026-08-10 실기기 재현 로그에서 실제로 관측),
                        // ClearPrinterBuffer 가 멀쩡한 보류 페이지를 날릴 수 있다.
                        if (!clearTried && (sawUserAction || canceledOnlyEntry)
                                && !lastErrorIsCoverUp && !lastErrorIsNoPaper
                                && lastInfoNoPaperCanceled
                                && elapsed >= RECOVERY_CLEAR_MIN_MS) {
                            log("#" + seq + " " + orderTag + " stuck 감지 (조치 완료·비트 잔류) "
                                    + recoveryBits() + " — active clear");
                            clearPrinterErrorState("복구대기-stuck");
                            clearTried = true;
                            clearTime = now;
                        }

                        // active clear 로도 비트가 안 내려가는 펌웨어 대비 안전망.
                        // 운영자가 이미 용지를 갈아 시각적으로 정상이고, 이 지점은 PagePrint
                        // 발사 전(submitted=false)이라 강제 진행에 중복 인쇄 위험이 없다.
                        if (clearTried && now - clearTime >= RECOVERY_CLEAR_GIVEUP_MS) {
                            forcedBreak = true;
                            break;
                        }

                        if (now - lastNotice >= 60_000L) {
                            // 비트를 함께 찍는다 — 이 로그가 비트를 빼먹은 탓에 2026-08-10
                            // 실매장 8분 정지의 원인을 현장 로그로 판별할 수 없었다.
                            log("#" + seq + " " + orderTag + " 복구대기중 elapsed="
                                    + (elapsed / 1000) + "s " + recoveryBits()
                                    + " action=" + sawUserAction);
                            lastNotice = now;
                        }
                    }
                    if (interrupted) {
                        long elapsed = System.currentTimeMillis() - startTime;
                        log("#" + seq + " " + orderTag + " 실패 [복구대기 인터럽트] ("
                                + elapsed + "ms)");
                        return RESULT_RETRYABLE;
                    }
                    long waited = System.currentTimeMillis() - waitStart;
                    if (forcedBreak) {
                        log("#" + seq + " " + orderTag + " 복구 강제진행 [" + entryPhase
                                + "] wait=" + waited + "ms " + recoveryBits()
                                + " — active clear 후에도 비트 잔류, 인쇄 시도");
                    } else {
                        log("#" + seq + " " + orderTag + " 복구감지 [" + entryPhase
                                + " → OK] wait=" + waited + "ms — 인쇄재개");
                    }
                } else {
                    long erStart = System.currentTimeMillis();
                    while (lastErrorOccurred
                            && (System.currentTimeMillis() - erStart) < ERROR_QUICK_GATE_MS) {
                        try { Thread.sleep(50); } catch (InterruptedException e) {
                            Thread.currentThread().interrupt(); break;
                        }
                    }
                    if (lastErrorOccurred) {
                        long elapsed = System.currentTimeMillis() - startTime;
                        log("#" + seq + " " + orderTag + " 실패 [프린터 에러 0x"
                                + String.format("%04X", lastErrorStatusBits)
                                + " — 재시도 위임] (" + elapsed + "ms)");
                        return RESULT_RETRYABLE;
                    }
                }
            }

            // 1-B-② 피크타임 race 게이팅 — 펌웨어 idle 동기화 (최대 5초)
            // 비콘 미수신 환경(lastStatusTime=0) 에서는 fallback 으로 즉시 통과.
            if (lastStatusTime != 0L) {
                long waitStart = System.currentTimeMillis();
                while (!(lastInfoRecvIdle && lastInfoPrintIdle && !lastInfoNoPaperCanceled)
                        && (System.currentTimeMillis() - waitStart) < IDLE_WAIT_MS) {
                    try { Thread.sleep(20); } catch (InterruptedException e) {
                        Thread.currentThread().interrupt(); break;
                    }
                }
                // idle 게이트 wait 로그 제거 — 정상 흐름은 100% 무로그.
                // 1초 이상 대기는 비정상 race 신호이지만 운영자 단순화 우선.
            }

            int bitmapWidth = bitmap.getWidth();
            int bitmapHeight = bitmap.getHeight();

            if (useCalibrate) {
                AutoReplyPrint.INSTANCE.CP_Label_CalibrateLabel(hPrinter);
            }

            AutoReplyPrint.INSTANCE.CP_Pos_ResetPrinter(hPrinter);

            if (useBackToPrint) {
                AutoReplyPrint.INSTANCE.CP_Label_BackPaperToPrintPosition(hPrinter);
            }

            AutoReplyPrint.INSTANCE.CP_Label_PageBegin(
                    hPrinter, 0, 0, bitmapWidth, bitmapHeight,
                    AutoReplyPrint.CP_Label_Rotation_0);
            AutoReplyPrint.CP_Label_DrawImageFromData_Helper.DrawImageFromBitmap(
                    hPrinter, 0, 0, bitmapWidth, bitmapHeight, bitmap,
                    AutoReplyPrint.CP_ImageBinarizationMethod_Thresholding,
                    AutoReplyPrint.CP_Label_Rotation_0);

            // PagePrint 직전의 인쇄 매수 스냅샷. 완료 판정에는 쓰지 않고(아래 주석 참조)
            // 진단 로그에만 남긴다 — 사후에 "정말 인쇄됐는가" 를 따지는 근거가 된다
            // (조회 미지원이면 -1).
            final int pageIdBefore = queryPrintedPageId();
            // peel edge 기준선. 이 값이 늘면 "내 라벨이 peel 에 도달했다".
            final int riseBefore = paperNoFetchRiseCount;

            AutoReplyPrint.INSTANCE.CP_Label_PagePrint(hPrinter, 1);
            // 이 지점부터 페이지는 펌웨어 소유 — 재전송은 곧 중복 인쇄다.
            submitted = true;

            if (useFeedToTear) {
                AutoReplyPrint.INSTANCE.CP_Label_FeedPaperToTearPosition(hPrinter);
            }

            // ── 다중 신호 완료 판정 ────────────────────────────────────────────────
            //
            // 기존에는 CP_Pos_QueryPrintResult 30초 블로킹 하나에만 완료 판정을 걸었다.
            // 그래서 **응답만 유실되면** 라벨이 이미 나왔고 프린터가 놀고 있는데도 30초를
            // 태운 뒤 "모르겠다"(SUBMITTED_NO_ACK) 로 끝났다. 新橋店 2026-08-07 로그의
            // #40 이 그 경우다 — recvIdle/printIdle 둘 다 true(프린터 idle)에 비콘도
            // 살아 있는데 응답만 오지 않았다.
            //
            // ⚠️ 반대로 **펌웨어 보류는 이 변경으로 빨라지지 않는다.** 앞 라벨을 안 떼면
            // 펌웨어가 실제로 인쇄를 안 하고 있는 것이므로 그 30초는 낭비가 아니라
            // 기다려야 하는 시간이다. 그리고 라벨을 늦게 떼는 것은 러시아워의 **정상
            // 운영**이지 고쳐야 할 대상이 아니다. 이 루프가 고치는 것은 보류가 아니라
            // "이미 나왔는데 응답이 없는" 경우다.
            //
            // 그래서 대기를 슬라이스로 쪼개고, 아래 둘 중 **먼저 오는 것**으로 완료를
            // 판정한다. 총 상한(30초)은 그대로 둔다 — 상한을 줄이면 아직 인쇄되지 않은
            // 페이지를 넘겨 펌웨어 버퍼에 쌓이기 때문이고, 바꾸는 것은 상한이 아니라
            // **판정 근거의 개수**다.
            //
            //   query : QueryPrintResult true (기존 경로)
            //   peel  : PAPERNOFETCH 상승 edge = 라벨이 물리적으로 peel 에 도달
            //
            // 인쇄 매수(pageId)는 신호로 쓰지 않는다. 실측상 같은 호출 안에서는 절대
            // 갱신되지 않고(新橋店 로그 199건 중 0건) 다음 인쇄 시점에야 반영돼,
            // 판정에 쓰면 앞 페이지의 뒤늦은 등록을 내 페이지로 오인할 수 있다.
            // 그 오인은 아직 인쇄되지 않은 페이지를 넘겨 펌웨어 버퍼에 쌓는다.
            // peel edge 가 정상·보류·응답유실 세 경우를 모두 덮으므로 보강도 불필요하다.
            // (진단 스냅샷에는 계속 남긴다 — 사후에 인쇄 여부를 따지는 근거로 유용하다.)
            //
            // 실측 2026-08-07 (D2s_KDS_STGL + REXOD):
            //   정상   #1 출력끝 (1250ms, via=query, ack=849ms)   — 슬라이싱해도 응답 유실 없음
            //   보류   #4 출력끝 (12645ms, via=peel, ack=12515ms) — 떼는 순간 edge 로 481ms 만에 완료
            //   미떼기 #2 30.2초 후 떼기대기 전환 (buzzer 활성)     — 폴백·비프음 정상
            //
            // 중복 인쇄 위험은 구조적으로 없다 — 여기는 submitted=true 이후라 결과가
            // SUCCESS / SUBMITTED_NO_ACK 뿐이고 재발사 경로 자체가 존재하지 않는다.
            boolean printed = false;
            String via = null;
            final long waitStartMs = System.currentTimeMillis();
            while (System.currentTimeMillis() - waitStartMs < QUERY_PRINT_RESULT_TIMEOUT_MS) {
                if (AutoReplyPrint.INSTANCE.CP_Pos_QueryPrintResult(
                        hPrinter, QUERY_RESULT_SLICE_MS)) {
                    printed = true;
                    via = "프린터응답";
                    break;
                }
                // 용지없음 취소는 종이가 안 나간 유일한 케이스 — 즉시 빠져나가 재시도로 넘긴다.
                if (lastInfoNoPaperCanceled) {
                    break;
                }
                if (paperNoFetchRiseCount != riseBefore) {
                    printed = true;
                    via = "라벨나옴";
                    break;
                }
            }
            final long ackWaitMs = System.currentTimeMillis() - waitStartMs;

            // 1-D 후처리: PageBegin/PagePrint 진행 중 NoPaper 가 발생한 race 케이스.
            // 진입 게이트(1-B-①)가 paper/cover 를 무한 대기로 차단하므로 보통 도달하지
            // 않지만, idle 게이트 통과 직후 PagePrint 도중 용지가 떨어지는 race 안전망.
            // false 반환 → Dart 재시도(1.5초) → 다음 진입 시 게이트 무한 대기로 복구.
            if (!printed && lastInfoNoPaperCanceled) {
                // NoPaperCanceled = 용지가 없어 펌웨어가 인쇄를 취소함 = 종이가 안 나감.
                // PagePrint 를 발사했더라도 중복 위험이 없는 유일한 케이스라 재시도 허용.
                log("#" + seq + " " + orderTag + " 실패 [용지없음 race — Dart 재시도 위임]");
                return RESULT_RETRYABLE;
            }

            // 1-D-① 장시간 방치 누락 방지 — PAPERNOFETCH 풀릴 때까지 무한 대기
            // PagePrint 추가 발사 안 함 (펌웨어 큐에 이미 보관됨, 떼면 자동 인쇄)
            //
            // ★ 중복 인쇄 방지: 떼기 감지 후 두 번째 QueryPrintResult 를 호출하지 않는다.
            // 이전 코드에서 두 번째 호출이 race-prone 으로 false 를 반환하면 Dart 측
            // _printLabelWithRetry 가 1.5초 후 새 PagePrint 를 발사 → 같은 라벨이 2장
            // 인쇄되는 사고 발생 (예: 1/7 두 장, 745번 두 장). 떼기 감지 = 펌웨어 인쇄
            // 완료로 간주하고 USB 포트만 확인 후 즉시 success 반환.
            if (!printed && lastInfoPaperNoFetch) {
                log("#" + seq + " " + orderTag + " 떼기대기 (앞 라벨을 안 뗌 — 비프음 울림)");
                long fetchStart = System.currentTimeMillis();
                long lastNotice = fetchStart;
                boolean interrupted = false;
                // ★ NoPaperCanceled(0x10) 를 함께 감시한다. 떼기대기 중 용지가 떨어지면
                // 펌웨어가 보류 페이지를 취소하면서 PAPERNOFETCH(0x20) 를 내리는데, 0x20 만
                // 보면 그 하강을 "운영자가 뗐다" 로 오독한다. 그 오독의 대가가 두 가지다:
                //   ① 나오지도 않은 라벨을 성공으로 처리해 조용히 누락시킨다.
                //   ② 0x10 을 리셋 없이 다음 라벨에 물려줘, 그 라벨이 복구대기에서 영원히
                //      빠져나오지 못한다 (2026-08-10 실매장 8분 정지 → 앱 강제 종료).
                // 완료 대기 루프에는 이 가드가 이미 있었고 여기에만 빠져 있었다.
                while (lastInfoPaperNoFetch && !lastInfoNoPaperCanceled) {
                    try {
                        Thread.sleep(100);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        interrupted = true;
                        break;
                    }
                    long now = System.currentTimeMillis();
                    if (now - lastNotice >= 60_000L) {
                        log("#" + seq + " " + orderTag + " 떼기대기중 elapsed="
                                + ((now - fetchStart) / 1000) + "s");
                        lastNotice = now;
                    }
                }
                if (interrupted) {
                    lastAckDiagnostic = "reason=떼기대기 인터럽트 elapsed="
                            + (System.currentTimeMillis() - startTime) + "ms";
                    log("#" + seq + " " + orderTag + " 실패 [떼기대기 인터럽트]");
                    return RESULT_SUBMITTED_NO_ACK;
                }
                long fetchWait = System.currentTimeMillis() - fetchStart;
                // 떼어진 게 아니라 용지 소진으로 취소된 경우. 종이가 나가지 않았으므로
                // 재시도가 안전하며, 이는 완료 대기 루프의 같은 신호 판정과 동일한 결론이다
                // ("용지없어 취소 = 중복 위험이 없는 유일한 케이스").
                // 0x10 을 여기서 내려 다음 라벨이 이 상태를 물려받지 않게 한다.
                if (lastInfoNoPaperCanceled) {
                    log("#" + seq + " " + orderTag + " 떼기대기 중 용지소진 [보류페이지 취소] "
                            + "wait=" + fetchWait + "ms — 재시도 위임");
                    clearPrinterErrorState("떼기대기-용지소진");
                    return RESULT_RETRYABLE;
                }
                boolean portOk = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
                long elapsed2 = System.currentTimeMillis() - startTime;
                log("#" + seq + " " + orderTag + " 떼어짐 wait=" + fetchWait
                        + "ms (" + (portOk ? "출력끝" : "실패")
                        + ", 총 " + elapsed2 + "ms)");
                if (!portOk) {
                    lastAckDiagnostic = "reason=떼기 후 포트 사망 fetchWait=" + fetchWait
                            + "ms elapsed=" + elapsed2 + "ms";
                }
                // 포트가 죽었어도 페이지는 이미 발사된 뒤라 재시도 금지.
                return portOk ? RESULT_SUCCESS : RESULT_SUBMITTED_NO_ACK;
            }

            // ★ 중복 인쇄 방지 (PAPERNOFETCH 가드와 동일 정신):
            // CP_Pos_QueryPrintResult 가 인쇄 완료까지 동기 블로킹하므로
            // printed=true 면 종이가 실제 인쇄된 상태. 일부 라벨 프린터 펌웨어는
            // 인쇄 직후 USB 를 detach 하는데, 그 결과 CP_Port_IsOpened 가 false 가 되어
            // result=false 가 되고 Dart _printLabelWithRetry 가 1.5초 후 같은 라벨을
            // 한 장 더 인쇄하는 사고가 발생한다 (USB_DEVICE_DETACHED 직후 케이스).
            // 출력 자체가 끝났다면 후속 USB 이벤트로 실패 처리하지 않는다.
            //
            // ★ 2026-08-03 아오야마점 라벨 2장 사고: QueryPrintResult 가 30초를 꽉 채워
            // false 를 반환했지만 라벨은 정상 출력된 상태였다 (하루 258장 중 2장, 0.8%).
            // 이를 인쇄 실패로 단정해 Dart 가 같은 페이지를 재발사 → 2장 인쇄.
            long elapsed = System.currentTimeMillis() - startTime;

            if (printed) {
                result = RESULT_SUCCESS;
                // 어느 신호로 완료를 판정했는지 남긴다 — 신호별 기여도를 셀 수 있어야
                // "동작하는 줄 알았는데 무력한" 신호를 코드에 남겨 두지 않는다.
                // pg 는 붙이지 않는다: 같은 호출 안에서는 절대 안 변한다(로그 199건 중 0건).
                log("#" + seq + " " + orderTag + " 출력끝 (" + elapsed + "ms, "
                        + via + " " + ackWaitMs + "ms)");
            } else {
                result = RESULT_SUBMITTED_NO_ACK;
                // 인쇄 매수 재조회는 **여기서만** 한다. 성공 경로에서도 부르면 매 인쇄마다
                // 공유 USB IN 엔드포인트에 명령을 하나씩 더 얹게 되는데, 그 간섭이야말로
                // 응답 유실의 유력한 후보다 (feedToTear 순서 가설과 같은 성질).
                // 값 자체는 판정에 쓰지 않고 진단용으로만 남긴다 — 같은 호출 안에서는
                // 갱신되지 않고 다음 인쇄 시점에야 반영되기 때문(로그 199건 중 0건).
                // 다만 30초짜리 긴 대기에서는 증가하며, 그것이 #40 의 pg=7→8 근거였다.
                final int pageIdAfter = queryPrintedPageId();
                // 요약과 원자료를 한 번만 만들어 로그·Sentry 양쪽에 같은 값을 쓴다
                // (두 번 만들면 시점이 어긋나고, 문구도 갈린다).
                final String summary = plainState();
                final String snapshot = diagnosticSnapshot(pageIdBefore, pageIdAfter);
                lastAckDiagnostic = "총 " + elapsed + "ms " + summary + " | " + snapshot;
                // 앞쪽은 운영자가 읽는 요약, `|` 뒤는 개발자용 원자료.
                log("#" + seq + " " + orderTag + " 실패 [완료신호 없음 "
                        + (QUERY_PRINT_RESULT_TIMEOUT_MS / 1000) + "초 — 재시도 금지] ("
                        + elapsed + "ms) " + summary + " | " + snapshot);
            }

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            // PagePrint 를 이미 발사한 뒤의 예외는 재시도하면 중복 인쇄가 된다.
            result = submitted ? RESULT_SUBMITTED_NO_ACK : RESULT_RETRYABLE;
            if (submitted) {
                lastAckDiagnostic = "reason=발사후 예외 [" + e.getMessage()
                        + "] elapsed=" + elapsed + "ms";
            }
            log("#" + seq + " " + orderTag + " 실패 [예외: " + e.getMessage() + "] ("
                    + elapsed + "ms"
                    + (submitted ? ", PagePrint 발사후 — 재시도 금지" : "") + ")");
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
        }

        return result;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 연결 관리
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * 앱 시작 시점의 warm-up. <b>포트만 열고 인쇄는 하지 않는다.</b>
     *
     * <p>{@link #printBitmap} 이 세션 첫 호출에서 lazy 로 하던 USB open 을 시작 창으로
     * 앞당긴다. 그 lazy open 이 실패하면 첫 주문의 라벨이 {@code 실패 [연결오류]} 로
     * 끝나고 1.5초 뒤 재시도에서야 인쇄됐다 — open 비용과 실패 확률을 첫 주문이
     * 대신 지불하는 구조였다. Windows 는 {@code WindowsLabelRouter.warmupOpen} 으로
     * 이미 같은 일을 하고 있고(main.dart), 이 메서드가 그 Android 대응물이다.
     *
     * <p>{@link #hPrinter} 와 {@link #currentAutoReplyMode} 가 프로세스 전역 static 이고
     * open 경로가 {@link #ensureConnected} 로 동일하므로, 첫 인쇄는 재연결 없이 이
     * 핸들을 그대로 재사용한다.
     *
     * <p>지켜야 할 제약 3가지:
     * <ul>
     *   <li>{@code printCount} 를 건드리지 않는다 — 첫 인쇄가 계속 {@code #1} 이어야
     *       기존 운영 로그의 시퀀스 해석이 바뀌지 않는다.</li>
     *   <li>{@code autoReplyMode} 는 실제 인쇄가 넘길 값과 <b>반드시 같아야 한다.</b>
     *       다르면 {@link #ensureConnected} 의 모드 비교가 첫 인쇄에서 재연결을
     *       유발해 warm-up 이 통째로 무효가 된다. 그래서 이 값은 Dart 의
     *       {@code getLabelAutoReplyMode()} 에서만 온다.</li>
     *   <li>USB 권한 선요청은 <b>여기서만</b> 한다. 인쇄 경로에 사람 손을 기다리는
     *       대기를 넣으면 인쇄 큐 전체가 다이얼로그에 묶인다.</li>
     * </ul>
     *
     * @return 포트가 열렸으면 true. 실패해도 기존 lazy 연결이 폴백으로 살아 있다.
     */
    public static synchronized boolean warmup(int autoReplyMode) {
        try {
            // init() 이 먼저 도는 것이 정상이지만, 등록 여부와 무관하게 no-op 이라 방어적으로 호출.
            ensureStatusCallbackRegistered();
            requestUsbPermissionOnce();
            return ensureConnected(autoReplyMode, "warmup");
        } catch (Throwable t) {
            log("[CONNECT] warmup 예외: " + t.getMessage());
            return false;
        }
    }

    /**
     * 포트가 열려 있고 모드가 일치하면 아무것도 하지 않고 true. 아니면 재연결한다.
     *
     * <p><b>진단 로그는 재연결이 실제로 일어난 경우에만 남는다</b> — 조건문이 아니라
     * 함수 구조로 보장한다(early-return 뒤에만 로깅). 이 메서드는 라벨 한 장마다
     * 호출되지만 정상 흐름은 첫 분기에서 끝나므로 운영 로그가 두꺼워지지 않는다.
     *
     * <p>남기는 값의 목적: 콜드스타트 1회 실패의 원인이 (A) USB 권한 미보유 인지
     * (B) 권한과 무관한 커널/디바이스 준비 지연 인지를 <b>로그 한 줄로</b> 가르기 위함.
     * 그래서 장치 enumerate 여부 · 권한 보유 · 포트별 소요 ms 를 함께 찍는다.
     *
     * @param caller {@code "인쇄"} 또는 {@code "warmup"} — 어느 경로가 포트를 열었는지 구분.
     */
    private static boolean ensureConnected(int autoReplyMode, String caller) {
        final boolean modeChanged = (autoReplyMode != currentAutoReplyMode);
        if (!modeChanged && AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter)) {
            return true; // ← 정상 흐름은 여기서 끝. 아래 로깅에 도달하지 않는다.
        }

        final long t0 = System.currentTimeMillis();
        // ★ 판정 순서 주의: 세션 첫 연결은 hPrinter 가 NULL 이면서 동시에
        //   currentAutoReplyMode(초기값 0) != autoReplyMode(보통 1) 라 modeChanged 도
        //   참이다. 모드변경을 먼저 보면 최초 연결이 "모드변경 0→1" 로 찍혀
        //   "왜 시작하자마자 모드가 바뀌지?" 라는 오독을 부른다. 핸들 유무가 우선.
        final String reason = (hPrinter == Pointer.NULL)
                ? "최초연결"
                : modeChanged
                        ? ("모드변경 " + currentAutoReplyMode + "→" + autoReplyMode)
                        : "포트무효";

        if (hPrinter != Pointer.NULL) {
            AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
            hPrinter = Pointer.NULL;
        }

        // 커널이 장치를 이미 enumerate 했는가 + 앱이 권한을 갖고 있는가.
        // 이 한 값이 위 (A)/(B) 를 가르는 판정 기준이다. OpenUsb 시도 **전에** 읽어야
        // 한다 — SDK 내부가 권한 상태를 바꿀 여지를 남기지 않기 위함.
        final String usbDiag = describeUsbState();

        final StringBuilder tried = new StringBuilder();
        boolean opened = false;
        for (int i = 0; i < PORT_CANDIDATES.length; i++) {
            final long tp = System.currentTimeMillis();
            hPrinter = AutoReplyPrint.INSTANCE.CP_Port_OpenUsb(
                    PORT_CANDIDATES[i], autoReplyMode);
            final boolean ok = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
            if (tried.length() > 0) {
                tried.append(' ');
            }
            tried.append(PORT_LABELS[i]).append(ok ? ":o/" : ":x/")
                    .append(System.currentTimeMillis() - tp).append("ms");
            if (ok) {
                currentAutoReplyMode = autoReplyMode;
                opened = true;
                break;
            }
        }

        final String diag = "[CONNECT] " + caller + " " + (opened ? "성공" : "실패")
                + " 사유=" + reason + " " + usbDiag
                + " 시도=[" + tried + "] (" + (System.currentTimeMillis() - t0) + "ms)";
        if (opened || !diag.equals(lastLoggedConnectDiag)) {
            log(diag);
        }
        lastLoggedConnectDiag = opened ? null : diag;
        return opened;
    }

    /**
     * 복구 판정에 실제로 쓰이는 세 비트의 현재값. 로그 전용.
     *
     * <p>앞의 둘은 error status(0x04/0x80), {@code canceled} 는 <b>info status(0x10)</b> 다.
     * 이 비대칭이 사고의 핵심이었다 — {@code ERROR 해제} 로그는 error status 만 보므로
     * "해제됐다고 찍혔는데 대기는 계속되는" 상태가 성립한다.
     */
    private static String recoveryBits() {
        return "noPaper=" + lastErrorIsNoPaper
                + " cover=" + lastErrorIsCoverUp
                + " canceled=" + lastInfoNoPaperCanceled;
    }

    /**
     * 펌웨어의 에러/취소 상태를 host 측에서 능동 해제한다.
     *
     * <p><b>왜 필요한가</b>: INFO_NOPAPERCANCELED(0x10) 는 error status 가 아니라 info
     * status 라, 운영자가 용지를 갈아 ERROR 가 해제돼도 함께 내려가지 않는 단말이 있다
     * (REXOD RXLA-561, 2026-08-10 실매장). 그 비트 하나 때문에 복구대기 루프가 8분간
     * 빠져나오지 못했고 앱 강제 종료가 유일한 탈출구였다. Windows 경로는 같은 현상을
     * 이미 겪고 active clear 로 처리하고 있다(windows_label_printer_backend.dart).
     *
     * <p>★ {@code ClearPrinterBuffer} 는 펌웨어 큐에 보류 중인 페이지도 함께 날린다.
     * 그럼에도 쓰는 이유는 이 함수가 불리는 시점이 이미 "큐가 멈춘" 상황이라 잃을 페이지가
     * 없거나, 있어도 그것이 곧 정지의 원인이기 때문이다.
     * <b>정상 흐름에서는 절대 호출하지 말 것.</b>
     */
    private static void clearPrinterErrorState(String reason) {
        if (hPrinter == Pointer.NULL) {
            return;
        }
        boolean err = false;
        boolean buf = false;
        boolean rst = false;
        try {
            err = AutoReplyPrint.INSTANCE.CP_Printer_ClearPrinterError(hPrinter);
        } catch (Throwable t) {
            Log.w(TAG, "ClearPrinterError 예외", t);
        }
        try {
            buf = AutoReplyPrint.INSTANCE.CP_Printer_ClearPrinterBuffer(hPrinter);
        } catch (Throwable t) {
            Log.w(TAG, "ClearPrinterBuffer 예외", t);
        }
        try {
            rst = AutoReplyPrint.INSTANCE.CP_Pos_ResetPrinter(hPrinter);
        } catch (Throwable t) {
            Log.w(TAG, "ResetPrinter 예외", t);
        }
        log("[CLEAR] " + reason + " — ClearError=" + err + " ClearBuffer=" + buf
                + " Reset=" + rst);
    }

    /**
     * 라벨 프린터 USB 장치의 커널 enumerate 여부와 앱의 권한 보유 여부.
     *
     * <p>{@link #PORT_IDS} 화이트리스트에 있는 장치만 본다 — 영수증 프린터 등 무관한
     * 장치를 로그에 노출하면 현장에서 오독을 부른다.
     */
    private static String describeUsbState() {
        if (sActivity == null) {
            return "장치=미초기화";
        }
        try {
            UsbManager um = (UsbManager) sActivity.getSystemService(Context.USB_SERVICE);
            if (um == null) {
                return "장치=USB서비스없음";
            }
            for (UsbDevice d : um.getDeviceList().values()) {
                for (int[] id : PORT_IDS) {
                    if (d.getVendorId() == id[0] && d.getProductId() == id[1]) {
                        return String.format("장치=VID:0x%04X,PID:0x%04X 권한=%s",
                                d.getVendorId(), d.getProductId(),
                                um.hasPermission(d) ? "있음" : "없음");
                    }
                }
            }
            return "장치=없음(enumerate안됨)";
        } catch (Throwable t) {
            return "장치=조회실패(" + t.getMessage() + ")";
        }
    }

    /**
     * 권한이 없으면 다이얼로그를 <b>한 번만</b> 띄운다 (승인 대기는 하지 않는다).
     *
     * <p>대기하지 않는 이유: 승인까지의 시간은 Dart 측 warm-up 백오프가 이미 덮는다.
     * 여기서 블로킹하면 그 백오프의 probe 가 멈춰 두 겹의 대기가 중첩된다.
     *
     * <p>Caysn SDK(nzio) 도 내부에서 requestPermission 을 부르지만 <b>결과를 기다리지
     * 않고 즉시 openDevice 로 진행</b>한다 — 그래서 권한이 없는 세션의 첫 open 은
     * 반드시 실패하고, 승인이 붙은 다음 시도에서야 열린다(2026-08-10 D2s_KDS 실측:
     * {@code 권한=없음} 실패 → 3.3초 뒤 {@code 권한=있음} 성공). 게다가 그 요청은
     * PendingIntent 를 flags=0 으로 만들어 <b>Android 12+ 단말에서는</b> 예외가 난 뒤
     * 삼켜진다 — 그 단말에서는 요청 자체가 없는 것과 같다. 여기서 같은 요청을 미리
     * 해 두면 두 경우 모두 승인 사이클이 첫 주문보다 앞서 시작된다.
     */
    private static void requestUsbPermissionOnce() {
        if (permissionRequested || sActivity == null) {
            return;
        }
        UsbManager um = (UsbManager) sActivity.getSystemService(Context.USB_SERVICE);
        if (um == null) {
            return;
        }
        for (UsbDevice d : um.getDeviceList().values()) {
            for (int[] id : PORT_IDS) {
                if (d.getVendorId() == id[0] && d.getProductId() == id[1]) {
                    if (!um.hasPermission(d)) {
                        log("[CONNECT] USB 권한 요청 " + String.format(
                                "VID:0x%04X PID:0x%04X", d.getVendorId(), d.getProductId()));
                        UsbPermissionHelper.request(sActivity, um, d);
                    }
                    permissionRequested = true;
                    return;
                }
            }
        }
    }

    /**
     * 마지막 ACK timeout 의 진단 스냅샷을 읽고 비운다 (consume).
     *
     * <p>Dart 는 {@code submittedNoAck} 를 받은 직후에만 호출한다. 한 번 읽으면 비우므로
     * 같은 스냅샷이 다음 이벤트에 중복으로 붙지 않는다.
     *
     * @return 스냅샷 문자열, 없으면 null
     */
    public static String consumeLastAckDiagnostic() {
        String snapshot = lastAckDiagnostic;
        lastAckDiagnostic = null;
        return snapshot;
    }

    /**
     * 마지막으로 인쇄 완료된 page id 를 동기 조회한다. 비콘 콜백과 독립적인 경로라
     * ACK timeout 시 "실제로 인쇄됐는가" 를 추측 없이 판정할 수 있다.
     *
     * <p>이 단말에서 {@code CP_Printer_AddOnPrinterPrintedEvent} 콜백은 fire 0건
     * 이력이 있으므로(2026-05-04 D2s_KDS_STGL 부하 테스트), 같은 데이터원을 쓰는
     * 이 API 도 동작하지 않을 수 있다. 그 경우 -1 또는 항상 같은 값이 나오며,
     * 호출부는 판정을 포기하고 재시도 금지로 폴백한다.
     *
     * @return page id, 조회 실패 시 -1
     */
    private static int queryPrintedPageId() {
        if (hPrinter == Pointer.NULL) {
            return -1;
        }
        try {
            IntByReference pageId = new IntByReference();
            LongByReference printedTime = new LongByReference();
            boolean ok = AutoReplyPrint.INSTANCE.CP_Printer_GetPrinterPrintedInfo(
                    hPrinter, pageId, printedTime);
            return ok ? pageId.getValue() : -1;
        } catch (Throwable t) {
            return -1;
        }
    }

    /**
     * 실패 로그 앞부분에 붙는 **운영자용** 한 줄 요약.
     *
     * <p>진단 스냅샷은 원인 규명에 필수지만 비트 이름과 16진수라 현장에서 읽을 수 없다.
     * 같은 상태를 사람 말로 먼저 적고, 원자료는 `|` 뒤로 미룬다.
     *
     * <p>세 값이 답하는 질문:
     * <ul>
     *   <li>프린터 — 지금 일하고 있나, 손 놓고 있나 (일하는 중이면 아직 차례가 안 온 것)</li>
     *   <li>라벨 — 이번 인쇄분이 실제로 배출됐나 (상승 edge 발생 여부)</li>
     *   <li>연결 — USB 가 살아 있나</li>
     * </ul>
     */
    private static String plainState() {
        final String printer = (lastInfoRecvIdle && lastInfoPrintIdle)
                ? "대기중(할일없음)" : "작업중";
        final String label = lastInfoPaperNoFetch ? "안뗀채로있음" : "없음";
        final String port = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)
                ? "정상" : "끊김";
        return "프린터=" + printer + " 라벨=" + label + " 연결=" + port;
    }

    /**
     * ACK timeout 실패 로그에 붙일 진단 스냅샷.
     *
     * <p>기존 로그는 {@code 실패 (30182ms)} 뿐이라 timeout 인지 다른 사유인지,
     * 그 시점 프린터가 어떤 상태였는지 사후 판별이 불가능했다. 비콘 캐시와
     * 동기 조회값을 나란히 남겨 둘이 어긋나는지도 함께 본다.
     */
    private static String diagnosticSnapshot(int pageIdBefore, int pageIdAfter) {
        StringBuilder sb = new StringBuilder();
        // pg: 인쇄 매수. 같은 호출 안에서는 안 변하는 것이 정상이고, 변했다면 긴 대기 동안
        //     실제로 인쇄가 일어났다는 뜻이다 (#40 의 7→8 이 그 근거였다).
        sb.append("pg=").append(pageIdBefore).append("→").append(pageIdAfter);
        // 이번 인쇄분이 배출됐는지 = 상승 edge 발생 여부. 판정의 핵심 근거라 맨 앞에 둔다.
        // 배출 edge 카운터는 적지 않는다. 이 스냅샷은 실패 분기에서만 쓰이는데, 그 분기는
        // "edge 가 안 올랐다" 를 조건으로 도달하므로 값이 늘 같다. 숫자만 남으면 무언가를
        // 말해 주는 것처럼 보여 오히려 오해를 부른다.
        //
        // paperNoFetch / recvIdle / printIdle / portOk 도 plainState() 가 사람 말로 이미
        // 전달하므로 여기 다시 적지 않는다. 이 괄호 안은 **plainState 가 못 담는 것만** 남긴다.
        sb.append(" 비콘[");
        sb.append("noPaperCanceled=").append(lastInfoNoPaperCanceled);
        sb.append(String.format(" err=0x%04X", lastErrorStatusBits));
        sb.append(" age=");
        sb.append(lastStatusTime == 0L
                ? "미수신"
                : (System.currentTimeMillis() - lastStatusTime) + "ms");
        sb.append(']');

        // 동기 상태조회 — 비콘 캐시가 stale 인지 교차 확인.
        try {
            LongByReference err = new LongByReference();
            LongByReference info = new LongByReference();
            LongByReference statusTime = new LongByReference();
            boolean ok = AutoReplyPrint.INSTANCE.CP_Printer_GetPrinterStatusInfo(
                    hPrinter, err, info, statusTime);
            if (ok) {
                sb.append(String.format(" 동기[err=0x%04X info=0x%04X]",
                        err.getValue() & 0xFFFFL, info.getValue() & 0xFFFFL));
            } else {
                sb.append(" 동기[조회실패]");
            }
        } catch (Throwable t) {
            sb.append(" 동기[미지원]");
        }

        // portOk 는 plainState() 의 `연결=` 이 담당한다 (중복 제거).
        return sb.toString();
    }

    /**
     * SDK 글로벌 status 콜백을 1회만 등록한다.
     *
     * <p>로그 양식: {@code printer info status: 0xXXXX [비트]... phase=<상태명>} +
     * 에러가 있으면 {@code error status: 0xXXXX [비트]...} 추가 줄.
     * 동시에 게이팅용 volatile 캐시 8개를 갱신한다.
     *
     * <p>info 비트 (CAPrinterStatus.java):
     * <ul>
     *   <li>0x02 INFO_LABELPAPER — 라벨용지 적재됨</li>
     *   <li>0x04 INFO_LABELMODE — 라벨 모드</li>
     *   <li>0x08 INFO_HAVEDATA — 버퍼에 인쇄 대기 데이터 있음</li>
     *   <li>0x10 INFO_NOPAPERCANCELED — 용지 없어 인쇄 취소됨</li>
     *   <li>0x20 INFO_PAPERNOFETCH — 인쇄됨 + 사용자가 안 뗌</li>
     *   <li>0x40 INFO_PRINTIDLE — 인쇄 엔진 idle</li>
     *   <li>0x80 INFO_RECVIDLE — USB 수신 idle</li>
     * </ul>
     */
    private static synchronized void ensureStatusCallbackRegistered() {
        if (statusCallbackRegistered) {
            return;
        }
        statusCallback = new AutoReplyPrint.CP_OnPrinterStatusEvent_Callback() {
            @Override
            public void CP_OnPrinterStatusEvent(Pointer h, long errorStatus,
                                                long infoStatus, Pointer ctx) {
                AutoReplyPrint.CP_PrinterStatus s =
                        new AutoReplyPrint.CP_PrinterStatus(errorStatus, infoStatus);

                // 게이팅용 캐시 갱신 (printBitmap 의 게이트가 읽음)
                lastStatusTime = System.currentTimeMillis();
                lastErrorOccurred = s.ERROR_OCCURED();
                if (lastErrorOccurred) {
                    lastErrorStatusBits = errorStatus & 0xFFFFL;
                    lastErrorTime = lastStatusTime;
                }
                lastErrorIsNoPaper = s.ERROR_NOPAPER();
                lastErrorIsCoverUp = s.ERROR_COVERUP();
                lastInfoRecvIdle = s.INFO_RECVIDLE();
                lastInfoPrintIdle = s.INFO_PRINTIDLE();
                lastInfoNoPaperCanceled = s.INFO_NOPAPERCANCELED();

                // PAPERNOFETCH 의 false→true 상승 edge 를 센다.
                // 레벨(현재 true 인가)이 아니라 edge 여야 하는 이유: 앞 라벨이 안 떼어져
                // 있으면 레벨은 이미 true 라 "내 라벨이 나왔는가" 를 구별할 수 없다.
                // 보류 상황에서도 edge 는 반드시 생긴다 —
                //   앞 라벨 peel(true) → 운영자가 뗌(false) → 붙잡힌 페이지 인쇄(true).
                // 즉 이 카운터의 증가 = "내 라벨이 물리적으로 peel 에 도달했다".
                final boolean prevPaperNoFetch = lastInfoPaperNoFetch;
                lastInfoPaperNoFetch = s.INFO_PAPERNOFETCH();
                if (!prevPaperNoFetch && lastInfoPaperNoFetch) {
                    paperNoFetchRiseCount++;
                }

                // 떼기 상태 전이 — logcat 전용. 파일 로그는 건드리지 않는다
                // (라벨 1장당 2줄씩 늘어나 운영 로그가 두꺼워짐).
                if (lastLoggedPaperNoFetch == null
                        || lastLoggedPaperNoFetch != lastInfoPaperNoFetch) {
                    lastLoggedPaperNoFetch = lastInfoPaperNoFetch;
                    Log.i(TAG, (currentOrderTag != null ? currentOrderTag + " " : "")
                            + "라벨 → "
                            + (lastInfoPaperNoFetch ? "나옴(안 뗀 상태)" : "떼어짐/없음"));
                }

                // ── phase 비콘 로그: ERROR 만 출력, 정상 phase(수신중/인쇄중/대기중 등)는 무음 ──
                // 정상 phase 는 라벨 라이프사이클 로그(출력중/출력끝)와 PAPERNOFETCH 추적으로
                // 충분히 식별 가능하므로, 라벨 처리 흐름과 인터리빙되는 노이즈를 제거한다.
                if (s.ERROR_OCCURED()) {
                    final String phase = decodePhase(s);
                    if (!phase.equals(lastLoggedPhase)) {
                        StringBuilder sb = new StringBuilder();
                        if (currentOrderTag != null) {
                            sb.append(currentOrderTag).append(' ');
                        }
                        sb.append("phase=").append(phase);
                        sb.append(String.format(" ERROR=0x%04X", errorStatus & 0xFFFFL));
                        if (s.ERROR_NOPAPER())  sb.append("[NoPaper]");
                        if (s.ERROR_COVERUP())  sb.append("[CoverUp]");
                        if (s.ERROR_OVERHEAT()) sb.append("[Overheat]");
                        if (s.ERROR_CUTTER())   sb.append("[Cutter]");
                        if (s.ERROR_FLASH())    sb.append("[Flash]");
                        if (s.ERROR_VOLTAGE())  sb.append("[Voltage]");
                        if (s.ERROR_MARKER())   sb.append("[Marker]");
                        if (s.ERROR_ENGINE())   sb.append("[Engine]");
                        if (s.ERROR_MOTOR())    sb.append("[Motor]");
                        log(sb.toString());
                        lastLoggedPhase = phase;
                    }
                } else if (lastLoggedPhase != null) {
                    // ERROR 해제 — 한 번만 알림. 어떤 조치(용지 교체/커버 닫음 등) 로 회복됐는지
                    // 사후 추적이 가능하도록 직전 phase 를 첨부한다.
                    final String prevPhase = lastLoggedPhase;
                    final String tag = currentOrderTag;
                    log((tag != null ? tag + " " : "") + "ERROR 해제 (이전: " + prevPhase + ")");
                    lastLoggedPhase = null;
                }
            }
        };
        try {
            boolean ok = AutoReplyPrint.INSTANCE.CP_Printer_AddOnPrinterStatusEvent(
                    statusCallback, Pointer.NULL);
            statusCallbackRegistered = ok;
            log("[CALLBACK] PrinterStatusEvent register -> " + ok);
        } catch (Throwable t) {
            log("[CALLBACK] PrinterStatusEvent register 실패: " + t.getMessage());
        }
    }

    /**
     * info/error 비트 조합을 사람이 읽기 쉬운 phase 한 단어로 매핑한다.
     * 우선순위: 에러 → 종이떼기대기 → 수신중 → 인쇄중 → 데이터있음(인쇄대기) → 대기.
     */
    private static String decodePhase(AutoReplyPrint.CP_PrinterStatus s) {
        if (s.ERROR_OCCURED()) {
            // 펌웨어 특성: 커버를 열어도 NoPaper 비트만 set 되고 CoverUp 비트는 안 뜨는
            // 단말이 있다 (D2s_KDS 등). 비트만으로는 둘을 구별할 수 없으므로 라벨에
            // 양가성을 노출 — 운영자가 커버 닫힘 + 용지 둘 다 확인하도록.
            if (s.ERROR_NOPAPER()) return "용지없음/커버열림";
            if (s.ERROR_COVERUP()) return "커버열림";
            if (s.ERROR_OVERHEAT()) return "과열";
            return "에러";
        }
        if (s.INFO_NOPAPERCANCELED()) return "용지없음취소";
        if (s.INFO_PAPERNOFETCH())    return "종이떼기대기중";
        if (!s.INFO_RECVIDLE())       return "수신중";
        if (!s.INFO_PRINTIDLE())      return "인쇄중";
        if (s.INFO_HAVEDATA())        return "인쇄대기";
        return "대기중";
    }

    private static void log(String message) {
        String logLine = "[LabelPrinter] " + message;
        Log.i(TAG, message);
        if (sActivity != null) {
            sActivity.appendLogToFile(logLine);
        }
    }

    public static synchronized void close() {
        log("[CLOSE] Closing label printer connection");
        if (hPrinter != Pointer.NULL) {
            AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
            hPrinter = Pointer.NULL;
            printCount.set(0);
        }
        if (statusCallbackRegistered && statusCallback != null) {
            try {
                AutoReplyPrint.INSTANCE.CP_Printer_RemoveOnPrinterStatusEvent(statusCallback);
            } catch (Throwable ignored) {
            }
            statusCallbackRegistered = false;
        }
        // dedup 캐시 리셋 — 재오픈 시 첫 비콘부터 다시 로그
        lastLoggedPhase = null;
        lastLoggedPaperNoFetch = null;
        lastLoggedConnectDiag = null;
        currentOrderTag = null;
        lastAckDiagnostic = null;
    }
}
