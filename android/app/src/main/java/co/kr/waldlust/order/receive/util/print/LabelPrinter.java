package co.kr.waldlust.order.receive.util.print;

import android.graphics.Bitmap;
import android.util.Log;

import com.caysn.autoreplyprint.AutoReplyPrint;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.LongByReference;

import co.kr.waldlust.order.receive.MainActivity;

public class LabelPrinter {
    private static final String TAG = "LabelPrinter";
    private static Pointer hPrinter = Pointer.NULL;
    private static int currentAutoReplyMode = 0;
    private static int printCount = 0;
    private static MainActivity sActivity = null;

    /**
     * MainActivity 참조를 설정합니다. 파일 로깅에 사용됩니다.
     */
    public static void init(MainActivity activity) {
        sActivity = activity;
    }

    // Supported VID:PID pairs
    // VID:0x4B43,PID:0x3538
    // VID:0x4B43,PID:0x3830
    // VID:0x0FE6,PID:0x811E
    // VID:0x067B,PID:0x2303

    public static boolean printBitmap(Bitmap bitmap,
                                       int autoReplyMode,
                                       boolean useFeedToTear,
                                       boolean useBackToPrint,
                                       boolean useStatusPolling,
                                       boolean useCalibrate) {
        boolean result = false;
        printCount++;
        long startTime = System.currentTimeMillis();

        String config = "autoReply=" + autoReplyMode
                + " feedToTear=" + useFeedToTear
                + " backToPrint=" + useBackToPrint
                + " polling=" + useStatusPolling
                + " calibrate=" + useCalibrate;

        log("========== LABEL PRINT #" + printCount + " START ==========");
        log("[CONFIG] " + config);

        try {
            // autoReplyMode가 변경된 경우 재연결 필요
            boolean needReconnect = (autoReplyMode != currentAutoReplyMode);
            if (needReconnect) {
                log("[CONNECT] autoReplyMode changed: " + currentAutoReplyMode + " -> " + autoReplyMode + ", reconnecting...");
            }

            // Check connection
            if (needReconnect || !AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter)) {
                if (hPrinter != Pointer.NULL) {
                    log("[CONNECT] Closing existing connection...");
                    AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
                    hPrinter = Pointer.NULL;
                }

                // Attempt to open known USB ports
                String[] ports = {
                        "VID:0x4B43,PID:0x3538",
                        "VID:0x4B43,PID:0x3830",
                        "VID:0x0FE6,PID:0x811E",
                        "VID:0x067B,PID:0x2303"
                };

                for (String port : ports) {
                    if (!AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                        log("[CONNECT] Trying port: " + port + " (autoReplyMode=" + autoReplyMode + ")");
                        hPrinter = AutoReplyPrint.INSTANCE.CP_Port_OpenUsb(port, autoReplyMode);
                        if (AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                            currentAutoReplyMode = autoReplyMode;
                            log("[CONNECT] SUCCESS - port: " + port);
                            break;
                        }
                    }
                }

                if (!AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                    log("[CONNECT] FAILED - no label printer found");
                    log("========== LABEL PRINT #" + printCount + " END (CONNECT FAIL) ==========");
                    return false;
                }
            } else {
                log("[CONNECT] Reusing existing connection (autoReplyMode=" + currentAutoReplyMode + ")");
            }

            int bitmapWidth = bitmap.getWidth();
            int bitmapHeight = bitmap.getHeight();
            log("[BITMAP] size=" + bitmapWidth + "x" + bitmapHeight);

            // 캘리브레이션 (옵션)
            if (useCalibrate) {
                long t = System.currentTimeMillis();
                log("[STEP] CP_Label_CalibrateLabel -> calling...");
                AutoReplyPrint.INSTANCE.CP_Label_CalibrateLabel(hPrinter);
                log("[STEP] CP_Label_CalibrateLabel -> done (" + (System.currentTimeMillis() - t) + "ms)");
            }

            // 프린터 초기화
            {
                long t = System.currentTimeMillis();
                AutoReplyPrint.INSTANCE.CP_Pos_ResetPrinter(hPrinter);
                log("[STEP] CP_Pos_ResetPrinter -> done (" + (System.currentTimeMillis() - t) + "ms)");
            }

            // Back paper to print position (옵션)
            if (useBackToPrint) {
                long t = System.currentTimeMillis();
                AutoReplyPrint.INSTANCE.CP_Label_BackPaperToPrintPosition(hPrinter);
                log("[STEP] CP_Label_BackPaperToPrintPosition -> done (" + (System.currentTimeMillis() - t) + "ms)");
            } else {
                log("[STEP] CP_Label_BackPaperToPrintPosition -> SKIPPED");
            }

            // 페이지 시작 + 이미지 그리기
            {
                long t = System.currentTimeMillis();
                AutoReplyPrint.INSTANCE.CP_Label_PageBegin(
                        hPrinter, 0, 0, bitmapWidth, bitmapHeight,
                        AutoReplyPrint.CP_Label_Rotation_0);
                AutoReplyPrint.CP_Label_DrawImageFromData_Helper.DrawImageFromBitmap(
                        hPrinter, 0, 0, bitmapWidth, bitmapHeight, bitmap,
                        AutoReplyPrint.CP_ImageBinarizationMethod_Thresholding,
                        AutoReplyPrint.CP_Label_Rotation_0);
                log("[STEP] PageBegin+DrawImage -> done (" + (System.currentTimeMillis() - t) + "ms)");
            }

            // 인쇄
            {
                long t = System.currentTimeMillis();
                AutoReplyPrint.INSTANCE.CP_Label_PagePrint(hPrinter, 1);
                log("[STEP] CP_Label_PagePrint(1) -> done (" + (System.currentTimeMillis() - t) + "ms)");
            }

            // Feed paper to tear position (옵션)
            if (useFeedToTear) {
                long t = System.currentTimeMillis();
                AutoReplyPrint.INSTANCE.CP_Label_FeedPaperToTearPosition(hPrinter);
                log("[STEP] CP_Label_FeedPaperToTearPosition -> done (" + (System.currentTimeMillis() - t) + "ms)");
            } else {
                log("[STEP] CP_Label_FeedPaperToTearPosition -> SKIPPED");
            }

            // 상태 폴링 (옵션)
            if (useStatusPolling) {
                log("[POLLING] Starting status polling...");
                waitForPrintIdle(hPrinter);
            } else {
                log("[POLLING] SKIPPED");
            }

            result = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
            long elapsed = System.currentTimeMillis() - startTime;
            log("[RESULT] success=" + result + " totalTime=" + elapsed + "ms");
            log("========== LABEL PRINT #" + printCount + " END ==========");

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log("[ERROR] " + e.getMessage() + " (after " + elapsed + "ms)");
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
            log("========== LABEL PRINT #" + printCount + " END (ERROR) ==========");
        }

        return result;
    }

    /**
     * 프린터가 인쇄 idle 상태가 될 때까지 폴링 대기.
     * 최대 5초 (100ms × 50회) 대기.
     */
    private static void waitForPrintIdle(Pointer handle) {
        LongByReference errorStatus = new LongByReference();
        LongByReference infoStatus = new LongByReference();
        LongByReference timestamp = new LongByReference();
        long pollStart = System.currentTimeMillis();

        for (int i = 0; i < 50; i++) {
            try {
                AutoReplyPrint.INSTANCE.CP_Printer_GetPrinterStatusInfo(
                        handle, errorStatus, infoStatus, timestamp);
                long info = infoStatus.getValue();
                long error = errorStatus.getValue();

                String flags = decodeInfoFlags(info);
                log("[POLLING] [" + i + "] info=0x" + Long.toHexString(info)
                        + " (" + flags + ")"
                        + " error=0x" + Long.toHexString(error));

                // INFO_PRINTIDLE 비트 확인 (bit 5)
                if ((info & 0x20) != 0) {
                    long elapsed = System.currentTimeMillis() - pollStart;
                    log("[POLLING] Printer IDLE detected after " + elapsed + "ms (polls=" + (i + 1) + ")");
                    return;
                }

                Thread.sleep(100);
            } catch (InterruptedException e) {
                log("[POLLING] Interrupted");
                return;
            } catch (Exception e) {
                log("[POLLING] Error: " + e.getMessage());
                return;
            }
        }

        long elapsed = System.currentTimeMillis() - pollStart;
        log("[POLLING] TIMEOUT after " + elapsed + "ms - printer did not become idle");
    }

    /**
     * info 상태 비트를 플래그 문자열로 디코딩.
     */
    private static String decodeInfoFlags(long info) {
        StringBuilder sb = new StringBuilder();
        if ((info & 0x01) != 0) sb.append("NOPAPER_CANCELED ");
        if ((info & 0x02) != 0) sb.append("LABELPAPER ");
        if ((info & 0x04) != 0) sb.append("LABELMODE ");
        if ((info & 0x08) != 0) sb.append("HAVEDATA ");
        if ((info & 0x10) != 0) sb.append("PAPERNOFETCH ");
        if ((info & 0x20) != 0) sb.append("PRINTIDLE ");
        if ((info & 0x40) != 0) sb.append("RECVIDLE ");
        return sb.toString().trim();
    }

    /**
     * Logcat + 파일 로그 동시 기록.
     */
    private static void log(String message) {
        String logLine = "[LabelPrinter] " + message;
        Log.i(TAG, message);
        if (sActivity != null) {
            sActivity.appendLogToFile(logLine);
        }
    }

    public static void close() {
        log("[CLOSE] Closing label printer connection");
        if (hPrinter != Pointer.NULL) {
            AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
            hPrinter = Pointer.NULL;
            printCount = 0;
        }
    }
}
