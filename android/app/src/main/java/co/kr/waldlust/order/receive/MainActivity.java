package co.kr.waldlust.order.receive;

import android.Manifest;
import android.app.ActivityManager;
import android.annotation.SuppressLint;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.Rect;
import android.graphics.RectF;
import android.net.ConnectivityManager;
import android.net.NetworkInfo;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.PowerManager;
import android.provider.Settings;
import android.text.format.DateFormat;
import android.util.Log;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.android.volley.AuthFailureError;
import com.android.volley.DefaultRetryPolicy;
import com.android.volley.Request;
import com.android.volley.toolbox.StringRequest;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.io.StringWriter;
import java.nio.charset.StandardCharsets;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import co.kr.waldlust.order.receive.util.print.UsbReceiptPrinter;
import co.kr.waldlust.order.receive.util.print.SunmiPrintHelper;
import co.kr.waldlust.order.receive.overlay.OverlayHelper;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import android.app.Presentation;
import android.media.MediaPlayer;
import android.view.Display;
import android.view.MotionEvent;
import android.widget.MediaController;
import android.widget.VideoView;
import android.hardware.display.DisplayManager;

import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "co.kr.waldlust.order.receive.appfit_order_agent";
    private static final String PREFERENCES_NAME = "KOKONUT_AGENT";
    private static final String LEGACY_PREFERENCES_NAME = "KOKONUT_AGENT";
    private static final String LEGACY_PACKAGE_NAME = "co.kr.waldlust.order.receive";
    public static final int START_SCAN = 300;

    // Legacy keys
    private static final String KEY_OVERLAY_X = "KOKONUT_KEY_OVERLAY_X";
    private static final String KEY_OVERLAY_Y = "KOKONUT_KEY_OVERLAY_Y";
    private static final String KEY_MID = "KOKONUT_M_ID";
    private static final String KEY_PWD = "KOKONUT_M_PWD";
    private static final String KEY_STORE_ID = "KOKONUT_STORE_ID";
    private static final String KEY_STORE_NAME = "KOKONUT_STORE_NAME";
    private static final String KEY_REWARD_TYPE = "KOKONUT_STORE_TYPE";
    private static final String KEY_WAIT_MIN = "KEY_WAIT_MIN";
    private static final String KEY_AUTO_RECEIPT = "KEY_AUTO_RECEIPT";
    private static final String KEY_EXTERNAL_PRINT = "KEY_EXTERNAL_PRINT";
    private static final String KEY_AUTO_LAUNCH = "KEY_AUTO_LAUNCH";
    private static final String KEY_VOLUME = "KEY_VOLUME";
    private static final String KEY_ORDER_ON = "KEY_ORDER_ON";
    private static final String KEY_VERSION_FIRST = "KEY_VERSION_FIRST";
    private static final String KEY_SOUND = "KEY_SOUND";
    private static final String KEY_SOUND_NUM = "KEY_SOUND_NUM";
    private static final String KEY_IS_SAVE_ID = "IS_SAVE_ID";
    private static final String KEY_IS_AUTO_LOGIN = "IS_AUTO_LOGIN";
    private static final String KEY_IS_NEW_ORDER = "IS_NEW_ORDER";
    private static final String KEY_IS_AUTO_LAUNCH = "IS_AUTO_LAUNCH";
    private static final String KEY_SHOW_KIOSK_ORDER = "IS_SHOW_KIOSK_ORDER";
    private static final String KEY_KIOSK_PRINT_AND_SOUND = "IS_KIOSK_PRINT_AND_SOUND";
    private static final String KEY_USE_PRINT = "KEY_USE_PRINT";
    private static final String KEY_MAIN_URL = "KEY_MAIN_URL";
    private static final String KEY_IS_KDS_MODE = "IS_KDS_MODE";
    // Dual monitor (D3 MINI front display) - must match Dart PreferenceService constants.
    private static final String KEY_BRAND_SLUG = "KEY_BRAND_SLUG";
    private static final String KEY_DUAL_MONITOR_MODE = "KEY_DUAL_MONITOR_MODE";
    // Brand content resources are named dm_<slug>(.mp4|.png). The dm_ prefix lets
    // res/raw/keep.xml keep them (tools:keep="@raw/dm_*,@drawable/dm_*") against R8
    // resource shrinking, since getIdentifier() lookups are invisible to the shrinker.
    private static final String DUAL_MONITOR_RES_PREFIX = "dm_";
    // MHST(매머드커피) 브랜드 고객용 LCD(T2mini 등) 대기화면 식별자. KEY_BRAND_SLUG 는
    // Dart BrandRegistry 의 assetFolder 를 그대로 받으므로 MHST 매장은 "mammoth".
    // 로그아웃 시 clearDualMonitor 가 이 slug 를 비워 LCD 도 함께 꺼진다.
    private static final String MHST_BRAND_SLUG = "mammoth";
    // Sunmi 고객용 LCD(T2mini 등) 표준 해상도. 로고를 이 비율 캔버스에 가운데 contain 으로
    // 합성해 보내면 실제 LCD 픽셀수가 달라도 펌웨어가 비례 스케일하여 중앙 정렬이 유지된다.
    private static final int LCD_WIDTH = 128;
    private static final int LCD_HEIGHT = 40;
    public static UsbReceiptPrinter receiptPrinter;

    public static String versionName = "/api/v2";

    private static View decorView;
    private static int uiOption;
    private static int showOption;
    public static final int STORAGE_PERMISSION_REQUEST_CODE = 101;
    public static final int REQUEST_CODE_POST_NOTIFICATION = 102;
    private static final int REQUEST_CODE_IGNORE_BATTERY_OPTIMIZATIONS = 103;
    private static final int REQUEST_CODE_LEGACY_DATA_ACCESS = 104;
    private static final int REQUEST_CODE_ALL_FILES_ACCESS = 105;

    public interface ResultInterface {
        void callbackResult(String result);
    }

    private DualMonitorPresentation dualMonitorPresentation;
    private int DISPLAY_LENGTH = 0;
    private final boolean isD3MINI = Build.MODEL.equals("D3 MINI");

    private BroadcastReceiver usbPermissionReceiver;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        setNativeCrashHandler();
        super.onCreate(savedInstanceState);

        // Register USB permission / detach receiver for the receipt printer.
        usbPermissionReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String action = intent.getAction();
                if (UsbReceiptPrinter.ACTION_USB_PERMISSION.equals(action)) {
                    synchronized (this) {
                        android.hardware.usb.UsbDevice device = intent
                                .getParcelableExtra(android.hardware.usb.UsbManager.EXTRA_DEVICE);
                        if (intent.getBooleanExtra(android.hardware.usb.UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                            if (device != null) {
                                Log.i("MainActivity", "USB permission granted for device: " + device.getDeviceName());
                                appendLogToFile("USB permission granted for device: " + device.getDeviceName());
                                if (receiptPrinter != null) {
                                    receiptPrinter.onPermissionGranted(device);
                                }
                            }
                        } else {
                            Log.w("MainActivity", "USB permission denied for device: "
                                    + (device != null ? device.getDeviceName() : "unknown"));
                            appendLogToFile("USB permission denied for device: "
                                    + (device != null ? device.getDeviceName() : "unknown"));
                        }
                    }
                } else if (android.hardware.usb.UsbManager.ACTION_USB_DEVICE_DETACHED.equals(action)) {
                    android.hardware.usb.UsbDevice device = intent
                            .getParcelableExtra(android.hardware.usb.UsbManager.EXTRA_DEVICE);
                    if (device != null && receiptPrinter != null) {
                        receiptPrinter.onUsbDetached(device);
                    }
                }
            }
        };

        IntentFilter usbFilter = new IntentFilter();
        usbFilter.addAction(UsbReceiptPrinter.ACTION_USB_PERMISSION);
        usbFilter.addAction(android.hardware.usb.UsbManager.ACTION_USB_DEVICE_DETACHED);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            // App internal broadcast only — restrict external exposure with RECEIVER_NOT_EXPORTED.
            registerReceiver(usbPermissionReceiver, usbFilter, Context.RECEIVER_NOT_EXPORTED);
        } else {
            registerReceiver(usbPermissionReceiver, usbFilter);
        }

        // Initialize printers
        initPrinters();

        // Dual monitor logic for D3 MINI
        showDualMonitor();

        // Start Foreground Service after checking notification permission
        checkAndStartForegroundService();

        // Delete old log files on startup
        deleteOldLogFiles();

        // Check and request All Files Access permission for log writing
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !hasAllFilesAccess()) {
            requestAllFilesAccess();
        }

        // Set system UI flags directly
        decorView = getWindow().getDecorView();
        uiOption = decorView.getSystemUiVisibility();

        // For API 19+ (KitKat and higher)
        decorView.setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                        | View.SYSTEM_UI_FLAG_FULLSCREEN
                        | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);

        // Keep screen on and fullscreen
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN);

        receiptPrinter = new UsbReceiptPrinter(getApplicationContext());
        receiptPrinter.discover();
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus) {
            // Reapply system UI flags when window gets focus
            decorView.setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
    }

    @Override
    @SuppressWarnings("unchecked")
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode == START_SCAN && data != null) {
            Bundle bundle = data.getExtras();
            if (bundle != null) {
                ArrayList<HashMap<String, String>> result = (ArrayList<HashMap<String, String>>) bundle
                        .getSerializable("data");
                if (result != null && !result.isEmpty()) {
                    HashMap<String, String> map = result.get(0);
                    String value = map.get("VALUE");
                    if (value != null) {
                        // Flutter로 스캔 결과 전달
                        new MethodChannel(getFlutterEngine().getDartExecutor().getBinaryMessenger(), CHANNEL)
                                .invokeMethod("onQRScanResult", value);
                    }
                }
            }
        }
        super.onActivityResult(requestCode, resultCode, data);
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        Log.d("MainActivity", "onNewIntent called");

        // 새로운 인텐트(오버레이 클릭 등) 수신 시 앱을 즉시 전면으로 가져옴
        try {
            // 1. Activity를 최상단으로
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED |
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD |
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON);

            // 2. Task를 전면으로 이동 (홈 화면을 강제 뒤배치하지 않기 위해 플래그를 0으로 설정)
            ActivityManager activityManager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            if (activityManager != null) {
                activityManager.moveTaskToFront(getTaskId(), 0);
                Log.d("MainActivity", "moveTaskToFront success in onNewIntent");
            }
        } catch (Exception e) {
            Log.e("MainActivity", "Error in onNewIntent: " + e.getMessage());
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        MethodChannel channel = new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL);
        channel.setMethodCallHandler(new NativeMethodHandler(this));
    }

    public boolean hasScanner(Context ctx) {
        PackageInfo info = getPackageInfo(ctx, "com.sunmi.scanner");
        return info != null && compareVer(info.versionName, "4.4.4", true, 3);
    }

    public boolean compareVer(String nVer, String oVer, boolean isEq, int bit) {
        if (nVer.isEmpty() || oVer.isEmpty())
            return false;
        String[] nArr = nVer.split("[.]");
        String[] oArr = oVer.split("[.]");
        if (nArr.length < bit || oArr.length < bit)
            return false;
        boolean vup = false;
        for (int i = 0; i < bit; i++) {
            int n = Integer.parseInt(nArr[i]);
            int o = Integer.parseInt(oArr[i]);
            if (n >= o) {
                if (n > o) {
                    vup = true;
                    break;
                } else if (isEq && i == (bit - 1)) {
                    vup = true;
                    break;
                }
            } else {
                break;
            }
        }
        return vup;
    }

    public static PackageInfo getPackageInfo(Context context, String pkg) {
        PackageInfo packageInfo;
        try {
            packageInfo = context.getPackageManager().getPackageInfo(pkg, 0);
        } catch (PackageManager.NameNotFoundException e) {
            packageInfo = null;
            e.printStackTrace();
        }
        return packageInfo;
    }

    public void showSystemUI() {
        runOnUiThread(() -> {
            decorView.setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN);

            // Auto-hide after 3 seconds
            decorView.postDelayed(this::hideSystemUI, 3000);
        });
    }

    public void hideSystemUI() {
        runOnUiThread(() -> {
            decorView.setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        });
    }

    @Override
    protected void onPause() {
        super.onPause();
        Log.d("MainActivity", "onPause called");

        // Dismiss (not just cleanup) so the front display window does not linger
        // showing the last content (e.g. a white image background) while backgrounded.
        if (dualMonitorPresentation != null) {
            dualMonitorPresentation.dismiss();
            dualMonitorPresentation = null;
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.d("MainActivity", "onResume called");

        if (dualMonitorPresentation == null || !dualMonitorPresentation.isShowing()) {
            showDualMonitor();
        }

        // 고객용 LCD(T2mini) 브랜드 대기화면 재적용 (서비스 준비 후).
        refreshBrandLcd();

        if (decorView != null) {
            decorView.setSystemUiVisibility(
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
    }

    @Override
    protected void onDestroy() {
        Log.d("MainActivity", "onDestroy called");

        // Tear down the front display so no content (e.g. white image) lingers on exit.
        if (dualMonitorPresentation != null) {
            dualMonitorPresentation.dismiss();
            dualMonitorPresentation = null;
        }

        // Stop Foreground Service
        stopOrderAgentService();

        // SUNMI printer cleanup
        if (isSunmiDevice()) {
            SunmiPrintHelper.getInstance().deInitSunmiPrinterService(this);
        }

        // Unregister USB permission receiver
        if (usbPermissionReceiver != null) {
            unregisterReceiver(usbPermissionReceiver);
        }

        // USB printer resource release
        if (receiptPrinter != null) {
            receiptPrinter.close();
        }

        super.onDestroy(); // Must be called last
    }

    private void initPrinters() {
        Log.d("MainActivity", "Initializing printers...");
        if (isSunmiDevice()) {
            SunmiPrintHelper.getInstance().initSunmiPrinterService(this);
        }
        co.kr.waldlust.order.receive.util.print.LabelPrinter.init(this);
    }

    public boolean checkPermissions() {
        Log.d("checkPermissions", "checkPermissions Build.VERSION.SDK_INT: " + Build.VERSION.SDK_INT);
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            boolean audioPermission = ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_MEDIA_AUDIO) == PackageManager.PERMISSION_GRANTED;
            boolean videoPermission = ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_MEDIA_VIDEO) == PackageManager.PERMISSION_GRANTED;
            boolean imagePermission = ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_MEDIA_IMAGES) == PackageManager.PERMISSION_GRANTED;
            return audioPermission && videoPermission && imagePermission;
        } else {
            boolean readPermission = ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
            boolean writePermission = ContextCompat.checkSelfPermission(this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
            return readPermission && writePermission;
        }
    }

    public boolean checkAndRequestPermissions() {
        if (checkPermissions()) {
            return true;
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }

        List<String> permissionsNeeded = new ArrayList<>();

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_MEDIA_AUDIO) != PackageManager.PERMISSION_GRANTED)
                permissionsNeeded.add(Manifest.permission.READ_MEDIA_AUDIO);
            if (ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_MEDIA_VIDEO) != PackageManager.PERMISSION_GRANTED)
                permissionsNeeded.add(Manifest.permission.READ_MEDIA_VIDEO);
            if (ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_MEDIA_IMAGES) != PackageManager.PERMISSION_GRANTED)
                permissionsNeeded.add(Manifest.permission.READ_MEDIA_IMAGES);
        } else {
            if (ContextCompat.checkSelfPermission(this,
                    Manifest.permission.READ_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED)
                permissionsNeeded.add(Manifest.permission.READ_EXTERNAL_STORAGE);
            if (ContextCompat.checkSelfPermission(this,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED)
                permissionsNeeded.add(Manifest.permission.WRITE_EXTERNAL_STORAGE);
        }

        if (!permissionsNeeded.isEmpty()) {
            ActivityCompat.requestPermissions(this, permissionsNeeded.toArray(new String[0]),
                    STORAGE_PERMISSION_REQUEST_CODE);
            return false;
        }
        return true;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions,
            @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == STORAGE_PERMISSION_REQUEST_CODE) {
            boolean granted = true;
            for (int grantResult : grantResults) {
                if (grantResult != PackageManager.PERMISSION_GRANTED) {
                    granted = false;
                    break;
                }
            }
            Log.d("Permissions", "Storage permission request result, granted: " + granted);
        } else if (requestCode == REQUEST_CODE_POST_NOTIFICATION) {
            if (grantResults.length > 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d("Permissions", "Notification permission granted. Starting service.");
                startOrderAgentService();
            } else {
                Log.w("Permissions", "Notification permission denied. Foreground service cannot show notification.");
            }
        }
    }

    public static String getDate(long time) {
        Calendar cal = Calendar.getInstance(Locale.KOREA);
        cal.setTimeInMillis(time);
        String date = DateFormat.format("yyyy-MM-dd", cal).toString();
        return date;
    }

    private boolean appendLogToFileDirectIO(String text, String fileName) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && !Environment.isExternalStorageManager()) {
                Log.w("FileWriter", "DirectIO: MANAGE_EXTERNAL_STORAGE permission not granted on Android 11+");
                return false;
            }

            File documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
            if (documentsDir == null) {
                Log.w("FileWriter", "DirectIO: DIRECTORY_DOCUMENTS is null");
                return false;
            }

            File logDir = new File(documentsDir, "appfit");
            if (!logDir.exists()) {
                Log.d("FileWriter", "DirectIO: Attempting to create directory: " + logDir.getAbsolutePath());
                if (!logDir.mkdirs()) {
                    Log.w("FileWriter", "DirectIO: Failed to create directory (mkdirs returned false): " + logDir.getAbsolutePath());
                    return false;
                }
                Log.d("FileWriter", "DirectIO: Successfully created directory: " + logDir.getAbsolutePath());
            }

            File logFile = new File(logDir, fileName);
            try (FileOutputStream fos = new FileOutputStream(logFile, true);
                    OutputStreamWriter writer = new OutputStreamWriter(fos, StandardCharsets.UTF_8)) {
                writer.append(text);
                writer.flush();
            }
            return true;
        } catch (Exception e) {
            Log.w("FileWriter", "DirectIO failed with exception: " + e.getMessage(), e);
            return false;
        }
    }

    public boolean hasAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager();
        }
        return true;
    }

    public void requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivityForResult(intent, REQUEST_CODE_ALL_FILES_ACCESS);
            } catch (Exception e) {
                Log.e("FileWriter", "Failed to open All Files Access settings", e);
                try {
                    Intent intent = new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);
                    startActivityForResult(intent, REQUEST_CODE_ALL_FILES_ACCESS);
                } catch (Exception e2) {
                    Log.e("FileWriter", "Failed to open general All Files Access settings", e2);
                }
            }
        }
    }

    private void writeLogToAppFolder(String text, String fileName) {
        try {
            File logDir = getExternalFilesDir("logs");
            if (logDir == null)
                return;
            if (!logDir.exists() && !logDir.mkdirs())
                return;
            File logFile = new File(logDir, fileName);
            try (FileOutputStream fos = new FileOutputStream(logFile, true);
                    OutputStreamWriter writer = new OutputStreamWriter(fos, StandardCharsets.UTF_8)) {
                writer.append(text);
                writer.flush();
            }
        } catch (Exception e) {
            Log.e("FileWriter", "App folder logging failed", e);
        }
    }

    public void openAppSettings() {
        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
        Uri uri = Uri.fromParts("package", getPackageName(), null);
        intent.setData(uri);
        startActivity(intent);
    }

    public boolean isSunmiDevice() {
        return Build.MANUFACTURER.startsWith("SUNMI");
    }

    public List<Map<String, Object>> getConnectedUsbDevices() {
        List<Map<String, Object>> deviceList = new ArrayList<>();
        UsbManager usbManager = (UsbManager) getSystemService(Context.USB_SERVICE);
        if (usbManager != null) {
            HashMap<String, UsbDevice> devices = usbManager.getDeviceList();
            for (UsbDevice device : devices.values()) {
                Map<String, Object> deviceMap = new HashMap<>();
                deviceMap.put("deviceName", device.getDeviceName());
                deviceMap.put("vendorId", device.getVendorId());
                deviceMap.put("productId", device.getProductId());
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    deviceMap.put("manufacturerName", device.getManufacturerName());
                    deviceMap.put("productName", device.getProductName());
                }
                deviceList.add(deviceMap);
            }
        }
        return deviceList;
    }

    private void showDualMonitor() {
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        String storeId = prefs.getString(KEY_STORE_ID, "");
        String slug = prefs.getString(KEY_BRAND_SLUG, "");
        String mode = prefs.getString(KEY_DUAL_MONITOR_MODE, "");
        DisplayManager cDisplayManager = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        Display[] cDisplays = cDisplayManager.getDisplays();
        DISPLAY_LENGTH = cDisplays.length;
        Log.e("cDisplays.length", String.valueOf(cDisplays.length));
        if (cDisplays.length > 1) {
            dualMonitorPresentation = new DualMonitorPresentation(this, cDisplays[1], storeId, slug, mode);
            Log.d("MainActivity", "showDualMonitor()");
            dualMonitorPresentation.show();
        } else {
            Log.d("MainActivity", "no DualMonitor");
        }
    }

    private class DualMonitorPresentation extends Presentation {
        private VideoView videoView;
        private ImageView imageView;
        private String videoUrl;
        private String packageName;
        private String storeId;
        private String slug;
        private String mode;
        private MediaController mediaController;
        private boolean isDestroyed = false;

        public DualMonitorPresentation(Context outerContext, Display display, String id, String slug, String mode) {
            super(outerContext, display);
            this.packageName = outerContext.getPackageName();
            this.storeId = id;
            this.slug = slug;
            this.mode = mode;
        }

        @SuppressLint("MissingInflatedId")
        @Override
        protected void onCreate(Bundle savedInstanceState) {
            super.onCreate(savedInstanceState);
            setContentView(R.layout.dual_monitor);

            videoView = findViewById(R.id.videoView1);
            imageView = findViewById(R.id.imageView1);

            // Data-driven content resolution: slug -> res/raw/<slug>.mp4 (video) or
            // res/drawable/<slug>.png (image). Brand prefix->slug mapping lives in Dart
            // (BrandRegistry) and is passed in via SharedPreferences.
            int rawId = (slug == null || slug.isEmpty())
                    ? 0
                    : getContext().getResources().getIdentifier(
                            DUAL_MONITOR_RES_PREFIX + slug, "raw", packageName);
            int drawableId = (slug == null || slug.isEmpty())
                    ? 0
                    : getContext().getResources().getIdentifier(
                            DUAL_MONITOR_RES_PREFIX + slug, "drawable", packageName);
            boolean hasVideo = rawId != 0;
            boolean hasImage = drawableId != 0;
            Log.d("DualMonitor", "present slug=" + slug + " mode=" + mode
                    + " rawId=" + rawId + " drawableId=" + drawableId);

            // effectiveMode: explicit operator choice wins when its content exists;
            // otherwise auto-default with video priority (video > image > none).
            // No content / "none" -> black screen (default layout background). True
            // panel power-off is NOT attempted: a screenBrightness override on this
            // hardware also dims the MAIN display, so we only show black.
            if ("none".equals(mode)) {
                // explicit hide: keep black screen
            } else if ("image".equals(mode) && hasImage) {
                setImage(drawableId);
            } else if ("video".equals(mode) && hasVideo) {
                setVideo(rawId);
            } else if (hasVideo) {
                setVideo(rawId);
            } else if (hasImage) {
                setImage(drawableId);
            }
        }

        private void setVideo(int videoResource) {
            videoUrl = "android.resource://" + packageName + "/" + videoResource;
            Uri videoUri = Uri.parse(videoUrl);

            videoView.setVisibility(View.VISIBLE);
            videoView.setVideoURI(videoUri);

            videoView.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
                @Override
                public void onPrepared(MediaPlayer mp) {
                    mp.setVolume(0f, 0f);
                    mp.setVideoScalingMode(MediaPlayer.VIDEO_SCALING_MODE_SCALE_TO_FIT);
                }
            });
            videoView.start();

            videoView.setOnTouchListener(new View.OnTouchListener() {
                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    return true;
                }
            });

            videoView.setOnCompletionListener(new MediaPlayer.OnCompletionListener() {
                @Override
                public void onCompletion(MediaPlayer mp) {
                    if (!isDestroyed) {
                        videoView.start();
                    }
                }
            });

            videoView.setOnErrorListener(new MediaPlayer.OnErrorListener() {
                @Override
                public boolean onError(MediaPlayer mp, int what, int extra) {
                    Log.e("DualMonitor", "Video playback error: " + what + ", " + extra);
                    return true;
                }
            });
        }

        private void setImage(int imageResource) {
            // Image content shows on a WHITE background (logos/graphics are designed
            // for light backgrounds). Only the no-content state stays black.
            imageView.setBackgroundColor(android.graphics.Color.WHITE);
            imageView.setImageResource(imageResource);
            imageView.setVisibility(View.VISIBLE);
            imageView.setOnTouchListener(new View.OnTouchListener() {
                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    return true;
                }
            });
        }

        @Override
        protected void onStop() {
            super.onStop();
            cleanup();
        }

        @Override
        public void dismiss() {
            cleanup();
            super.dismiss();
        }

        private void cleanup() {
            isDestroyed = true;
            if (videoView != null) {
                videoView.stopPlayback();
                videoView.setOnPreparedListener(null);
                videoView.setOnCompletionListener(null);
                videoView.setOnErrorListener(null);
                videoView.setOnTouchListener(null);
                videoView = null;
            }
            if (imageView != null) {
                imageView.setImageDrawable(null);
                imageView.setOnTouchListener(null);
                imageView = null;
            }
            if (mediaController != null) {
                mediaController = null;
            }
        }
    }

    private void checkAndStartForegroundService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                Log.w("MainActivity",
                        "Notification permission not granted. Requesting permission before starting service.");
                requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS },
                        REQUEST_CODE_POST_NOTIFICATION);
            } else {
                Log.d("MainActivity", "Notification permission already granted. Starting service.");
                startOrderAgentService();
            }
        } else {
            Log.d("MainActivity", "Below Tiramisu, starting service directly.");
            startOrderAgentService();
        }
    }

    private void startOrderAgentService() {
        Intent serviceIntent = new Intent(this, OrderAgentService.class);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent);
        } else {
            startService(serviceIntent);
        }
        Log.i("MainActivity", "OrderAgentService started");
    }

    private void stopOrderAgentService() {
        Intent serviceIntent = new Intent(this, OrderAgentService.class);
        stopService(serviceIntent);
        Log.i("MainActivity", "OrderAgentService stopped");
    }

    public boolean isIgnoringBatteryOptimizations() {
        PowerManager pm = (PowerManager) getSystemService(Context.POWER_SERVICE);
        if (pm != null) {
            return pm.isIgnoringBatteryOptimizations(getPackageName());
        }
        return false;
    }

    @SuppressLint("BatteryLife")
    public void requestIgnoreBatteryOptimizations() {
        if (!isIgnoringBatteryOptimizations()) {
            try {
                Intent intent = new Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivityForResult(intent, REQUEST_CODE_IGNORE_BATTERY_OPTIMIZATIONS);
            } catch (Exception e) {
                Log.e("MainActivity", "Failed to request ignore battery optimizations", e);
                try {
                    Intent intent = new Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS);
                    startActivity(intent);
                } catch (Exception e2) {
                    Log.e("MainActivity", "Failed to open battery optimization settings", e2);
                }
            }
        }
    }

    private void deleteOldLogFiles() {
        File logDir = new File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS),
                "appfit");
        if (!logDir.exists() || !logDir.isDirectory()) {
            Log.d("MainActivity", "Log directory does not exist: " + logDir.getAbsolutePath());
            return;
        }

        File[] logFiles = logDir.listFiles();
        if (logFiles == null) {
            Log.w("MainActivity", "Could not list files in log directory: " + logDir.getAbsolutePath());
            return;
        }

        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.MONTH, -6);
        long cutoffMillis = cal.getTimeInMillis();
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());

        Log.d("MainActivity", "Checking for log files older than 6 months in: " + logDir.getAbsolutePath());

        for (File file : logFiles) {
            if (file.isFile() && file.getName().endsWith(".txt")) {
                String fileName = file.getName();
                try {
                    if (!fileName.startsWith("appfit_") || fileName.length() < 18) continue;
                    String dateString = fileName.substring(7, 17);
                    Date fileDate = dateFormat.parse(dateString);

                    if (fileDate != null && fileDate.getTime() < cutoffMillis) {
                        Log.i("MainActivity", "Deleting old log file: " + fileName);
                        if (file.delete()) {
                            Log.d("MainActivity", "Successfully deleted: " + fileName);
                            appendLogToFile("[SYSTEM] 오래된 로그 파일 삭제 완료: " + fileName);
                        } else {
                            Log.w("MainActivity", "Failed to delete: " + fileName);
                            appendLogToFile("[SYSTEM] 오래된 로그 파일 삭제 실패: " + fileName);
                        }
                    }
                } catch (ParseException e) {
                    Log.w("MainActivity", "Could not parse date from log file name: " + fileName, e);
                } catch (IndexOutOfBoundsException e) {
                    Log.w("MainActivity", "Skipping file with unexpected name format: " + fileName);
                }
            }
        }
        Log.d("MainActivity", "Finished checking old log files.");
    }

    public void saveStoreIdToNative(String storeId, boolean isKdsMode, String mainURL, String slug) {
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();
        editor.putString(KEY_STORE_ID, storeId);
        editor.putBoolean(KEY_IS_KDS_MODE, isKdsMode);
        editor.putString(KEY_MAIN_URL, mainURL);
        editor.putString(KEY_BRAND_SLUG, slug != null ? slug : "");
        editor.apply();

        runOnUiThread(() -> {
            if (dualMonitorPresentation != null) {
                dualMonitorPresentation.dismiss();
                dualMonitorPresentation = null;
            }
            showDualMonitor();
            refreshBrandLcd();
        });
    }

    // Reports dual monitor capability for the given brand slug: whether a secondary
    // display is attached and whether video/image content resources exist.
    public Map<String, Object> getDualMonitorCapability(String slug) {
        Map<String, Object> result = new HashMap<>();
        DisplayManager dm = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        boolean hasSecondaryDisplay = dm != null && dm.getDisplays().length > 1;
        String pkg = getPackageName();
        int rawId = (slug == null || slug.isEmpty())
                ? 0 : getResources().getIdentifier(DUAL_MONITOR_RES_PREFIX + slug, "raw", pkg);
        int drawableId = (slug == null || slug.isEmpty())
                ? 0 : getResources().getIdentifier(DUAL_MONITOR_RES_PREFIX + slug, "drawable", pkg);
        result.put("hasSecondaryDisplay", hasSecondaryDisplay);
        result.put("hasVideo", rawId != 0);
        result.put("hasImage", drawableId != 0);
        Log.d("DualMonitor", "capability slug=" + slug + " secondary=" + hasSecondaryDisplay
                + " video=" + (rawId != 0) + " image=" + (drawableId != 0));
        return result;
    }

    // Blacks out the front display (e.g. on logout): clears the brand slug so no
    // content resolves, then re-renders to a black screen.
    public void clearDualMonitor() {
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        prefs.edit().putString(KEY_BRAND_SLUG, "").apply();
        runOnUiThread(() -> {
            if (dualMonitorPresentation != null) {
                dualMonitorPresentation.dismiss();
                dualMonitorPresentation = null;
            }
            showDualMonitor();
            // slug 를 비웠으므로 LCD 대기화면도 함께 꺼진다.
            refreshBrandLcd();
        });
    }

    // 고객용 LCD(T2mini 등 보조 디스플레이) 브랜드 대기화면 갱신. 저장된 brand slug 로
    // 브랜드를 판별해 MHST 면 "MAMMOTH"/"COFFEE" 두 줄(가운데 정렬)을, 그 외 매장이거나
    // 로그아웃(slug 비움) 상태면 화면을 지운다. 듀얼모니터 콘텐츠와 동일하게 onResume·
    // 로그인 저장·로그아웃 시점에 호출된다.
    private void refreshBrandLcd() {
        refreshBrandLcd(0);
    }

    // Sunmi 서비스 바인딩은 비동기라 onResume 직후엔 아직 준비 전일 수 있다. 준비될 때까지
    // 짧게 재시도(최대 ~3s)해 대기화면이 누락되지 않게 한다.
    private void refreshBrandLcd(int attempt) {
        if (!isSunmiDevice()) {
            return;
        }
        SunmiPrintHelper helper = SunmiPrintHelper.getInstance();
        if (!helper.isReady() && attempt < 30) {
            new android.os.Handler(android.os.Looper.getMainLooper())
                    .postDelayed(() -> refreshBrandLcd(attempt + 1), 100);
            return;
        }
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        String slug = prefs.getString(KEY_BRAND_SLUG, "");
        if (MHST_BRAND_SLUG.equals(slug)) {
            Bitmap lcdLogo = buildLcdLogoBitmap(R.drawable.mmth_print_logo);
            if (lcdLogo != null) {
                helper.sendBitmapToLcd(lcdLogo);
            } else {
                // 비트맵 디코드 실패 시 텍스트로 폴백.
                helper.sendTextToLcd("MAMMOTH", "COFFEE");
            }
        } else {
            helper.clearLcd();
        }
    }

    // drawable 로고를 고객 LCD 비율(LCD_WIDTH x LCD_HEIGHT) 흰 배경 캔버스에 비율 유지로
    // contain + 가운데 합성한다. 원본 BMP 는 가로로 긴 워드마크(341x24)라 그대로 보내면
    // 좌측/상단 치우침·왜곡이 생기므로 중앙 배치 비트맵을 만들어 sendLCDBitmap 으로 넘긴다.
    private Bitmap buildLcdLogoBitmap(int resId) {
        try {
            BitmapFactory.Options opts = new BitmapFactory.Options();
            opts.inScaled = false; // density 자동 확대 방지 (원본 픽셀 유지)
            Bitmap src = BitmapFactory.decodeResource(getResources(), resId, opts);
            if (src == null) {
                Log.w("MainActivity", "buildLcdLogoBitmap: decode failed res=" + resId);
                return null;
            }

            Bitmap canvasBmp = Bitmap.createBitmap(LCD_WIDTH, LCD_HEIGHT, Bitmap.Config.ARGB_8888);
            Canvas canvas = new Canvas(canvasBmp);
            canvas.drawColor(Color.WHITE); // 투명 영역 -> 흰색(미점등)

            float scale = Math.min(
                    (float) LCD_WIDTH / src.getWidth(),
                    (float) LCD_HEIGHT / src.getHeight());
            float drawW = src.getWidth() * scale;
            float drawH = src.getHeight() * scale;
            float left = (LCD_WIDTH - drawW) / 2f;
            float top = (LCD_HEIGHT - drawH) / 2f;

            Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG | Paint.FILTER_BITMAP_FLAG);
            Rect srcRect = new Rect(0, 0, src.getWidth(), src.getHeight());
            RectF dstRect = new RectF(left, top, left + drawW, top + drawH);
            canvas.drawBitmap(src, srcRect, dstRect, paint);
            src.recycle();
            return canvasBmp;
        } catch (Exception e) {
            Log.e("MainActivity", "buildLcdLogoBitmap error", e);
            return null;
        }
    }

    // Persists the operator's dual monitor content choice (video/image/none) and
    // re-renders the presentation immediately.
    public void setDualMonitorMode(String mode) {
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        prefs.edit().putString(KEY_DUAL_MONITOR_MODE, mode).apply();
        runOnUiThread(() -> {
            if (dualMonitorPresentation != null) {
                dualMonitorPresentation.dismiss();
                dualMonitorPresentation = null;
            }
            showDualMonitor();
        });
    }

    public void appendLogToFile(String text) {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault());
        String timestampedText = sdf.format(new Date()) + " " + text + "\n";
        String date = getDate(System.currentTimeMillis());
        String fileName = "appfit_" + date + ".txt";

        if (!appendLogToFileDirectIO(timestampedText, fileName)) {
            writeLogToAppFolder(timestampedText, fileName);
        }
    }

    public void appendLogsToFile(List<String> logs) {
        if (logs == null || logs.isEmpty())
            return;

        StringBuilder sb = new StringBuilder();
        for (String log : logs) {
            sb.append(log).append("\n");
        }

        String combinedText = sb.toString();
        String date = getDate(System.currentTimeMillis());
        String fileName = "appfit_" + date + ".txt";

        if (!appendLogToFileDirectIO(combinedText, fileName)) {
            writeLogToAppFolder(combinedText, fileName);
        }
    }

    private void setNativeCrashHandler() {
        final Thread.UncaughtExceptionHandler originalHandler = Thread.getDefaultUncaughtExceptionHandler();

        Thread.setDefaultUncaughtExceptionHandler(new Thread.UncaughtExceptionHandler() {
            @Override
            public void uncaughtException(@NonNull Thread thread, @NonNull Throwable throwable) {
                try {
                    StringWriter sw = new StringWriter();
                    PrintWriter pw = new PrintWriter(sw);
                    throwable.printStackTrace(pw);
                    String stackTrace = sw.toString();

                    String crashLog = "\n\n" +
                            "========== NATIVE CRASH DETECTED ==========\n" +
                            "Time: " + new SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.KOREA).format(new Date())
                            + "\n" +
                            "Thread: " + thread.getName() + " (ID: " + thread.getId() + ")\n" +
                            "Exception: " + throwable.getClass().getName() + ": " + throwable.getMessage() + "\n" +
                            "Stack Trace:\n" + stackTrace +
                            "============================================\n\n";

                    Log.e("MainActivity", "CRASH DETECTED: " + crashLog);
                    appendLogToFile(crashLog);
                } catch (Exception e) {
                    Log.e("MainActivity", "Error in crash handler: " + e.getMessage());
                }

                if (originalHandler != null) {
                    originalHandler.uncaughtException(thread, throwable);
                }
            }
        });
    }

    public boolean setAutoStartup(boolean enable) {
        try {
            Log.d("MainActivity", "Setting auto startup: " + enable);

            SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
            SharedPreferences.Editor editor = prefs.edit();
            editor.putBoolean(KEY_AUTO_LAUNCH, enable);

            boolean result = editor.commit();

            if (result) {
                Log.d("MainActivity", "Auto startup setting saved successfully: " + enable);
            } else {
                Log.e("MainActivity", "Failed to save auto startup setting");
            }

            return result;
        } catch (Exception e) {
            Log.e("MainActivity", "Error setting auto startup: " + e.getMessage(), e);
            return false;
        }
    }

    @Override
    public void onBackPressed() {
        Log.d("MainActivity", "Back button pressed, moving to background");
        try {
            moveTaskToBack(true);
        } catch (Exception e) {
            Log.e("MainActivity", "Failed to move task to back in onBackPressed: " + e.getMessage());
            super.onBackPressed();
        }
    }

    public String readLegacyOrderNumberFile() {
        File downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        File appfitDir = new File(downloadDir, "appfit");
        File orderNumDir = new File(appfitDir, "orderNum");
        File currentNumFile = new File(orderNumDir, "current_num.txt");

        if (!currentNumFile.exists() || !currentNumFile.isFile()) {
            Log.w("MainActivity", "Legacy order number file does not exist: " + currentNumFile.getAbsolutePath());
            appendLogToFile("Legacy order number file does not exist: " + currentNumFile.getAbsolutePath());
            return "";
        }

        StringBuilder content = new StringBuilder();
        try (BufferedReader reader = new BufferedReader(
                new InputStreamReader(new FileInputStream(currentNumFile), StandardCharsets.UTF_8))) {
            String line;
            while ((line = reader.readLine()) != null) {
                content.append(line.trim());
            }

            String result = content.toString();
            Log.i("MainActivity", "Successfully read legacy order number file: " + result);
            appendLogToFile("Successfully read legacy order number file: " + result);
            return result;

        } catch (IOException e) {
            Log.e("MainActivity", "Error reading legacy order number file", e);
            appendLogToFile("Error reading legacy order number file: " + e.getMessage());
            return "";
        }
    }
}