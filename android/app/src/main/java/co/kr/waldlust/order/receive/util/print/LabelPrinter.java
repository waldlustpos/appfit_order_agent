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
    private static volatile boolean lastInfoRecvIdle = false;
    private static volatile boolean lastInfoPrintIdle = false;
    private static volatile boolean lastInfoNoPaperCanceled = false;
    private static volatile boolean lastInfoPaperNoFetch = false;

    /** 동일 status 비콘 연속 출력을 막기 위한 dedup 캐시 (-1 = 아직 미로깅). */
    private static volatile long lastLoggedInfoStatusBits = -1L;
    private static volatile long lastLoggedErrorStatusBits = -1L;

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

        String indexSuffix = (totalLabels > 1) ? " " + labelIndex + "/" + totalLabels : "";
        log("#" + seq + " 출력시작 (주문: " + orderNo + ")" + indexSuffix
                + " autoReply=" + autoReplyMode);

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
                    log("#" + seq + " 출력결과 -> 실패 [연결오류] (" + elapsed + "ms)" + indexSuffix);
                    return false;
                }
            }

            // 1-B-① ERROR 짧은 게이트 — 큐 안 막고 false 반환 (재시도 위임)
            if (lastErrorOccurred) {
                long erStart = System.currentTimeMillis();
                while (lastErrorOccurred
                        && (System.currentTimeMillis() - erStart) < ERROR_QUICK_GATE_MS) {
                    try { Thread.sleep(50); } catch (InterruptedException e) {
                        Thread.currentThread().interrupt(); break;
                    }
                }
                if (lastErrorOccurred) {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log("#" + seq + " 출력결과 -> 실패 [프린터 에러 0x"
                            + String.format("%04X", lastErrorStatusBits)
                            + " — 재시도 위임] (" + elapsed + "ms)" + indexSuffix);
                    return false;
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
                long waited = System.currentTimeMillis() - waitStart;
                if (waited >= 100) {
                    log("#" + seq + " idle 게이트 통과 wait=" + waited
                            + "ms recv=" + lastInfoRecvIdle
                            + " print=" + lastInfoPrintIdle
                            + " npc=" + lastInfoNoPaperCanceled + indexSuffix);
                }
                // timeout 도달했지만 idle 미달성 → 그래도 진행 (QueryPrintResult 가 2차 안전망)
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
            long ackStart = System.currentTimeMillis();
            boolean printed = AutoReplyPrint.INSTANCE.CP_Pos_QueryPrintResult(
                    hPrinter, QUERY_PRINT_RESULT_TIMEOUT_MS);
            long ackWait = System.currentTimeMillis() - ackStart;
            log("#" + seq + " QueryPrintResult -> " + printed + " (" + ackWait + "ms)" + indexSuffix);

            // 1-D 후처리: 용지없음 취소는 진짜 실패 → 재시도 위임
            if (!printed && lastInfoNoPaperCanceled) {
                log("#" + seq + " QueryPrintResult -> false [용지없음으로 인쇄 취소됨]" + indexSuffix);
                return false;
            }

            // 1-D-① 장시간 방치 누락 방지 — PAPERNOFETCH 풀릴 때까지 무한 대기
            // PagePrint 추가 발사 안 함 (펌웨어 큐에 이미 보관됨, 떼면 자동 인쇄)
            if (!printed && lastInfoPaperNoFetch) {
                log("#" + seq + " 사용자 떼기 대기 시작 (PAPERNOFETCH set, buzzer 활성)"
                        + indexSuffix);
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
                        log("#" + seq + " 떼기 대기 중 elapsed="
                                + ((now - fetchStart) / 1000) + "s" + indexSuffix);
                        lastNotice = now;
                    }
                }
                if (interrupted) {
                    log("#" + seq + " 떼기 대기 인터럽트 — 누락 처리" + indexSuffix);
                    return false;
                }
                long fetchWait = System.currentTimeMillis() - fetchStart;
                log("#" + seq + " 떼기 감지 wait=" + fetchWait
                        + "ms — 펌웨어 인쇄 시작" + indexSuffix);

                // 사용자 떼는 순간 펌웨어가 큐된 라벨 인쇄 → 다시 ACK 대기
                printed = AutoReplyPrint.INSTANCE.CP_Pos_QueryPrintResult(
                        hPrinter, QUERY_PRINT_RESULT_TIMEOUT_MS);
                log("#" + seq + " 떼기 후 QueryPrintResult -> " + printed + indexSuffix);
            }

            result = printed && AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " 출력결과 -> " + (result ? "성공" : "실패") + " (" + elapsed + "ms)" + indexSuffix);

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " 출력결과 -> 실패 [예외: " + e.getMessage() + "] (" + elapsed + "ms)" + indexSuffix);
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
                lastInfoRecvIdle = s.INFO_RECVIDLE();
                lastInfoPrintIdle = s.INFO_PRINTIDLE();
                lastInfoNoPaperCanceled = s.INFO_NOPAPERCANCELED();
                lastInfoPaperNoFetch = s.INFO_PAPERNOFETCH();

                // dedup: 동일 status 비트값 연속이면 로그 skip (idle 비콘 폭주 방지)
                final long infoMasked = infoStatus & 0xFFFFL;
                final long errorMasked = errorStatus & 0xFFFFL;

                if (infoMasked != lastLoggedInfoStatusBits) {
                    StringBuilder sb = new StringBuilder();
                    sb.append(String.format("printer info status: 0x%04X", infoMasked));
                    if (s.INFO_LABELMODE())       sb.append("[LabelMode]");
                    if (s.INFO_LABELPAPER())      sb.append("[LabelPaper]");
                    if (s.INFO_HAVEDATA())        sb.append("[HaveData]");
                    if (s.INFO_NOPAPERCANCELED()) sb.append("[NoPaperCanceled]");
                    if (s.INFO_PAPERNOFETCH())    sb.append("[Paper NOT Fetch]");
                    if (s.INFO_PRINTIDLE())       sb.append("[PrintIdle]");
                    if (s.INFO_RECVIDLE())        sb.append("[RecvIdle]");
                    sb.append(" phase=").append(decodePhase(s));
                    log(sb.toString());
                    lastLoggedInfoStatusBits = infoMasked;
                }

                if (s.ERROR_OCCURED() && errorMasked != lastLoggedErrorStatusBits) {
                    StringBuilder eb = new StringBuilder();
                    eb.append(String.format("printer error status: 0x%04X", errorMasked));
                    if (s.ERROR_CUTTER())   eb.append("[Cutter]");
                    if (s.ERROR_FLASH())    eb.append("[Flash]");
                    if (s.ERROR_NOPAPER())  eb.append("[NoPaper]");
                    if (s.ERROR_VOLTAGE())  eb.append("[Voltage]");
                    if (s.ERROR_MARKER())   eb.append("[Marker]");
                    if (s.ERROR_ENGINE())   eb.append("[Engine]");
                    if (s.ERROR_OVERHEAT()) eb.append("[Overheat]");
                    if (s.ERROR_COVERUP())  eb.append("[CoverUp]");
                    if (s.ERROR_MOTOR())    eb.append("[Motor]");
                    log(eb.toString());
                    lastLoggedErrorStatusBits = errorMasked;
                } else if (!s.ERROR_OCCURED() && lastLoggedErrorStatusBits != 0L
                        && lastLoggedErrorStatusBits != -1L) {
                    log("printer error cleared");
                    lastLoggedErrorStatusBits = 0L;
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
            if (s.ERROR_NOPAPER()) return "용지없음";
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
        lastLoggedInfoStatusBits = -1L;
        lastLoggedErrorStatusBits = -1L;
    }
}
