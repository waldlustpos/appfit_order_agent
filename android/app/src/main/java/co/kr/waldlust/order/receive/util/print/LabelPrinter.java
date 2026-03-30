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
                                       boolean useCalibrate,
                                       String orderNo,
                                       int labelIndex,
                                       int totalLabels) {
        boolean result = false;
        printCount++;
        long startTime = System.currentTimeMillis();

        String indexSuffix = (totalLabels > 1) ? " " + labelIndex + "/" + totalLabels : "";
        log("#" + printCount + " 출력시작 (주문: " + orderNo + ")" + indexSuffix);

        try {
            // autoReplyMode가 변경된 경우 재연결 필요
            boolean needReconnect = (autoReplyMode != currentAutoReplyMode);

            // Check connection
            if (needReconnect || !AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter)) {
                if (hPrinter != Pointer.NULL) {
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
                        hPrinter = AutoReplyPrint.INSTANCE.CP_Port_OpenUsb(port, autoReplyMode);
                        if (AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                            currentAutoReplyMode = autoReplyMode;
                            break;
                        }
                    }
                }

                if (!AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log("#" + printCount + " 출력결과 -> 실패 [연결오류] (" + elapsed + "ms)" + indexSuffix);
                    return false;
                }
            }

            int bitmapWidth = bitmap.getWidth();
            int bitmapHeight = bitmap.getHeight();

            // 캘리브레이션 (옵션)
            if (useCalibrate) {
                AutoReplyPrint.INSTANCE.CP_Label_CalibrateLabel(hPrinter);
            }

            // 프린터 초기화
            AutoReplyPrint.INSTANCE.CP_Pos_ResetPrinter(hPrinter);

            // Back paper to print position (옵션)
            if (useBackToPrint) {
                AutoReplyPrint.INSTANCE.CP_Label_BackPaperToPrintPosition(hPrinter);
            }

            // 페이지 시작 + 이미지 그리기
            AutoReplyPrint.INSTANCE.CP_Label_PageBegin(
                    hPrinter, 0, 0, bitmapWidth, bitmapHeight,
                    AutoReplyPrint.CP_Label_Rotation_0);
            AutoReplyPrint.CP_Label_DrawImageFromData_Helper.DrawImageFromBitmap(
                    hPrinter, 0, 0, bitmapWidth, bitmapHeight, bitmap,
                    AutoReplyPrint.CP_ImageBinarizationMethod_Thresholding,
                    AutoReplyPrint.CP_Label_Rotation_0);

            // 인쇄
            AutoReplyPrint.INSTANCE.CP_Label_PagePrint(hPrinter, 1);

            // Feed paper to tear position (옵션)
            if (useFeedToTear) {
                AutoReplyPrint.INSTANCE.CP_Label_FeedPaperToTearPosition(hPrinter);
            }

            // 상태 폴링 (옵션)
            if (useStatusPolling) {
                waitForPrintIdle(hPrinter);
            }

            result = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + printCount + " 출력결과 -> " + (result ? "성공" : "실패") + " (" + elapsed + "ms)" + indexSuffix);

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + printCount + " 출력결과 -> 실패 [예외: " + e.getMessage() + "] (" + elapsed + "ms)" + indexSuffix);
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
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

        for (int i = 0; i < 50; i++) {
            try {
                AutoReplyPrint.INSTANCE.CP_Printer_GetPrinterStatusInfo(
                        handle, errorStatus, infoStatus, timestamp);
                long info = infoStatus.getValue();

                // INFO_PRINTIDLE 비트 확인 (bit 5)
                if ((info & 0x20) != 0) {
                    return;
                }

                Thread.sleep(100);
            } catch (InterruptedException e) {
                return;
            } catch (Exception e) {
                return;
            }
        }
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
