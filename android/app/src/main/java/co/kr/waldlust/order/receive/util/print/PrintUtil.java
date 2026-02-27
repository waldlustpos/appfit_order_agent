package co.kr.waldlust.order.receive.util.print;

import android.app.PendingIntent;
import android.app.ProgressDialog;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Message;
import android.util.Log;
import co.kr.waldlust.order.receive.R;
import com.posbank.printer.Printer;
import com.posbank.printer.PrinterConstants;
import com.posbank.printer.PrinterDevice;
import com.posbank.printer.PrinterManager;
import com.posbank.util.StrUtil;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.UnsupportedEncodingException;
import java.text.DecimalFormat;
import java.text.NumberFormat;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.TreeMap;

public class PrintUtil {
    public static final String PRINTER_USB_PERMISSION = "com.posbank.USB_PERMISSION";
    public static final String ACTION_GET_DEFINEED_NV_IMAGE_KEY_CODES = "com.posbank.anction.GET_DEFINED_NV_IMAGE_KEY_CODES";
    public static final String EXTRA_NAME_NV_KEY_CODES = "NVImageKeyCodes";
    private ProgressDialog mProgressDialog;

    public PrinterManager printerManager;
    public static HashMap<String, PrinterDevice> printerDeviceMap;
    public static int discoveryOption;
    public static Printer printer;
    public static ArrayList<Printer> printerList;
    private String TAG = "PrintActivity";
    private Context context;
    private long setCreditInfoTime = 0;

    private static final String CHARSET = "EUC-KR";

    private static final int FONT_SIZE_NORMAL = 0x00;
    private static final int FONT_SIZE_LARGE = 0x11;
    private static final int FONT_SIZE_TALL = 0x10;
    private static final int FONT_SIZE_WIDE = 0x01;

    private static final byte ALIGN_LEFT = 0x00;
    private static final byte ALIGN_CENTER = 0x01;
    private static final byte ALIGN_RIGHT = 0x02;

    private static final byte[] CMD_INIT = { 0x1B, 0x40 };
    private static final byte[] CMD_LF = { 0x0A };
    private static final byte[] CMD_CUT_PAPER = { 0x1D, 0x56, 0x42, 0x00 };
    private static final byte[] CMD_BOLD_ON = { 0x1B, 0x45, 0x01 };
    private static final byte[] CMD_BOLD_OFF = { 0x1B, 0x45, 0x00 };
    private static final byte[] CMD_UNDERLINE_OFF = { 0x1B, 0x2D, 0x00 };

    private static byte[] getSetSizeCmd(int sizeMode) {
        return new byte[] { 0x1D, 0x21, (byte) sizeMode };
    }

    private static byte[] getSetAlignCmd(byte align) {
        return new byte[] { 0x1B, 0x61, align };
    }

    public PrintUtil(Context context) {
        this.context = context;

        printer = null;
        printerList = new ArrayList<>();

        printerManager = new PrinterManager(
                context.getApplicationContext(),
                printerMsgHandler,
                null);
    }

    public void loadPrinters() {
        Log.d(TAG, "loadPrinters: Starting printer discovery");
        if (printerList == null)
            printerList = new ArrayList<>();

        printerList.clear();

        if (null != printerDeviceMap && printerDeviceMap.size() > 0) {
            printerDeviceMap.clear();
        }

        discoveryOption = 0;
        printerManager.setSerialPorts(null);

        discoveryOption |= PrinterConstants.PRINTER_TYPE_USB;

        Log.d(TAG, "loadPrinters: Starting USB discovery with option: " + discoveryOption);
        printerManager.startDiscovery(discoveryOption);
    }

    public void printerConnect() {
        Log.d(TAG, "printerConnect: Starting printer connection process");

        if (null != printerDeviceMap) {
            printerDeviceMap.clear();
        }

        printerDeviceMap = printerManager.getDeviceList();
        Log.d(TAG, "printerConnect: Found " + (printerDeviceMap != null ? printerDeviceMap.size() : 0) + " devices");

        if (null != printerDeviceMap && printerDeviceMap.size() > 0) {
            TreeMap<String, PrinterDevice> tm = new TreeMap<String, PrinterDevice>(printerDeviceMap);
            Iterator<String> iteratorKey = tm.keySet().iterator();

            for (Iterator<String> it = iteratorKey; it.hasNext();) {
                String key = it.next();
                PrinterDevice device = printerDeviceMap.get(key);
                Log.d(TAG, "printerConnect: Processing device - " + device.getDeviceName() + " (Type: "
                        + device.getDeviceType() + ")");

                // [NEW] 라벨프린터(AutoReplyPrint)는 영수증 프린터 목록에서 제외
                if (device.getDeviceType() == PrinterConstants.PRINTER_TYPE_USB) {
                    UsbDevice usbDevice = (UsbDevice) device.getDeviceContext();
                    if (isLabelPrinter(usbDevice)) {
                        Log.d(TAG, "printerConnect: Skipping label printer - " + usbDevice.getDeviceName() + " (VID: "
                                + usbDevice.getVendorId() + ")");
                        continue;
                    }
                }

                if (hasPermission(device)) {
                    Log.d(TAG, "printerConnect: Permission granted for device: " + device.getDeviceName());
                    printer = printerManager.connectDevice(device);
                    printerList.add(printer);
                    if (printer != null) {
                        Log.d(TAG, "Posbank printer connected successfully: " + device.getDeviceName());
                    } else {
                        Log.e(TAG, "Failed to connect to Posbank printer: " + device.getDeviceName());
                    }
                } else {
                    Log.w(TAG, "Permission denied for Posbank printer: " + device.getDeviceName()
                            + ", requesting permission...");
                    requestPermission(device);
                }
            }
        } else {
            Log.w(TAG, "printerConnect: No USB devices found or device map is empty");
        }

        Log.d(TAG, "printerConnect: Connection process completed. Connected printers: " + printerList.size());
    }

    public void test() {
        // try {
        // int i=0;
        // for (Printer p : printerList) {
        // String print = "print" + i;
        // String utf = "";

        // for(int j=0;j<10;j++){ //u001B@ a1
        // utf += "\n\u001B@\u001Ba1\u001B1" + print + "\n\u001Ba0\u001B!\u0000";
        // }

        // //

        // utf = utf + "\n" + "\u001DVB\u0000";

        // //String data, int alignment, int model, int size
        // p.executeDirectIO(utf.getBytes("EUC-KR"));

        // i++;
        // }
        // } catch (UnsupportedEncodingException e) {
        // e.printStackTrace();
        // }
    }

    public void printOrderFromJson(String orderJson, boolean isCancel) {
        if (printerList == null || printerList.isEmpty()) {
            Log.e(TAG, "No Posbank printer connected for printing order.");
            return;
        }

        try {
            JSONObject jsonOrder = new JSONObject(orderJson);
            ByteArrayOutputStream commandStream = new ByteArrayOutputStream();

            commandStream.write(CMD_INIT);

            commandStream.write(getSetAlignCmd(ALIGN_CENTER));

            if (isCancel) {
                commandStream.write(getSetSizeCmd(FONT_SIZE_TALL));
                commandStream.write("[취소주문서]".getBytes(CHARSET));
                commandStream.write(CMD_LF);
                commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                commandStream.write(CMD_LF);
            }

            commandStream.write(CMD_BOLD_ON);
            commandStream.write(getSetSizeCmd(FONT_SIZE_TALL));
            String displayNum = jsonOrder.optString("displayOrderNum", jsonOrder.optString("ordrSimpleId", ""));
            commandStream.write(("주문번호: " + displayNum).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            commandStream.write(CMD_BOLD_OFF);
            commandStream.write(CMD_LF);

            String userName = jsonOrder.optString("userName", "");
            if (!userName.isEmpty() && !userName.equals("null")) {
                commandStream.write(CMD_BOLD_ON);
                commandStream.write(getSetSizeCmd(FONT_SIZE_TALL));
                commandStream.write((userName + "님").getBytes(CHARSET));
                commandStream.write(CMD_LF);
                commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                commandStream.write(CMD_BOLD_OFF);
            }
            String kioskId = jsonOrder.optString("kioskId", "");
            if (!kioskId.isEmpty() && !kioskId.equals("null")) {
                commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                commandStream.write(("키오스크: " + kioskId).getBytes(CHARSET));
                commandStream.write(CMD_LF);
            }
            commandStream.write(CMD_LF);

            commandStream.write(getSetAlignCmd(ALIGN_LEFT));

            String storeName = jsonOrder.optString("storeName", "");
            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            commandStream.write(storeName.getBytes(CHARSET));
            commandStream.write(CMD_LF);

            String orderDate = jsonOrder.optString("ordrDtm", "");
            commandStream.write(("[일시] : " + orderDate).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            commandStream.write(padRight("메뉴", 32).getBytes(CHARSET));
            commandStream.write(padLeft("수량", 10).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            JSONArray menuList = jsonOrder.optJSONArray("ordrPrdList");
            if (menuList != null && menuList.length() > 0) {
                for (int i = 0; i < menuList.length(); i++) {
                    JSONObject menuItem = menuList.getJSONObject(i);
                    String menuName = menuItem.optString("prdNm", "");
                    int menuCount = menuItem.optInt("ordrCnt", 0);
                    String countString = isCancel ? "-" + menuCount : String.valueOf(menuCount);

                    commandStream.write(getSetSizeCmd(FONT_SIZE_WIDE));
                    commandStream.write(padRight(menuName, 32).getBytes(CHARSET));
                    commandStream.write(padLeft(countString, 10).getBytes(CHARSET));
                    commandStream.write(CMD_LF);
                    commandStream.write(CMD_LF);
                    JSONArray optionList = menuItem.optJSONArray("optPrdList");
                    if (optionList != null && optionList.length() > 0) {
                        commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                        for (int j = 0; j < optionList.length(); j++) {
                            JSONObject optionItem = optionList.getJSONObject(j);
                            String optionName = optionItem.optString("optPrdNm", "");
                            int optionCount = optionItem.optInt("optPrdCnt", 0);
                            String optionCountString = isCancel ? "-" + optionCount : String.valueOf(optionCount);

                            String optionLine = " -" + optionName;
                            commandStream.write(padRight(optionLine, 32).getBytes(CHARSET));
                            commandStream.write(padLeft(optionCountString, 10).getBytes(CHARSET));
                            commandStream.write(CMD_LF);
                        }
                    }
                    commandStream.write(CMD_LF);
                }
            }

            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            String memo = jsonOrder.optString("ordrMemo", "");
            if (!memo.isEmpty()) {
                commandStream.write(CMD_LF);
                commandStream.write(getSetAlignCmd(ALIGN_CENTER));
                commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                commandStream.write(memo.getBytes(CHARSET));
                commandStream.write(CMD_LF);
                commandStream.write(getSetAlignCmd(ALIGN_LEFT));
                commandStream.write(CMD_LF);
            }

            commandStream.write(CMD_LF);
            commandStream.write(CMD_LF);
            commandStream.write(CMD_CUT_PAPER);

            byte[] commands = commandStream.toByteArray();
            for (Printer p : printerList) {
                try {
                    Log.d(TAG, "Sending order print commands to Posbank printer: " + p);
                    p.executeDirectIO(commands);
                } catch (Exception e) {
                    Log.e(TAG, "Error printing order on " + p, e);
                }
            }

        } catch (JSONException e) {
            Log.e(TAG, "JSON Parsing error in printOrderFromJson (Posbank): " + e.getMessage());
        } catch (IOException e) {
            Log.e(TAG, "IO error building print commands (Posbank): " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "General error in printOrderFromJson (Posbank): " + e.getMessage());
        }
    }

    public void printReceiptFromJson(String orderJson, boolean isCancel) {
        if (printerList == null || printerList.isEmpty()) {
            Log.e(TAG, "No Posbank printer connected for printing receipt.");
            return;
        }

        try {
            JSONObject jsonOrder = new JSONObject(orderJson);
            ByteArrayOutputStream commandStream = new ByteArrayOutputStream();
            NumberFormat formatter = new DecimalFormat("#,###");

            commandStream.write(CMD_INIT);

            commandStream.write(getSetAlignCmd(ALIGN_CENTER));

            if (isCancel) {
                commandStream.write(getSetSizeCmd(FONT_SIZE_TALL));
                commandStream.write("[취소영수증]".getBytes(CHARSET));
                commandStream.write(CMD_LF);
                commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                commandStream.write(CMD_LF);
            }

            commandStream.write(CMD_BOLD_ON);
            commandStream.write(getSetSizeCmd(FONT_SIZE_TALL));
            String displayNum = jsonOrder.optString("displayOrderNum", jsonOrder.optString("ordrSimpleId", ""));
            commandStream.write(("주문번호 : " + displayNum).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            commandStream.write(CMD_BOLD_OFF);
            commandStream.write(CMD_LF);

            commandStream.write(getSetAlignCmd(ALIGN_LEFT));

            String storeName = jsonOrder.optString("storeName", "");
            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            commandStream.write(storeName.getBytes(CHARSET));
            commandStream.write(CMD_LF);

            String orderDate = jsonOrder.optString("ordrDtm", "");
            commandStream.write(("[일시]   : " + orderDate).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(CMD_LF);

            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            commandStream.write(padRight("메뉴", 22).getBytes(CHARSET));
            commandStream.write(padLeft("수량", 10).getBytes(CHARSET));
            commandStream.write(padLeft("금액", 10).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            JSONArray menuList = jsonOrder.optJSONArray("ordrPrdList");
            if (menuList != null && menuList.length() > 0) {
                for (int i = 0; i < menuList.length(); i++) {
                    JSONObject menuItem = menuList.getJSONObject(i);
                    String menuName = menuItem.optString("prdNm", "");
                    int menuCount = menuItem.optInt("ordrCnt", 0);
                    double menuPrice = menuItem.optDouble("prdPrc", 0.0);
                    long totalItemPrice = (long) (menuPrice * menuCount);

                    String countString = isCancel ? "-" + menuCount : String.valueOf(menuCount);
                    String amountString = isCancel ? "-" + formatter.format(totalItemPrice)
                            : formatter.format(totalItemPrice);

                    commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                    commandStream.write(padRight(menuName, 22).getBytes(CHARSET));
                    commandStream.write(padLeft(countString, 10).getBytes(CHARSET));
                    commandStream.write(padLeft(amountString, 10).getBytes(CHARSET));
                    commandStream.write(CMD_LF);

                    JSONArray optionList = menuItem.optJSONArray("optPrdList");
                    if (optionList != null && optionList.length() > 0) {
                        commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                        for (int j = 0; j < optionList.length(); j++) {
                            JSONObject optionItem = optionList.getJSONObject(j);
                            String optionName = optionItem.optString("optPrdNm", "");
                            int optionCount = optionItem.optInt("optPrdCnt", 0);
                            double optionPrice = optionItem.optDouble("optPrdPrc", 0.0);
                            long totalOptionPrice = (long) (optionPrice * optionCount);

                            String optionCountString = isCancel ? "-" + optionCount : String.valueOf(optionCount);
                            String optionAmountString = isCancel ? "-" + formatter.format(totalOptionPrice)
                                    : formatter.format(totalOptionPrice);

                            String optionLine = " -" + optionName;
                            commandStream.write(padRight(optionLine, 22).getBytes(CHARSET));
                            commandStream.write(padLeft(optionCountString, 10).getBytes(CHARSET));
                            commandStream.write(padLeft(optionAmountString, 10).getBytes(CHARSET));
                            commandStream.write(CMD_LF);
                        }
                    }
                }
            }

            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            commandStream.write(getSetAlignCmd(ALIGN_RIGHT));
            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
            String exceptTaxPrice = jsonOrder.optString("exceptTaxPrice", "0");
            String taxPrice = jsonOrder.optString("taxPrice", "0");
            commandStream.write(("과세금액: " + exceptTaxPrice).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(("부 가 세: " + taxPrice).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(getSetAlignCmd(ALIGN_LEFT));
            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            commandStream.write(getSetSizeCmd(FONT_SIZE_WIDE));
            String orderPrice = jsonOrder.optString("ordrPrc", "0");
            String discountPrice = jsonOrder.optString("discPrc", "0");
            String paymentPrice = jsonOrder.optString("payPrc", "0");

            commandStream.write(padRight("주문금액 : ", 32).getBytes(CHARSET));
            commandStream.write(padLeft(orderPrice, 10).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(CMD_LF);

            commandStream.write(padRight("할인금액 : ", 32).getBytes(CHARSET));
            commandStream.write(padLeft(discountPrice.equals("0") ? "0" : "-" + discountPrice, 10).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(CMD_LF);

            commandStream.write(CMD_BOLD_ON);
            commandStream.write(padRight("결제금액 : ", 32).getBytes(CHARSET));
            commandStream.write(padLeft(paymentPrice, 10).getBytes(CHARSET));
            commandStream.write(CMD_LF);
            commandStream.write(CMD_BOLD_OFF);
            commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));

            commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
            commandStream.write(CMD_LF);

            String memo = jsonOrder.optString("ordrMemo", "");
            if (!memo.isEmpty()) {
                commandStream.write(getSetAlignCmd(ALIGN_CENTER));
                commandStream.write(getSetSizeCmd(FONT_SIZE_NORMAL));
                commandStream.write(memo.getBytes(CHARSET));
                commandStream.write(CMD_LF);
                commandStream.write(getSetAlignCmd(ALIGN_LEFT));
                commandStream.write(getSeparatorLine(42).getBytes(CHARSET));
                commandStream.write(CMD_LF);
            }

            commandStream.write(CMD_LF);
            commandStream.write(CMD_LF);
            commandStream.write(CMD_LF);
            commandStream.write(CMD_CUT_PAPER);

            byte[] commands = commandStream.toByteArray();
            for (Printer p : printerList) {
                try {
                    Log.d(TAG, "Sending receipt print commands to Posbank printer: ");
                    p.executeDirectIO(commands);
                } catch (Exception e) {
                    Log.e(TAG, "Error printing receipt on ", e);
                }
            }

        } catch (JSONException e) {
            Log.e(TAG, "JSON Parsing error in printReceiptFromJson (Posbank): " + e.getMessage());
        } catch (IOException e) {
            Log.e(TAG, "IO error building print commands (Posbank): " + e.getMessage());
        } catch (Exception e) {
            Log.e(TAG, "General error in printReceiptFromJson (Posbank): " + e.getMessage());
        }
    }

    private String getSeparatorLine(int width) {
        StringBuilder line = new StringBuilder();
        for (int i = 0; i < width; i++) {
            line.append("-");
        }
        return line.toString();
    }

    private String padRight(String text, int totalWidth) {
        try {
            int byteLength = text.getBytes(CHARSET).length;
            int paddingNeeded = totalWidth - byteLength;
            if (paddingNeeded <= 0) {
                return text;
            }
            StringBuilder paddedText = new StringBuilder(text);
            for (int i = 0; i < paddingNeeded; i++) {
                paddedText.append(" ");
            }
            return paddedText.toString();
        } catch (UnsupportedEncodingException e) {
            Log.e(TAG, "Charset error in padRight", e);
            return String.format("%-" + totalWidth + "s", text);
        }
    }

    private String padLeft(String text, int totalWidth) {
        try {
            int byteLength = text.getBytes(CHARSET).length;
            int paddingNeeded = totalWidth - byteLength;
            if (paddingNeeded <= 0) {
                return text;
            }
            StringBuilder paddedText = new StringBuilder();
            for (int i = 0; i < paddingNeeded; i++) {
                paddedText.append(" ");
            }
            paddedText.append(text);
            return paddedText.toString();
        } catch (UnsupportedEncodingException e) {
            Log.e(TAG, "Charset error in padLeft", e);
            return String.format("%" + totalWidth + "s", text);
        }
    }

    private void requestPermissionForUSB(UsbDevice device) {
        PendingIntent permissionIntent = PendingIntent.getBroadcast(
                context.getApplicationContext(), 0, new Intent(PRINTER_USB_PERMISSION),
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.S ? PendingIntent.FLAG_IMMUTABLE
                        : PendingIntent.FLAG_UPDATE_CURRENT);
        UsbManager usbManager = (UsbManager) context.getApplicationContext().getSystemService(Context.USB_SERVICE);
        usbManager.requestPermission(device, permissionIntent);
    }

    private void requestPermission(PrinterDevice device) {
        if (device.getDeviceType() == PrinterConstants.PRINTER_TYPE_USB) {
            requestPermissionForUSB((UsbDevice) device.getDeviceContext());
        }
    }

    private boolean hasPermissionForUSB(UsbDevice device) {
        UsbManager usbManager = (UsbManager) context.getApplicationContext().getSystemService(Context.USB_SERVICE);
        return usbManager.hasPermission(device);
    }

    private boolean hasPermission(PrinterDevice device) {
        boolean hasPermission = true;
        if (device.getDeviceType() == PrinterConstants.PRINTER_TYPE_USB) {
            hasPermission = hasPermissionForUSB((UsbDevice) device.getDeviceContext());
        }
        return hasPermission;
    }

    /**
     * [NEW] 라벨프린터(AutoReplyPrint 연동 장치) 여부를 확인합니다.
     * LabelPrinter.java에 정의된 4가지 VID/PID 쌍을 기반으로 합니다.
     */
    private boolean isLabelPrinter(UsbDevice device) {
        if (device == null)
            return false;

        int vid = device.getVendorId();
        int pid = device.getProductId();

        // LabelPrinter.java의 지원 목록:
        // VID:0x4B43(19267), PID:0x3538(13624)
        // VID:0x4B43(19267), PID:0x3830(14384)
        // VID:0x0FE6(4070), PID:0x811E(33054)
        // VID:0x067B(1659), PID:0x2303(8963)
        return (vid == 0x4B43 && (pid == 0x3538 || pid == 0x3830)) ||
                (vid == 0x0FE6 && pid == 0x811E) ||
                (vid == 0x067B && pid == 0x2303);
    }

    private final Handler printerMsgHandler = new Handler(new Handler.Callback() {
        @Override
        public boolean handleMessage(Message msg) {
            int msgID = msg.what;
            PrinterDevice device;
            String deviceName = msg.getData().getString(PrinterConstants.PRINTER_KEY_STR_DEVICE_NAME);

            switch (msgID) {
                case PrinterConstants.PRINTER_MSG_STATE_CHANGED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_STATE_CHANGED");
                    processPrinterMessage_StateChanged(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_CONN_SUCCEEDED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_CONN_SUCCEEDED");
                    processPrinterMessage_Connection(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_CONN_FAILED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_CONN_FAILED");
                    processPrinterMessage_Connection(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_CONN_LOST:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_CONN_LOST");
                    processPrinterMessage_Connection(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_CONN_CLOSED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_CONN_CLOSED");
                    processPrinterMessage_Connection(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_DATA_WRITE_COMPLETED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_DATA_WRITE_COMPLETED");
                    processPrinterMessage_DataWriteCompleted(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_DATA_RECEIVED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_DATA_RECEIVED");
                    processPrinterMessage_DataReceived(msg);
                    break;

                case PrinterConstants.PRINTER_MSG_DEVICE_NAME:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_DEVICE_NAME");
                    showPrinterMessage(true, deviceName + " connected");
                    break;

                case PrinterConstants.PRINTER_MSG_TOAST:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_TOAST");
                    String toastMsg = (String) msg.obj;
                    showPrinterMessage(true, "[" + deviceName + "] Message received: " + toastMsg);
                    break;

                case PrinterConstants.PRINTER_MSG_COMPLETE_PROCESS_BITMAP:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_COMPLETE_PROCESS_BITMAP");
                    showPrinterMessage(true, "[" + deviceName + "] Bitmap process completed");
                    break;

                case PrinterConstants.PRINTER_MSG_DISCOVERY_STARTED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_DISCOVERY_STARTED");
                    mProgressDialog = new ProgressDialog(context);
                    mProgressDialog.show();
                    break;

                case PrinterConstants.PRINTER_MSG_DISCOVERY_FINISHED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_DISCOVERY_FINISHED");
                    if (mProgressDialog != null && mProgressDialog.isShowing()) {
                        mProgressDialog.dismiss();
                    }
                    mProgressDialog = null;
                    printerConnect();
                    break;

                case PrinterConstants.PRINTER_MSG_USB_DEVICE_SET:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_USB_DEVICE_SET");
                    device = (PrinterDevice) msg.obj;
                    if (null != device) {
                        UsbDevice usbDevice = (UsbDevice) device.getDeviceContext();
                        // [NEW] 라벨프린터인 경우 권한 요청을 하지 않음 (LabelPrinter.java에서 별도 관리)
                        if (isLabelPrinter(usbDevice)) {
                            Log.d(TAG, "handleMessage: Ignoring label printer in device discovery - "
                                    + usbDevice.getDeviceName());
                            break;
                        }
                        if (!hasPermissionForUSB(usbDevice)) {
                            requestPermissionForUSB(usbDevice);
                        }
                    }
                    break;

                case PrinterConstants.PRINTER_MSG_USB_SERIAL_DEVICE_SET:
                    break;

                case PrinterConstants.PRINTER_MSG_SERIAL_DEVICE_SET:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_SERIAL_DEVICE_SET");
                    device = (PrinterDevice) msg.obj;
                    if (null != device) {
                    }
                    break;

                case PrinterConstants.PRINTER_MSG_BLUETOOTH_DEVICE_SET:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_BLUETOOTH_DEVICE_SET");
                    break;

                case PrinterConstants.PRINTER_MSG_NETWORK_DEVICE_SET:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_NETWORK_DEVICE_SET");
                    break;

                case PrinterConstants.PRINTER_MSG_ERROR_INVALID_ARGUMENT:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_ERROR_INVALID_ARGUMENT");
                    showPrinterMessage(true, "[" + deviceName + "] Invalid argument");
                    break;

                case PrinterConstants.PRINTER_MSG_ERROR_NV_MEMORY_CAPACITY:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_ERROR_NV_MEMORY_CAPACITY");
                    showPrinterMessage(true, "[" + deviceName + "] NV memory capacity error");
                    break;

                case PrinterConstants.PRINTER_MSG_ERROR_OUT_OF_MEMORY:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_ERROR_OUT_OF_MEMORY");
                    showPrinterMessage(true, "[" + deviceName + "] Out of memory");
                    break;

                case PrinterConstants.PRINTER_MSG_ERROR_CLASSES_NOT_FOUND:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_ERROR_CLASSES_NOT_FOUND");
                    showPrinterMessage(true, "[" + deviceName + "] Classes is not found");
                    break;

                case PrinterConstants.PRINTER_MSG_ERROR_CMD_NOT_SUPPORTED:
                    Log.i(TAG, "Printer message received...PRINTER_MSG_ERROR_CMD_NOT_SUPPORTED");
                    String strMsg = "Command is not supported";
                    showPrinterMessage(true, "[" + deviceName + "] " + strMsg);
                    break;

                default:
                    break;
            }

            return true;
        }
    });

    private void processPrinterMessage_StateChanged(Message msg) {
        int nState = msg.arg2;
        String deviceName = msg.getData().getString(PrinterConstants.PRINTER_KEY_STR_DEVICE_NAME);

        switch (nState) {
            case PrinterConstants.PRINTER_STATE_NONE:
                Log.i(TAG, "Printer message received...PRINTER_MSG_STATE_CHANGE : PRINTER_STATE_NONE");
                break;

            case PrinterConstants.PRINTER_STATE_CONNECTING:
                Log.i(TAG, "Printer message received...PRINTER_MSG_STATE_CHANGE : PRINTER_STATE_CONNECTING");
                showPrinterMessage(false, "Device [" + deviceName + "] connecting...");
                break;

            case PrinterConstants.PRINTER_STATE_CONNECTED:
                Log.i(TAG, "Printer message received...PRINTER_MSG_STATE_CHANGE : PRINTER_STATE_CONNECTED");
                showPrinterMessage(false, "Device [" + deviceName + "] connection was successful.");
                break;
        }
    }

    private void processPrinterMessage_Connection(Message msg) {
        int msgID = msg.what;
        String deviceName = msg.getData().getString(PrinterConstants.PRINTER_KEY_STR_DEVICE_NAME);
        boolean available = true;

        switch (msgID) {
            case PrinterConstants.PRINTER_MSG_CONN_SUCCEEDED:
                showPrinterMessage(false, "Device [" + deviceName + "] connection has succeeded");
                break;

            case PrinterConstants.PRINTER_MSG_CONN_FAILED:
                available = false;
                showPrinterMessage(false, "Unable to connect device [" + deviceName + "]");
                break;

            case PrinterConstants.PRINTER_MSG_CONN_LOST:
                available = false;
                showPrinterMessage(false, "Device [" + deviceName + "] connection was lost");
                break;

            case PrinterConstants.PRINTER_MSG_CONN_CLOSED:
                available = false;
                showPrinterMessage(false, "Device [" + deviceName + "] connection was closed");
                break;
        }
    }

    private void processPrinterMessage_DataWriteCompleted(Message msg) {
        int process = msg.arg1;
        String deviceName = msg.getData().getString(PrinterConstants.PRINTER_KEY_STR_DEVICE_NAME);
        switch (process) {
            case PrinterConstants.PRINTER_PROC_SET_DOUBLE_BYTE_FONT:
                Log.i(TAG,
                        "Printer message received...PRINTER_MSG_DATA_WRITE_COMPLETED: PRINTER_PROC_SET_DOUBLE_BYTE_FONT\n");
                showPrinterMessage(true, "Device [" + deviceName + "]: Complete to set double byte font.");
                break;

            case PrinterConstants.PRINTER_PROC_DEFINE_NV_IMAGE:
                Log.i(TAG,
                        "Printer message received...PRINTER_MSG_DATA_WRITE_COMPLETED: PRINTER_PROC_DEFINE_NV_IMAGE\n");
                showPrinterMessage(true, "Device [" + deviceName + "]: Complete to define NV image");
                break;

            case PrinterConstants.PRINTER_PROC_REMOVE_NV_IMAGE:
                Log.i(TAG,
                        "Printer message received...PRINTER_MSG_DATA_WRITE_COMPLETED: PRINTER_PROC_REMOVE_NV_IMAGE\n");
                showPrinterMessage(true, "Device [" + deviceName + "]: Complete to remove NV image");
                break;

            case PrinterConstants.PRINTER_PROC_UPDATE_FIRMWARE:
                Log.i(TAG,
                        "Printer message received...PRINTER_MSG_DATA_WRITE_COMPLETED: PRINTER_PROC_UPDATE_FIRMWARE\n");
                showPrinterMessage(true,
                        "Device [" + deviceName + "]: Complete to download firmware.\nPlease reboot the printer.");
                break;
        }
    }

    private void processPrinterMessage_DataReceived(Message msg) {
        int reqCmd = msg.arg1;
        int value = msg.arg2;
        Object obj = msg.obj;
        Bundle data = msg.getData();
        String deviceName = data.getString(PrinterConstants.PRINTER_KEY_STR_DEVICE_NAME);
        StringBuffer strBufferToast;
        int nComp = 0;

        switch (reqCmd) {
            case PrinterConstants.PRINTER_PROC_GET_STATUS:
                strBufferToast = new StringBuffer();
                if (value == PrinterConstants.PRINTER_STATUS_NORMAL) {
                    strBufferToast.append("[" + deviceName + "] No error");
                } else {
                    if ((value
                            & PrinterConstants.PRINTER_STATUS_COVER_OPEN) == PrinterConstants.PRINTER_STATUS_COVER_OPEN) {
                        strBufferToast.append("[" + deviceName + "] Cover is open.\n");
                    }
                    if ((value
                            & PrinterConstants.PRINTER_STATUS_PAPER_NOT_PRESENT) == PrinterConstants.PRINTER_STATUS_PAPER_NOT_PRESENT) {
                        strBufferToast.append("[" + deviceName + "] Paper end sensor: paper not present.\n");
                    }
                }
                showPrinterMessage(true, strBufferToast.toString());
                break;

            case PrinterConstants.PRINTER_PROC_GET_PRINTER_ID:
                String strID1 = (String) obj;
                String strID2 = data.getString(PrinterConstants.PRINTER_KEY_STR_PRINTER_ID);
                strBufferToast = new StringBuffer();
                strBufferToast.append("Device [" + deviceName + "] PrinterID: " + strID1 + " [" + strID2 + "]\n");
                showPrinterMessage(true, strBufferToast.toString());
                break;

            case PrinterConstants.PRINTER_PROC_AUTO_STATUS_BACK:
                Log.i(TAG, "Printer message received...PRINTER_MSG_DATA_RECEIVED: PRINTER_PROC_AUTO_STATUS_BACK: "
                        + String.valueOf(value) + "\n");
                strBufferToast = new StringBuffer();
                strBufferToast.append(
                        "Device [" + deviceName + "] AutoStatusBack received...Code: " + String.valueOf(value) + "\n");
                nComp = value & PrinterConstants.PRINTER_AUTO_STATUS_COVER_OPEN;
                if (nComp == PrinterConstants.PRINTER_AUTO_STATUS_COVER_OPEN) {
                    strBufferToast.append("Cover is open.\n");
                }
                nComp = value & PrinterConstants.PRINTER_AUTO_STATUS_NO_PAPER;
                if (nComp == PrinterConstants.PRINTER_AUTO_STATUS_NO_PAPER) {
                    strBufferToast.append("Paper end sensor: paper not present.\n");
                }
                nComp = value & PrinterConstants.PRINTER_AUTO_STATUS_PAPER_FED;
                if (nComp == PrinterConstants.PRINTER_AUTO_STATUS_PAPER_FED) {
                    strBufferToast.append("Paper is being fed by the paper feed button.\n");
                }
                showPrinterMessage(true, strBufferToast.toString());
                break;

            case PrinterConstants.PRINTER_PROC_GET_CODE_PAGE:
                Log.i(TAG, "Printer message received...PRINTER_MSG_DATA_RECEIVED: PRINTER_PROC_GET_CODE_PAGE\n");
                String strFont = (String) obj;
                strBufferToast = new StringBuffer();
                strBufferToast.append("Device [" + deviceName + "] Code Page: " + strFont + "\n");
                showPrinterMessage(false, strBufferToast.toString());
                break;

            case PrinterConstants.PRINTER_PROC_DEFINE_NV_IMAGE:
                Log.i(TAG, "Printer message received...PRINTER_MSG_DATA_RECEIVED: PRINTER_PROC_DEFINE_NV_IMAGE\n");
                break;

            case PrinterConstants.PRINTER_PROC_GET_NV_IMAGE_KEY_CODES:
                Log.i(TAG,
                        "Printer message received...PRINTER_MSG_DATA_RECEIVED: PRINTER_PROC_GET_NV_IMAGE_KEY_CODES\n");
                int[] keyCodes = data.getIntArray(PrinterConstants.PRINTER_KEY_STR_NV_IMAGE_KEY_CODES);
                Intent intent = new Intent();
                intent.setAction(ACTION_GET_DEFINEED_NV_IMAGE_KEY_CODES);
                intent.putExtra(EXTRA_NAME_NV_KEY_CODES, keyCodes);
                context.sendBroadcast(intent);
                break;

            case PrinterConstants.PRINTER_PROC_EXECUTE_DIRECT_IO:
                Log.i(TAG, "Printer message received...PRINTER_MSG_DATA_RECEIVED: PRINTER_PROC_EXECUTE_DIRECT_IO\n");
                byte[] receiveData = data.getByteArray(PrinterConstants.PRINTER_KEY_STR_DIRECT_IO);
                strBufferToast = new StringBuffer();
                strBufferToast.append("Device [" + deviceName + "] ");
                strBufferToast.append(StrUtil.toHexString(receiveData));
                strBufferToast.append("\n");
                showPrinterMessage(true, strBufferToast.toString());
                break;
        }
    }

    public void showPrinterMessage(boolean showToast, String message) {
        // Toast.makeText(context.getApplicationContext(), message,
        // Toast.LENGTH_LONG).show();
    }
}
