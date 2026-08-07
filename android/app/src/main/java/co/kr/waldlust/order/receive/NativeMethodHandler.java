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
import android.hardware.camera2.CameraManager;
import android.os.Build;
import android.util.Base64;
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
    private final ExecutorService labelPrintExecutor = Executors.newSingleThreadExecutor();
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
                    final int finalAutoReplyMode = autoReplyMode != null ? autoReplyMode : 1;
                    final boolean finalUseFeedToTear = useFeedToTear != null ? useFeedToTear : true;
                    final boolean finalUseBackToPrint = useBackToPrint != null ? useBackToPrint : true;
                    final boolean finalUseCalibrate = useCalibrate != null ? useCalibrate : false;
                    final String finalOrderNo = orderNo != null ? orderNo : "-";
                    final int finalLabelIndex = labelIndex != null ? labelIndex : 1;
                    final int finalTotalLabels = totalLabels != null ? totalLabels : 1;

                    labelPrintExecutor.submit(() -> {
                        // 벤더 라우팅: 연결된 USB VID 로 매 인쇄 재평가 (attach/detach stale 방지).
                        // 두 벤더 동시 연결 시 BIXOLON 우선. Caysn 전용 knob(autoReplyMode 등)은
                        // BIXOLON 경로에서 무의미하므로 전달하지 않는다.
                        //
                        // 반환은 LabelPrinter.RESULT_* 3분류(0=성공 / 1=재시도가능 /
                        // 2=발사후 무응답). Dart 는 1 일 때만 재시도한다 — 2 에서 재시도하면
                        // 이미 펌웨어에 들어간 페이지가 한 장 더 인쇄된다.
                        int printResult;
                        if (co.kr.waldlust.order.receive.util.print.BixolonLabelDriver
                                .isBixolonAttached(activity)) {
                            // BIXOLON 드라이버는 아직 bool 만 반환 — 실패는 재시도 가능으로 본다
                            // (기존 동작 유지).
                            printResult = co.kr.waldlust.order.receive.util.print.BixolonLabelDriver
                                    .printBitmap(bitmap, finalOrderNo, finalLabelIndex, finalTotalLabels)
                                    ? co.kr.waldlust.order.receive.util.print.LabelPrinter.RESULT_SUCCESS
                                    : co.kr.waldlust.order.receive.util.print.LabelPrinter.RESULT_RETRYABLE;
                        } else {
                            printResult = co.kr.waldlust.order.receive.util.print.LabelPrinter.printBitmap(
                                    bitmap,
                                    finalAutoReplyMode,
                                    finalUseFeedToTear,
                                    finalUseBackToPrint,
                                    finalUseCalibrate,
                                    finalOrderNo,
                                    finalLabelIndex,
                                    finalTotalLabels);
                        }
                        new android.os.Handler(android.os.Looper.getMainLooper()).post(() -> result.success(printResult));
                    });
                } else {
                    result.error("INVALID_ARGUMENT", "Image bytes are null or empty", null);
                }
                break;

            // ACK timeout 진단 스냅샷 조회. printLabel 의 int 반환 계약을 건드리지 않기
            // 위해 별도 메서드로 분리했다 — Map 으로 바꾸면 invokeMethod<int> 가 타입
            // 캐스트로 실패하고, 그 실패는 PlatformException catch 에 안 잡혀 중복 인쇄
            // 불변식을 지키는 3분류 경로를 흔들 수 있다.
            case "getLastLabelAckDiagnostic":
                result.success(co.kr.waldlust.order.receive.util.print.LabelPrinter
                        .consumeLastAckDiagnostic());
                break;

            case "reconnectExternalPrinter": {
                try {
                    if (MainActivity.receiptPrinter != null) {
                        MainActivity.receiptPrinter.close();
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
                boolean ok = false;
                try {
                    if (MainActivity.receiptPrinter != null
                            && MainActivity.receiptPrinter.isConnected()) {
                        ok = MainActivity.receiptPrinter.verifyConnection();
                    }
                } catch (Exception e) {
                    Log.e(TAG, "isExternalPrinterConnected error", e);
                    ok = false;
                }
                result.success(ok);
                break;
            }

            case "hasBuiltinPrinter": {
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
                final int maxTries = 30;
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
                String orderJson = call.argument("orderJson");
                String type = call.argument("type");
                Boolean isCancel = call.argument("isCancel");
                Boolean useBuiltinPrint = call.argument("useBuiltinPrint");
                if (isCancel == null) {
                    isCancel = false;
                }

                String logoBase64 = call.argument("logoBase64");
                Bitmap logoBitmap = null;
                if (logoBase64 != null && !logoBase64.isEmpty()) {
                    try {
                        byte[] logoBytes = Base64.decode(logoBase64, Base64.DEFAULT);
                        logoBitmap = BitmapFactory.decodeByteArray(logoBytes, 0, logoBytes.length);
                    } catch (Exception e) {
                        Log.w(TAG, "Receipt logo decode failed, printing without logo: " + e.getMessage());
                    }
                }

                if (orderJson != null && !orderJson.isEmpty()) {
                    Log.d(TAG, "Received print request. Type: " + type + ", isCancel: "
                            + isCancel + ", isSunmi: " + activity.isSunmiDevice());

                    if (activity.isSunmiDevice() && Boolean.TRUE.equals(useBuiltinPrint)) {
                        if ("order".equals(type)) {
                            SunmiPrintHelper.getInstance().printOrderFromJson(orderJson, isCancel, logoBitmap);
                        } else if (type != null && type.equals("receipt")) {
                            SunmiPrintHelper.getInstance().printReceiptFromJson(orderJson, isCancel, logoBitmap);
                        } else {
                            Log.w(TAG, "Print type is null or unknown: " + type + ". Defaulting to receipt.");
                            SunmiPrintHelper.getInstance().printReceiptFromJson(orderJson, isCancel, logoBitmap);
                        }
                    }
                    result.success(true);
                } else {
                    Log.e(TAG, "Order JSON is null or empty for printing");
                    result.error("INVALID_ARGUMENT", "Order JSON is null or empty", null);
                }
                break;

            case "printDeviceCall": {
                String callHeadline = call.argument("headline");
                String callDeviceIdLabel = call.argument("deviceIdLabel");
                String callDeviceId = call.argument("deviceId");
                String callDateLabel = call.argument("dateLabel");
                String callDateValue = call.argument("dateValue");
                if (activity.isSunmiDevice()) {
                    SunmiPrintHelper.getInstance().printDeviceCall(
                            callHeadline, callDeviceIdLabel, callDeviceId,
                            callDateLabel, callDateValue);
                }
                result.success(true);
                break;
            }

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
                        // 홈 화면을 강제 뒤배치하지 않기 위해 플래그를 0으로 설정
                        activityManager.moveTaskToFront(activity.getTaskId(), 0);
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
                String slug = call.argument("slug");

                Log.d("isKdsMode", "onMethodCall: isKdsMode" + isKdsMode);

                activity.saveStoreIdToNative(storeId, isKdsMode, mainURL, slug);
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

            case "getTimezoneId":
                result.success(java.util.TimeZone.getDefault().getID());
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

            case "hasBuiltinScanner": {
                // 바코드 스캔 버튼이 실제로 동작하는 단말에서만 true 를 반환한다.
                // (1) startQRScan 이 시도하는 intent action 이 resolve 되는지(=스캐너 앱 설치),
                // (2) 실제 카메라가 존재하는지. 둘 다 충족해야 한다.
                // D2s 처럼 Sunmi 스캐너 앱은 깔려 있어도 카메라가 없는 단말은 버튼을
                // 눌러봤자 "no camera detect" 토스트만 뜨므로 카메라 존재까지 확인한다.
                boolean available = false;
                try {
                    Context ctx = activity.getApplicationContext();
                    PackageManager pm = ctx.getPackageManager();
                    boolean scannerAppResolves =
                            pm.resolveActivity(new Intent("com.sunmi.scanner.qrscanner"), 0) != null
                            || pm.resolveActivity(new Intent("com.summi.scan"), 0) != null
                            || pm.resolveActivity(new Intent("com.sunmi.scan"), 0) != null;

                    // 카메라 존재는 두 신호의 OR 로 판정한다. T2mini 의 카메라는 HAL1(legacy)
                    // 기반 SunmiUsbCamera 라 camera2 의 getCameraIdList() 에 잡히지 않는데,
                    // 카메라 자체는 멀쩡히 있고 Sunmi 스캐너도 정상 동작한다. 시스템 feature
                    // 선언은 HAL 세대와 무관하므로 이쪽을 우선 신호로 쓰고, camera2 로만
                    // 잡히는 단말을 위해 getCameraIdList() 를 fallback 으로 남긴다.
                    // 카메라가 진짜 없는 D2s 는 두 신호 모두 false 라 계속 숨겨진다.
                    boolean hasCameraFeature = pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY);

                    boolean hasCamera2 = false;
                    CameraManager cm = (CameraManager) ctx.getSystemService(Context.CAMERA_SERVICE);
                    if (cm != null) {
                        hasCamera2 = cm.getCameraIdList().length > 0;
                    }

                    available = scannerAppResolves && (hasCameraFeature || hasCamera2);
                    Log.i(TAG, "hasBuiltinScanner: scannerAppResolves=" + scannerAppResolves
                            + ", cameraFeature=" + hasCameraFeature
                            + ", camera2=" + hasCamera2
                            + " -> " + available);
                } catch (Exception e) {
                    // 조용히 false 를 반환하면 다음 단말에서 원인 추적이 불가능해진다.
                    Log.w(TAG, "hasBuiltinScanner 판정 실패 - 미지원으로 간주", e);
                    available = false;
                }
                result.success(available);
                break;
            }

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

            case "getDualMonitorCapability": {
                String slug = call.argument("slug");
                result.success(activity.getDualMonitorCapability(slug));
                break;
            }

            case "setDualMonitorMode": {
                String mode = call.argument("mode");
                activity.setDualMonitorMode(mode != null ? mode : "none");
                result.success(null);
                break;
            }

            case "clearDualMonitor": {
                activity.clearDualMonitor();
                result.success(null);
                break;
            }

            case "getLogDirPath":
                // Absolute path of the directory holding appfit_YYYY-MM-DD.txt logs.
                // Dart reads these files directly to build the log archive.
                result.success(activity.getLogDirPath());
                break;

            case "getDeviceSerial": {
                // Sunmi: device serial via the bound printer service (e.g. D3 MINI
                // "DE33256H10784"). Non-Sunmi (e.g. IM H092W "H092W24A1G00862") and
                // any Sunmi fallback: SystemProperties/Build serial via getDeviceSerial().
                if (!activity.isSunmiDevice()) {
                    result.success(activity.getDeviceSerial());
                    break;
                }
                final SunmiPrintHelper snHelper = SunmiPrintHelper.getInstance();
                if (snHelper.isReady()) {
                    String sn = snHelper.getPrinterSerialNo();
                    result.success((sn != null && !sn.isEmpty())
                            ? sn : activity.getDeviceSerial());
                    break;
                }
                final java.util.concurrent.atomic.AtomicBoolean snReplied =
                        new java.util.concurrent.atomic.AtomicBoolean(false);
                final android.os.Handler snHandler =
                        new android.os.Handler(android.os.Looper.getMainLooper());
                final int[] snTries = {0};
                final int snMaxTries = 30;
                final long snIntervalMs = 50;
                Runnable snProbe = new Runnable() {
                    @Override
                    public void run() {
                        if (snReplied.get()) return;
                        if (snHelper.isReady()) {
                            if (snReplied.compareAndSet(false, true)) {
                                String sn = snHelper.getPrinterSerialNo();
                                result.success((sn != null && !sn.isEmpty())
                                        ? sn : activity.getDeviceSerial());
                            }
                            return;
                        }
                        snTries[0]++;
                        if (snTries[0] >= snMaxTries) {
                            if (snReplied.compareAndSet(false, true)) {
                                Log.w(TAG, "getDeviceSerial: Sunmi service bind timeout");
                                result.success(activity.getDeviceSerial());
                            }
                            return;
                        }
                        snHandler.postDelayed(this, snIntervalMs);
                    }
                };
                snHandler.postDelayed(snProbe, snIntervalMs);
                break;
            }

            default:
                result.notImplemented();
                break;
        }
    }
}
