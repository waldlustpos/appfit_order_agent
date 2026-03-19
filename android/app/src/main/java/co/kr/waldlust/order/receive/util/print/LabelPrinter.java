package co.kr.waldlust.order.receive.util.print;

import android.graphics.Bitmap;
import android.util.Log;

import com.caysn.autoreplyprint.AutoReplyPrint;
import com.sun.jna.Pointer;

public class LabelPrinter {
    private static final String TAG = "LabelPrinter";
    private static Pointer hPrinter = Pointer.NULL;

    // Supported VID:PID pairs from PrintBitmapUtils.java
    // VID:0x4B43,PID:0x3538
    // VID:0x4B43,PID:0x3830
    // VID:0x0FE6,PID:0x811E
    // VID:0x067B,PID:0x2303

    public static boolean printBitmap(Bitmap bitmap) {
        boolean result = false;

        try {
            // Check connection
            if (!AutoReplyPrint.INSTANCE.CP_Port_IsConnectionValid(hPrinter)) {
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
                        hPrinter = AutoReplyPrint.INSTANCE.CP_Port_OpenUsb(port, 0);
                        if (AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                            Log.d(TAG, "Connected to label printer: " + port);
                            break;
                        }
                    }
                }
            }

            // Send data if connected
            if (AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter)) {
                Log.d(TAG, "Sending bitmap to label printer...");

                int bitmapWidth = bitmap.getWidth();
                int bitmapHeight = bitmap.getHeight();

                // 프린터 초기화 (연속 출력 시 위치 밀림 방지)
                AutoReplyPrint.INSTANCE.CP_Pos_ResetPrinter(hPrinter);

                // Back paper to print position
                AutoReplyPrint.INSTANCE.CP_Label_BackPaperToPrintPosition(hPrinter);

                // 좌우 위치 절대 고정: CP_Label_PageBegin으로 x=0, y=0 명시 지정하여
                // ESC/POS 상태값에 무관하게 항상 동일한 위치에 출력
                AutoReplyPrint.INSTANCE.CP_Label_PageBegin(
                        hPrinter, 0, 0, bitmapWidth, bitmapHeight,
                        AutoReplyPrint.CP_Label_Rotation_0);

                // DrawImageFromBitmap 헬퍼: 내부적으로 올바른 파라미터 순서로 CP_Label_DrawImageFromPixels 호출
                AutoReplyPrint.CP_Label_DrawImageFromData_Helper.DrawImageFromBitmap(
                        hPrinter, 0, 0, bitmapWidth, bitmapHeight, bitmap,
                        AutoReplyPrint.CP_ImageBinarizationMethod_Thresholding,
                        AutoReplyPrint.CP_Label_Rotation_0);

                AutoReplyPrint.INSTANCE.CP_Label_PagePrint(hPrinter, 1);

                // Feed paper
                AutoReplyPrint.INSTANCE.CP_Label_FeedPaperToTearPosition(hPrinter);

                result = AutoReplyPrint.INSTANCE.CP_Port_IsOpened(hPrinter);
                Log.d(TAG, "Label print command sent. Result: " + result);
            } else {
                Log.e(TAG, "Failed to connect to any label printer.");
            }
        } catch (Exception e) {
            Log.e(TAG, "Error printing label: " + e.getMessage(), e);
        }

        return result;
    }

    public static void close() {
        if (hPrinter != Pointer.NULL) {
            AutoReplyPrint.INSTANCE.CP_Port_Close(hPrinter);
            hPrinter = Pointer.NULL;
        }
    }
}
