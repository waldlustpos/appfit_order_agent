package co.kr.waldlust.order.receive;

import android.Manifest;
import android.app.ActivityManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.util.Log;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import java.util.Map;

import co.kr.waldlust.order.receive.overlay.OverlayHelper;
import co.kr.waldlust.order.receive.util.print.PrintUtil;
import co.kr.waldlust.order.receive.util.print.SunmiPrintHelper;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class NativeMethodHandler implements MethodChannel.MethodCallHandler {
    private static final String TAG = "NativeMethodHandler";
    private final MainActivity activity;

    public NativeMethodHandler(MainActivity activity) {
        this.activity = activity;
    }

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        switch (call.method) {
            case "readLegacyOrderNumberFile":
                String lastOrderNumber = activity.readLegacyOrderNumberFile();
                result.success(lastOrderNumber);
                break;

            case "showSystemUI":
                activity.showSystemUI();
                result.success(true);
                break;

            case "hideSystemUI":
                activity.hideSystemUI();
                result.success(true);
                break;

            case "setAdjustResize":
                activity.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
                Log.d(TAG, "setAdjustResize");
                result.success(null);
                break;

            case "setAdjustPan":
                activity.getWindow().setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_PAN);
                Log.d(TAG, "setAdjustPan");
                result.success(null);
                break;

            case "setAutoStartup": {
                Boolean enable = call.argument("enable");
                boolean success = activity.setAutoStartup(enable != null ? enable : false);
                result.success(success);
                break;
            }

            case "printLabel":
                byte[] imageBytes = call.argument("imageBytes");

                if (imageBytes != null && imageBytes.length > 0) {
                    Log.d(TAG, "Received printLabel request. Bytes: " + imageBytes.length);
                    Bitmap bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.length);
                    co.kr.waldlust.order.receive.util.print.LabelPrinter.printBitmap(bitmap);
                    result.success(true);
                } else {
                    result.error("INVALID_ARGUMENT", "Image bytes are null or empty", null);
                }
                break;

            case "printOrder":
                String orderJson = call.argument("orderJson");
                String type = call.argument("type");
                Boolean isCancel = call.argument("isCancel");
                Boolean useExternalPrint = call.argument("useExternalPrint");
                Boolean useBuiltinPrint = call.argument("useBuiltinPrint");
                if (isCancel == null) {
                    isCancel = false;
                }

                if (orderJson != null && !orderJson.isEmpty()) {
                    Log.d(TAG, "Received print request. Type: " + type + ", isCancel: "
                            + isCancel + ", isSunmi: " + activity.isSunmiDevice());

                    if (activity.isSunmiDevice() && Boolean.TRUE.equals(useBuiltinPrint)) {
                        if ("order".equals(type)) {
                            SunmiPrintHelper.getInstance().printOrderFromJson(orderJson, isCancel);
                        } else if (type != null && type.equals("receipt")) {
                            SunmiPrintHelper.getInstance().printReceiptFromJson(orderJson, isCancel);
                        } else {
                            Log.w(TAG, "Print type is null or unknown: " + type + ". Defaulting to receipt.");
                            SunmiPrintHelper.getInstance().printReceiptFromJson(orderJson, isCancel);
                        }
                    }

                    if (Boolean.TRUE.equals(useExternalPrint)) {
                        if (MainActivity.printrUtil != null) {
                            if ("order".equals(type)) {
                                MainActivity.printrUtil.printOrderFromJson(orderJson, isCancel);
                            } else {
                                MainActivity.printrUtil.printReceiptFromJson(orderJson, isCancel);
                            }
                        } else {
                            Log.e(TAG, "PrintUtil is not initialized!");
                            if (!Boolean.TRUE.equals(useBuiltinPrint)) {
                                result.error("PRINTER_ERROR", "PrintUtil not initialized", null);
                                return;
                            }
                        }
                    }
                    result.success(true);
                } else {
                    Log.e(TAG, "Order JSON is null or empty for printing");
                    result.error("INVALID_ARGUMENT", "Order JSON is null or empty", null);
                }
                break;

            case "moveToBackground":
                try {
                    activity.moveTaskToBack(true);
                    result.success(true);
                } catch (Exception e) {
                    result.error("MOVE_BACKGROUND_ERROR", e.getMessage(), null);
                }
                break;

            case "bringToFront":
                try {
                    ActivityManager activityManager = (ActivityManager) activity
                            .getSystemService(Context.ACTIVITY_SERVICE);
                    if (activityManager != null) {
                        activityManager.moveTaskToFront(activity.getTaskId(), ActivityManager.MOVE_TASK_WITH_HOME);
                    }

                    Intent intent = new Intent(activity, MainActivity.class);
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                            | Intent.FLAG_ACTIVITY_SINGLE_TOP);
                    activity.startActivity(intent);
                    result.success(true);
                } catch (Exception e) {
                    result.error("BRING_FRONT_ERROR", e.getMessage(), null);
                }
                break;

            case "saveStoreIdToNative": {
                Log.d(TAG, "call saveStoreIdToNative");
                String storeId = call.argument("storeId");
                boolean isKdsMode = call.argument("isKdsMode");
                String mainURL = call.argument("mainURL");

                Log.d("isKdsMode", "onMethodCall: isKdsMode" + isKdsMode);

                activity.saveStoreIdToNative(storeId, isKdsMode, mainURL);
                result.success(null);
                break;
            }

            case "logToFile":
                String message = call.argument("message");
                if (message != null) {
                    activity.appendLogToFile(message);
                    result.success(true);
                } else {
                    result.error("INVALID_ARGUMENT", "Log message is null", null);
                }
                break;

            case "logBatchToFile":
                java.util.List<String> messages = call.argument("messages");
                if (messages != null) {
                    activity.appendLogsToFile(messages);
                    result.success(true);
                } else {
                    result.error("INVALID_ARGUMENT", "Log messages list is null", null);
                }
                break;

            case "checkAndRequestFilePermissions":
                if (activity.checkPermissions()) {
                    result.success(true);
                } else {
                    result.success(activity.checkAndRequestPermissions());
                }
                break;

            case "openAppSettings":
                activity.openAppSettings();
                result.success(null);
                break;

            case "getAndroidSdkVersion":
                result.success(Build.VERSION.SDK_INT);
                break;

            case "checkIgnoringBatteryOptimizations":
                result.success(activity.isIgnoringBatteryOptimizations());
                break;

            case "requestIgnoreBatteryOptimizations":
                activity.requestIgnoreBatteryOptimizations();
                result.success(null);
                break;

            case "checkNotificationPermission":
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    result.success(activity.checkSelfPermission(
                            Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED);
                } else {
                    result.success(true);
                }
                break;

            case "requestNotificationPermission":
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    activity.requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS },
                            MainActivity.REQUEST_CODE_POST_NOTIFICATION);
                    result.success(null);
                } else {
                    result.success(true);
                }
                break;

            case "startQRScan":
                try {
                    Intent intent = new Intent("com.summi.scan");
                    if (activity.hasScanner(activity.getApplicationContext())) {
                        intent.setAction("com.sunmi.scanner.qrscanner");
                    }
                    activity.startActivityForResult(intent, MainActivity.START_SCAN);
                    result.success(null);
                } catch (ActivityNotFoundException e) {
                    result.error("SCANNER_NOT_FOUND", "QR 바코드를 지원하지 않는 단말입니다.", null);
                }
                break;

            case "checkOverlayPermission":
                result.success(OverlayHelper.canDrawOverlays(activity));
                break;

            case "requestOverlayPermission":
                OverlayHelper.requestOverlayPermission(activity);
                result.success(true);
                break;

            case "showOverlay":
                OverlayHelper.showBubble(activity);
                result.success(null);
                break;

            case "hideOverlay":
                OverlayHelper.hideBubble(activity);
                result.success(null);
                break;

            case "notifyNewOrder":
                OverlayHelper.notifyNewOrder(activity);
                result.success(null);
                break;

            case "getConnectedUsbDevices":
                result.success(activity.getConnectedUsbDevices());
                break;

            default:
                result.notImplemented();
                break;
        }
    }
}
