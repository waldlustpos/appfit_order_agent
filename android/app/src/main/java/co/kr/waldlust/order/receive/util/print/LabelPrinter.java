package co.kr.waldlust.order.receive.util.print;

import android.graphics.Bitmap;
import android.util.Log;

import com.caysn.autoreplyprint.AutoReplyPrint;
import com.sun.jna.Pointer;

import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;

import co.kr.waldlust.order.receive.MainActivity;

public class LabelPrinter {
    private static final String TAG = "LabelPrinter";
    private static Pointer hPrinter = Pointer.NULL;
    private static int currentAutoReplyMode = 0;
    // 라벨 재출력 버튼 연타 등 동시 호출 시 카운터 경쟁을 방지하기 위해 Atomic 사용
    private static final AtomicInteger printCount = new AtomicInteger(0);
    private static MainActivity sActivity = null;

    /** PagePrint 한 장의 인쇄 완료를 알리는 SDK 콜백을 await 하기 위한 latch. */
    private static final AtomicReference<CountDownLatch> printedLatch = new AtomicReference<>();
    private static AutoReplyPrint.CP_OnPrinterPrintedEvent_Callback printedCallback = null;
    private static boolean callbackRegistered = false;

    /** PrintedEvent 도착까지 최대 대기 시간 — 평균 200ms, 최악 stuck 39초 데이터 기준 5초가 합리. */
    private static final long PRINTED_ACK_TIMEOUT_MS = 5000L;

    public static void init(MainActivity activity) {
        sActivity = activity;
        ensurePrintedCallbackRegistered();
    }

    // Supported VID:PID pairs
    // VID:0x4B43,PID:0x3538
    // VID:0x4B43,PID:0x3830
    // VID:0x0FE6,PID:0x811E
    // VID:0x067B,PID:0x2303

    /**
     * 라벨 한 장을 인쇄하고 SDK 의 PrintedEvent ACK 가 올 때까지 기다린다.
     *
     * <p>autoReplyMode=1 환경에서 SDK 는 한 장의 인쇄가 끝나면 콜백을 fire 한다.
     * 그 신호로 다음 호출과의 race 를 차단해 라벨 누락을 방지한다.
     *
     * <p>비프음 흐름: 사용자가 라벨을 안 떼면 펌웨어가 다음 명령 진입 시 buzzer 를
     * 울려 알린다. NoFetch 비트는 의도적으로 체크하지 않아 이 UX 를 보존한다.
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
            // ACK 타임아웃으로 USB 가 손상된 케이스도 이 분기가 자동 회복한다.
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

            // PagePrint 호출이 끝나기 전에 콜백이 fire 되어도 안전하도록 호출 직전에 latch 발급.
            CountDownLatch latch = new CountDownLatch(1);
            printedLatch.set(latch);

            AutoReplyPrint.INSTANCE.CP_Label_PagePrint(hPrinter, 1);

            if (useFeedToTear) {
                AutoReplyPrint.INSTANCE.CP_Label_FeedPaperToTearPosition(hPrinter);
            }

            // ACK 대기. 타임아웃 시 별도 처리 안 함 — 다음 호출 진입 시 IsConnectionValid 가
            // 죽은 포트면 자연스럽게 재오픈한다.
            if (autoReplyMode == 1) {
                long ackStart = System.currentTimeMillis();
                boolean acked = false;
                try {
                    acked = latch.await(PRINTED_ACK_TIMEOUT_MS, TimeUnit.MILLISECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
                long ackWait = System.currentTimeMillis() - ackStart;
                log("#" + seq + " printed_ack acked=" + acked + " (" + ackWait + "ms)" + indexSuffix);
            }

            result = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " 출력결과 -> " + (result ? "성공" : "실패") + " (" + elapsed + "ms)" + indexSuffix);

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " 출력결과 -> 실패 [예외: " + e.getMessage() + "] (" + elapsed + "ms)" + indexSuffix);
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
        } finally {
            printedLatch.set(null);
        }

        return result;
    }

    /**
     * SDK 글로벌 콜백을 1회만 등록한다. 콜백은 PagePrint 한 장이 완료된 시점에 fire 되며,
     * 현재 발급된 latch 를 countDown 한다.
     */
    private static synchronized void ensurePrintedCallbackRegistered() {
        if (callbackRegistered) {
            return;
        }
        printedCallback = new AutoReplyPrint.CP_OnPrinterPrintedEvent_Callback() {
            @Override
            public void CP_OnPrinterPrintedEvent(Pointer handle, int pageIndex, Pointer context) {
                CountDownLatch latch = printedLatch.get();
                if (latch != null) {
                    latch.countDown();
                }
            }
        };
        try {
            boolean ok = AutoReplyPrint.INSTANCE.CP_Printer_AddOnPrinterPrintedEvent(printedCallback, Pointer.NULL);
            callbackRegistered = ok;
            log("[CALLBACK] PrintedEvent register -> " + ok);
        } catch (Throwable t) {
            log("[CALLBACK] PrintedEvent register 실패: " + t.getMessage());
        }
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
        if (callbackRegistered && printedCallback != null) {
            try {
                AutoReplyPrint.INSTANCE.CP_Printer_RemoveOnPrinterPrintedEvent(printedCallback);
            } catch (Throwable ignored) {
            }
            callbackRegistered = false;
        }
    }
}
