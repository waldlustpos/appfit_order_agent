package co.kr.waldlust.order.receive;

import android.Manifest;
import android.app.ActivityManager;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.os.Build;
import android.util.Log;
import android.net.Uri;
import android.provider.Settings;
import android.view.Surface;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import co.kr.waldlust.order.receive.overlay.OverlayHelper;
import co.kr.waldlust.order.receive.util.print.SunmiPrintHelper;
import co.kr.waldlust.order.receive.util.print.UsbReceiptPrinter;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class NativeMethodHandler implements MethodChannel.MethodCallHandler {
    private static final String TAG = "NativeMethodHandler";
    private final MainActivity activity;
    private final ExecutorService fileIoExecutor = Executors.newSingleThreadExecutor();
    // 라벨 프린터는 USB 단일 자원 → 단일 스레드 executor 로 직렬화하여 재출력 연타 / 동시 호출의
    // 공백지/지연 이슈를 차단한다.
    private final ExecutorService labelPrintExecutor = Executors.newSingleThreadExecutor();
    // 외부 영수증 프린터(범용 USB ESC/POS). 라벨과는 별개의 USB 디바이스이지만, 동일 단말에서
    // 연속 출력 시 bulkTransfer 동시 호출 충돌을 막기 위해 단일 스레드로 직렬화한다.
    private final ExecutorService receiptPrintExecutor = Executors.newSingleThreadExecutor();

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
                Integer autoReplyMode = call.argument("autoReplyMode");
                Boolean useFeedToTear = call.argument("useFeedToTear");
                Boolean useBackToPrint = call.argument("useBackToPrint");
                Boolean useCalibrate = call.argument("useCalibrate");
                String orderNo = call.argument("orderNo");
                Integer labelIndex = call.argument("labelIndex");
                Integer totalLabels = call.argument("totalLabels");

                if (imageBytes != null && imageBytes.length > 0) {
                    final Bitmap bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.length);
                    // autoReplyMode 기본 1: SDK PrintedEvent ACK 활성. preference_service.dart 와 일치.
                    final int finalAutoReplyMode = autoReplyMode != null ? autoReplyMode : 1;
                    final boolean finalUseFeedToTear = useFeedToTear != null ? useFeedToTear : true;
                    final boolean finalUseBackToPrint = useBackToPrint != null ? useBackToPrint : true;
                    final boolean finalUseCalibrate = useCalibrate != null ? useCalibrate : false;
                    final String finalOrderNo = orderNo != null ? orderNo : "-";
                    final int finalLabelIndex = labelIndex != null ? labelIndex : 1;
                    final int finalTotalLabels = totalLabels != null ? totalLabels : 1;

                    labelPrintExecutor.submit(() -> {
                        boolean printResult = co.kr.waldlust.order.receive.util.print.LabelPrinter.printBitmap(
                                bitmap,
                                finalAutoReplyMode,
                                finalUseFeedToTear,
                                finalUseBackToPrint,
                                finalUseCalibrate,
                                finalOrderNo,
                                finalLabelIndex,
                                finalTotalLabels);
                        new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> result.success(printResult));
                    });
                } else {
                    result.error("INVALID_ARGUMENT", "Image bytes are null or empty", null);
                }
                break;

            case "reconnectExternalPrinter": {
                // 외부 영수증 프린터(범용 USB ESC/POS) 재탐색 트리거.
                // - 앱 첫 실행 시 미연결이었거나, USB 권한 거부 후 다시 켠 케이스,
                //   또는 사용자가 설정 화면에서 외부 프린터 토글을 ON 한 직후 호출되어
                //   discovery + permission 흐름을 다시 돌린다.
                // - idempotent. open 상태든 닫힌 상태든 안전하게 재시도.
                try {
                    if (MainActivity.receiptPrinter != null) {
                        MainActivity.receiptPrinter.discover();
                        result.success(true);
                    } else {
                        Log.e(TAG, "reconnectExternalPrinter: receiptPrinter is not initialized");
                        result.success(false);
                    }
                } catch (Exception e) {
                    Log.e(TAG, "reconnectExternalPrinter error", e);
                    result.success(false);
                }
                break;
            }

            case "isExternalPrinterConnected": {
                // 외부 영수증 프린터 연결 상태 조회. UsbReceiptPrinter 의 bulkOut endpoint 확보 여부 기반.
                try {
                    boolean connected = MainActivity.receiptPrinter != null
                            && MainActivity.receiptPrinter.isConnected();
                    result.success(connected);
                } catch (Exception e) {
                    Log.e(TAG, "isExternalPrinterConnected error", e);
                    result.success(false);
                }
                break;
            }

            case "hasBuiltinPrinter": {
                // Sunmi 내장 프린터 하드웨어 존재 여부.
                // - 비-Sunmi 단말은 즉시 false.
                // - Sunmi 단말: initSunmiPrinterService 가 비동기 bindService 라 isReady() 가
                //   false 일 수 있음 → main thread 의 Handler.postDelayed 로 50ms 간격 폴링
                //   (최대 1.5초). isReady() true 되면 hasInnerPrinter() 반환, timeout 시 false.
                if (!activity.isSunmiDevice()) {
                    result.success(false);
                    break;
                }
                final SunmiPrintHelper helper = SunmiPrintHelper.getInstance();
                if (helper.isReady()) {
                    result.success(helper.hasInnerPrinter());
                    break;
                }
                final java.util.concurrent.atomic.AtomicBoolean replied =
                        new java.util.concurrent.atomic.AtomicBoolean(false);
                final android.os.Handler probeHandler =
                        new android.os.Handler(android.os.Looper.getMainLooper());
                final int[] tries = {0};
                final int maxTries = 30; // 50ms × 30 = 1.5s
                final long intervalMs = 50;
                Runnable probe = new Runnable() {
                    @Override
                    public void run() {
                        if (replied.get()) return;
                        if (helper.isReady()) {
                            if (replied.compareAndSet(false, true)) {
                                result.success(helper.hasInnerPrinter());
                            }
                            return;
                        }
                        tries[0]++;
                        if (tries[0] >= maxTries) {
                            if (replied.compareAndSet(false, true)) {
                                Log.w(TAG, "hasBuiltinPrinter: Sunmi service bind timeout");
                                result.success(false);
                            }
                            return;
                        }
                        probeHandler.postDelayed(this, intervalMs);
                    }
                };
                probeHandler.postDelayed(probe, intervalMs);
                break;
            }

            case "encodeCp949Batch": {
                // Dart ReceiptEscPosBuilder.toBytesCp949 가 한 영수증의 모든 텍스트 segments 를
                // 한 번에 위탁. Java String.getBytes("EUC-KR") 는 CP949 호환 출력으로
                // 기존 Posbank/PrintUtil 경로와 동일한 byte 결과를 보장.
                // (Dart win32 의존을 안드로이드에서 트리거하지 않기 위한 우회.)
                java.util.List<String> texts = call.argument("texts");
                java.util.List<byte[]> out = new java.util.ArrayList<>();
                if (texts != null) {
                    for (String t : texts) {
                        if (t == null) { out.add(new byte[0]); continue; }
                        try {
                            out.add(t.getBytes("EUC-KR"));
                        } catch (java.io.UnsupportedEncodingException e) {
                            Log.e(TAG, "encodeCp949Batch fallback to default charset for: " + t, e);
                            out.add(t.getBytes());
                        }
                    }
                }
                result.success(out);
                break;
            }

            case "printReceiptBytes": {
                // Dart ReceiptEscPosBuilder.toBytesCp949() 결과(byte[])를 받아 외부 프린터 USB bulkTransfer 로 송출.
                // Windows 경로와 동일한 byte 스트림을 사용 — 양 플랫폼 hex dump 가 일치한다.
                // 결과는 PlatformException.code (BUSY / NO_DEVICE / TRANSPORT_ERROR)
                // 로 전달돼 Dart PrinterJobQueue 가 backoff 재시도를 결정한다.
                byte[] data = call.argument("bytes");
                String jobName = call.argument("jobName");
                final String finalJobName = jobName != null ? jobName : "RECEIPT";
                if (data == null || data.length == 0) {
                    result.error("INVALID_ARGUMENT", "bytes is null or empty", null);
                    break;
                }
                final byte[] finalData = data;
                receiptPrintExecutor.submit(() -> {
                    UsbReceiptPrinter.WriteResult wr = UsbReceiptPrinter.WriteResult.TRANSPORT_ERROR;
                    String errorMsg = null;
                    try {
                        if (MainActivity.receiptPrinter != null) {
                            wr = MainActivity.receiptPrinter.writeBytes(finalData, finalJobName);
                        } else {
                            wr = UsbReceiptPrinter.WriteResult.NO_DEVICE;
                            errorMsg = "receiptPrinter not initialized";
                            Log.e(TAG, "printReceiptBytes: receiptPrinter is not initialized");
                        }
                    } catch (Exception e) {
                        wr = UsbReceiptPrinter.WriteResult.TRANSPORT_ERROR;
                        errorMsg = e.getMessage();
                        Log.e(TAG, "printReceiptBytes error", e);
                    }
                    final UsbReceiptPrinter.WriteResult fWr = wr;
                    final String fErrMsg = errorMsg;
                    new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> {
                        switch (fWr) {
                            case SUCCESS:
                                result.success(true);
                                break;
                            case BUSY:
                                result.error("BUSY",
                                        fErrMsg != null ? fErrMsg : "claim/open failed",
                                        null);
                                break;
                            case NO_DEVICE:
                                result.error("NO_DEVICE",
                                        fErrMsg != null ? fErrMsg : "printer not attached",
                                        null);
                                break;
                            case TRANSPORT_ERROR:
                            default:
                                result.error("TRANSPORT_ERROR",
                                        fErrMsg != null ? fErrMsg : "bulkTransfer failed",
                                        null);
                                break;
                        }
                    });
                });
                break;
            }

            case "printOrder":
                // Sunmi 내장 영수증 프린터 전용 채널. 외부 영수증 프린터는 'printReceiptBytes' 로 분리.
                String orderJson = call.argument("orderJson");
                String type = call.argument("type");
                Boolean isCancel = call.argument("isCancel");
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
                    final String msgCopy = message;
                    fileIoExecutor.execute(() -> activity.appendLogToFile(msgCopy));
                    result.success(true);
                } else {
                    result.error("INVALID_ARGUMENT", "Log message is null", null);
                }
                break;

            case "logBatchToFile":
                java.util.List<String> messages = call.argument("messages");
                if (messages != null) {
                    final java.util.List<String> msgsCopy = new java.util.ArrayList<>(messages);
                    fileIoExecutor.execute(() -> activity.appendLogsToFile(msgsCopy));
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

            case "restartApp": {
                Intent restartIntent = activity.getPackageManager()
                        .getLaunchIntentForPackage(activity.getPackageName());
                restartIntent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_NEW_TASK);
                PendingIntent pendingIntent = PendingIntent.getActivity(
                        activity, 0, restartIntent,
                        PendingIntent.FLAG_CANCEL_CURRENT | PendingIntent.FLAG_IMMUTABLE);
                AlarmManager alarmManager = (AlarmManager) activity.getSystemService(Context.ALARM_SERVICE);
                alarmManager.set(AlarmManager.RTC, System.currentTimeMillis() + 100, pendingIntent);
                result.success(null);
                android.os.Process.killProcess(android.os.Process.myPid());
                break;
            }

            case "checkWriteSettings":
                result.success(Settings.System.canWrite(activity));
                break;

            case "requestWriteSettings": {
                Intent writeSettingsIntent = new Intent(
                        Settings.ACTION_MANAGE_WRITE_SETTINGS,
                        Uri.parse("package:" + activity.getPackageName()));
                writeSettingsIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                try {
                    activity.startActivity(writeSettingsIntent);
                } catch (ActivityNotFoundException e) {
                    Log.e(TAG, "WRITE_SETTINGS 설정 화면을 열 수 없습니다: " + e.getMessage());
                }
                result.success(null);
                break;
            }

            case "setSystemRotation": {
                Boolean reversed = call.argument("reversed");
                boolean isReversed = reversed != null && reversed;
                try {
                    Settings.System.putInt(activity.getContentResolver(),
                            Settings.System.ACCELEROMETER_ROTATION, 0);
                    Settings.System.putInt(activity.getContentResolver(),
                            Settings.System.USER_ROTATION,
                            isReversed ? Surface.ROTATION_180 : Surface.ROTATION_0);
                    Log.d(TAG, "시스템 회전 설정 완료: " + (isReversed ? "180도" : "정상"));
                    result.success(true);
                } catch (Exception e) {
                    Log.e(TAG, "시스템 회전 설정 실패: " + e.getMessage());
                    result.error("ROTATION_ERROR", e.getMessage(), null);
                }
                break;
            }

            default:
                result.notImplemented();
                break;
        }
    }
}
