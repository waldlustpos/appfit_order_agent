package co.kr.waldlust.order.receive.util.print;

import android.graphics.Bitmap;
import android.util.Log;

import com.caysn.autoreplyprint.AutoReplyPrint;
import com.sun.jna.Pointer;

import java.util.concurrent.atomic.AtomicInteger;

import co.kr.waldlust.order.receive.MainActivity;

public class LabelPrinter {
    private static final String TAG = "LabelPrinter";
    private static Pointer hPrinter = Pointer.NULL;
    private static int currentAutoReplyMode = 0;
    // 라벨 재출력 버튼 연타 등 동시 호출 시 카운터 경쟁을 방지하기 위해 Atomic 사용
    private static final AtomicInteger printCount = new AtomicInteger(0);
    private static MainActivity sActivity = null;

    /** {@link AutoReplyPrint#CP_Pos_QueryPrintResult} 의 동기 블로킹 timeout. samplelabel 표준값. */
    private static final int QUERY_PRINT_RESULT_TIMEOUT_MS = 30_000;

    /** ERROR_OCCURED 상태에서 클리어 까지 짧게 대기 — 피크타임 큐 막힘 방지. */
    private static final long ERROR_QUICK_GATE_MS = 500L;

    /** RECVIDLE/PRINTIDLE 동기화 timeout — 직전 라벨 처리 완료 대기. */
    private static final long IDLE_WAIT_MS = 5_000L;

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

    /** 동일 phase 연속 출력을 막기 위한 dedup 캐시 (null = 아직 미로깅). */
    private static volatile String lastLoggedPhase = null;

    /**
     * 현재 활성 라벨의 표시 prefix (예: "[0812]" 또는 "[0812 1/7]").
     * ERROR phase 비콘에 컨텍스트 prefix 로 사용 — 어느 라벨에서 에러가 났는지 식별용.
     * printBitmap 시작 시 갱신되고, 다음 printBitmap 이 시작되거나 close() 까지 유지된다.
     */
    private static volatile String currentOrderTag = null;

    public static void init(MainActivity activity) {
        sActivity = activity;
        ensureStatusCallbackRegistered();
    }

    // Supported VID:PID pairs
    // VID:0x4B43,PID:0x3538
    // VID:0x4B43,PID:0x3830
    // VID:0x0FE6,PID:0x811E
    // VID:0x067B,PID:0x2303

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
     */
    public static synchronized boolean printBitmap(Bitmap bitmap,
                                       int autoReplyMode,
                                       boolean useFeedToTear,
                                       boolean useBackToPrint,
                                       boolean useCalibrate,
                                       String orderNo,
                                       int labelIndex,
                                       int totalLabels) {
        boolean result = false;
        final int seq = printCount.incrementAndGet();
        long startTime = System.currentTimeMillis();

        // 운영자 시점의 식별자: 주문번호 + (다중 라벨일 때) 인덱스. 모든 라이프사이클 로그에 prefix.
        // 예: "[0795]" 또는 "[0795 1/7]"
        final String orderTag = "[" + orderNo
                + (totalLabels > 1 ? " " + labelIndex + "/" + totalLabels : "") + "]";
        // 활성 라벨 컨텍스트 등록 — ERROR phase 비콘에 prefix 로 사용.
        currentOrderTag = orderTag;
        log("#" + seq + " " + orderTag + " 출력시작");

        try {
            // autoReplyMode 가 변경됐거나 포트가 죽었으면 재연결.
            // QueryPrintResult timeout 으로 USB 가 손상된 케이스도 이 분기가 자동 회복한다.
            boolean needReconnect = (autoReplyMode != currentAutoReplyMode);
            if (needReconnect || !AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter)) {
                if (hPrinter != Pointer.NULL) {
                    AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
                    hPrinter = Pointer.NULL;
                }

                String[] ports = {
                        "VID:0x4B43,PID:0x3538",
                        "VID:0x4B43,PID:0x3830",
                        "VID:0x0FE6,PID:0x811E",
                        "VID:0x067B,PID:0x2303"
                };

                for (String port : ports) {
                    if (!AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                        hPrinter = AutoReplyPrint.INSTANCE.CP_Port_OpenUsb(port, autoReplyMode);
                        if (AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                            currentAutoReplyMode = autoReplyMode;
                            break;
                        }
                    }
                }

                if (!AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log("#" + seq + " " + orderTag + " 실패 [연결오류] (" + elapsed + "ms)");
                    return false;
                }
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
                    log("#" + seq + " " + orderTag + " 복구대기 진입 [" + entryPhase
                            + "] status=0x" + String.format("%04X", lastErrorStatusBits));
                    boolean interrupted = false;
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
                        if (now - lastNotice >= 60_000L) {
                            log("#" + seq + " " + orderTag + " 복구대기중 elapsed="
                                    + ((now - waitStart) / 1000) + "s");
                            lastNotice = now;
                        }
                    }
                    if (interrupted) {
                        long elapsed = System.currentTimeMillis() - startTime;
                        log("#" + seq + " " + orderTag + " 실패 [복구대기 인터럽트] ("
                                + elapsed + "ms)");
                        return false;
                    }
                    long waited = System.currentTimeMillis() - waitStart;
                    log("#" + seq + " " + orderTag + " 복구감지 [" + entryPhase
                            + " → OK] wait=" + waited + "ms — 인쇄재개");
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
                        return false;
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

            AutoReplyPrint.INSTANCE.CP_Label_PagePrint(hPrinter, 1);

            if (useFeedToTear) {
                AutoReplyPrint.INSTANCE.CP_Label_FeedPaperToTearPosition(hPrinter);
            }

            // samplelabel `TestFunction.java:282` 의 Test_Pos_QueryPrintResult 와 동일한 호출.
            // 인쇄 완료 또는 timeout 까지 동기 블로킹 → 다음 호출의 진입을 자연 직렬화.
            // ACK 결과는 아래 출력결과 라인에 통합 (정상 흐름은 출력끝 한 줄로 충분).
            boolean printed = AutoReplyPrint.INSTANCE.CP_Pos_QueryPrintResult(
                    hPrinter, QUERY_PRINT_RESULT_TIMEOUT_MS);

            // 1-D 후처리: PageBegin/PagePrint 진행 중 NoPaper 가 발생한 race 케이스.
            // 진입 게이트(1-B-①)가 paper/cover 를 무한 대기로 차단하므로 보통 도달하지
            // 않지만, idle 게이트 통과 직후 PagePrint 도중 용지가 떨어지는 race 안전망.
            // false 반환 → Dart 재시도(1.5초) → 다음 진입 시 게이트 무한 대기로 복구.
            if (!printed && lastInfoNoPaperCanceled) {
                log("#" + seq + " " + orderTag + " 실패 [용지없음 race — Dart 재시도 위임]");
                return false;
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
                log("#" + seq + " " + orderTag + " 떼기대기 (PAPERNOFETCH, buzzer 활성)");
                long fetchStart = System.currentTimeMillis();
                long lastNotice = fetchStart;
                boolean interrupted = false;
                while (lastInfoPaperNoFetch) {
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
                    log("#" + seq + " " + orderTag + " 실패 [떼기대기 인터럽트]");
                    return false;
                }
                long fetchWait = System.currentTimeMillis() - fetchStart;
                boolean portOk = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
                long elapsed2 = System.currentTimeMillis() - startTime;
                log("#" + seq + " " + orderTag + " 떼어짐 wait=" + fetchWait
                        + "ms (" + (portOk ? "출력끝" : "실패")
                        + ", 총 " + elapsed2 + "ms)");
                return portOk;
            }

            result = printed && AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " " + orderTag + " " + (result ? "출력끝" : "실패")
                    + " (" + elapsed + "ms)");

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " " + orderTag + " 실패 [예외: " + e.getMessage() + "] ("
                    + elapsed + "ms)");
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
        }

        return result;
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
                lastInfoPaperNoFetch = s.INFO_PAPERNOFETCH();

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
        currentOrderTag = null;
    }
}
