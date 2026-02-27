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

                // 프린터 초기화 (연속 출력 시 위치 밀림 방지)
                AutoReplyPrint.INSTANCE.CP_Pos_ResetPrinter(hPrinter);

                // Back paper to print position
                AutoReplyPrint.INSTANCE.CP_Label_BackPaperToPrintPosition(hPrinter);

                // Print Bitmap
                AutoReplyPrint.CP_Pos_PrintRasterImageFromData_Helper.PrintRasterImageFromBitmap(
                        hPrinter,
                        bitmap.getWidth(),
                        bitmap.getHeight(),
                        bitmap,
                        AutoReplyPrint.CP_ImageBinarizationMethod_Thresholding,
                        0);

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
