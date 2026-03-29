package co.kr.waldlust.order.receive;

import android.Manifest;
import android.app.ActivityManager;
import android.annotation.SuppressLint;
import android.content.ActivityNotFoundException;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
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

import co.kr.waldlust.order.receive.util.print.PrintUtil;
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
    public static PrintUtil printrUtil;

    public static String versionName = "/api/v2";
    public static Bitmap bitmapLogoForPrint = null;

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

        // Register USB permission receiver
        usbPermissionReceiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                String action = intent.getAction();
                if (PrintUtil.PRINTER_USB_PERMISSION.equals(action)) {
                    synchronized (this) {
                        android.hardware.usb.UsbDevice device = intent
                                .getParcelableExtra(android.hardware.usb.UsbManager.EXTRA_DEVICE);
                        if (intent.getBooleanExtra(android.hardware.usb.UsbManager.EXTRA_PERMISSION_GRANTED, false)) {
                            if (device != null) {
                                Log.i("MainActivity", "USB permission granted for device: " + device.getDeviceName());
                                appendLogToFile("USB permission granted for device: " + device.getDeviceName());
                                // 퍼미션이 승인되면 프린터 재연결 시도
                                if (printrUtil != null) {
                                    printrUtil.printerConnect();
                                }
                            }
                        } else {
                            Log.w("MainActivity", "USB permission denied for device: "
                                    + (device != null ? device.getDeviceName() : "unknown"));
                            appendLogToFile("USB permission denied for device: "
                                    + (device != null ? device.getDeviceName() : "unknown"));
                        }
                    }
                }
            }
        };

        IntentFilter usbFilter = new IntentFilter(PrintUtil.PRINTER_USB_PERMISSION);
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(usbPermissionReceiver, usbFilter, Context.RECEIVER_EXPORTED);
        } else {
            registerReceiver(usbPermissionReceiver, usbFilter);
        }

        // Initialize printers
        initPrinters();

        // 타브랜드 로고 준비 필요
        // bitmapLogoForPrint = BitmapFactory.decodeResource(this.getResources(),
        // R.drawable.logo);

        // Show dual monitor if device is D3 MINI -> 현재 매머드만 지원

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

        printrUtil = new PrintUtil(this);
        printrUtil.loadPrinters();

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

            // 2. Task를 전면으로 이동
            ActivityManager activityManager = (ActivityManager) getSystemService(Context.ACTIVITY_SERVICE);
            if (activityManager != null) {
                activityManager.moveTaskToFront(getTaskId(), ActivityManager.MOVE_TASK_WITH_HOME);
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

        if (dualMonitorPresentation != null && dualMonitorPresentation.isShowing()) {
            dualMonitorPresentation.cleanup();
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        Log.d("MainActivity", "onResume called");

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
        // Stop Foreground Service
        stopOrderAgentService();

        // 중요: SUNMI 프린터 서비스 해제 (SUNMI 장비인 경우에만)
        if (isSunmiDevice()) {
            SunmiPrintHelper.getInstance().deInitSunmiPrinterService(this);
        }

        // Unregister USB permission receiver
        if (usbPermissionReceiver != null) {
            unregisterReceiver(usbPermissionReceiver);
        }

        super.onDestroy(); // 항상 마지막에 호출
    }

    private void initPrinters() {
        Log.d("MainActivity", "Initializing printers...");
        if (isSunmiDevice()) {
            SunmiPrintHelper.getInstance().initSunmiPrinterService(this);
        }
        // 라벨 프린터 파일 로깅 초기화
        co.kr.waldlust.order.receive.util.print.LabelPrinter.init(this);
        // printrUtil is initialized in onCreate or elsewhere
    }

    public boolean checkPermissions() {
        Log.d("checkPermissions", "checkPermissions Build.VERSION.SDK_INT: " + Build.VERSION.SDK_INT);
        // API 23 (Marshmallow) 미만은 항상 true (설치 시 권한 부여)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return true;
        }

        // API 33 (Tiramisu) 이상
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

    /**
     * 직접 File I/O로 Documents/appfit/ 폴더에 로그를 기록합니다.
     * MANAGE_EXTERNAL_STORAGE 권한이 있거나 Android 10 + requestLegacyExternalStorage
     * 환경에서 동작합니다.
     * 
     * @return true: 기록 성공, false: 기록 실패 (fallback 필요)
     */
    private boolean appendLogToFileDirectIO(String text, String fileName) {
        try {
            File documentsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS);
            File logDir = new File(documentsDir, "appfit");
            if (!logDir.exists() && !logDir.mkdirs()) {
                Log.w("FileWriter", "DirectIO: Failed to create directory: " + logDir.getAbsolutePath());
                return false;
            }

            File logFile = new File(logDir, fileName);
            try (FileOutputStream fos = new FileOutputStream(logFile, true);
                    OutputStreamWriter writer = new OutputStreamWriter(fos, StandardCharsets.UTF_8)) {
                writer.append(text);
                writer.flush();
            }
            return true;
        } catch (Exception e) {
            Log.w("FileWriter", "DirectIO failed: " + e.getMessage());
            return false;
        }
    }

    /**
     * Android 11+ (R 이상) 환경에서 MANAGE_EXTERNAL_STORAGE 권한 보유 여부를 확인합니다.
     */
    public boolean hasAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            return Environment.isExternalStorageManager();
        }
        // Android 10 이하는 requestLegacyExternalStorage 또는 WRITE_EXTERNAL_STORAGE로 커버
        return true;
    }

    /**
     * MANAGE_EXTERNAL_STORAGE 권한을 요청하기 위해 시스템 설정 화면을 엽니다.
     */
    public void requestAllFilesAccess() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
                intent.setData(Uri.parse("package:" + getPackageName()));
                startActivityForResult(intent, REQUEST_CODE_ALL_FILES_ACCESS);
            } catch (Exception e) {
                Log.e("FileWriter", "Failed to open All Files Access settings", e);
                // Fallback: 일반 설정 화면
                try {
                    Intent intent = new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION);
                    startActivityForResult(intent, REQUEST_CODE_ALL_FILES_ACCESS);
                } catch (Exception e2) {
                    Log.e("FileWriter", "Failed to open general All Files Access settings", e2);
                }
            }
        }
    }

    /**
     * 앱 전용 외부 저장소에 로그를 기록합니다. (fallback용)
     * 경로: /Android/data/${packageName}/files/logs/
     * 권한 불필요, 앱 삭제 시 함께 삭제됨.
     */
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

    // Add method to check if device is SUNMI
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

    private void showDualMonitor(String id) {
        DisplayManager cDisplayManager = (DisplayManager) getSystemService(Context.DISPLAY_SERVICE);
        Display[] cDisplays = cDisplayManager.getDisplays();
        DISPLAY_LENGTH = cDisplays.length;
        Log.e("cDisplays.length", String.valueOf(cDisplays.length));
        if (cDisplays.length > 1) {
            dualMonitorPresentation = new DualMonitorPresentation(this, cDisplays[1], id);
            Log.d("MainActivity", "showDualMonitor()");
            dualMonitorPresentation.show();
        } else {
            Log.d("MainActivity", "no DualMonitor");
        }
    }

    // DualMonitorPresentation class
    private class DualMonitorPresentation extends Presentation {
        private VideoView videoView;
        private ImageView imageView;
        private String videoUrl;
        private String packageName;
        private String storeId;
        private MediaController mediaController;
        private boolean isDestroyed = false;
        private boolean showImage = false;

        public DualMonitorPresentation(Context outerContext, Display display, String id) {
            super(outerContext, display);
            this.packageName = outerContext.getPackageName();
            this.storeId = id;
        }

        @SuppressLint("MissingInflatedId")
        @Override
        protected void onCreate(Bundle savedInstanceState) {
            super.onCreate(savedInstanceState);
            setContentView(R.layout.dual_monitor);

            videoView = findViewById(R.id.videoView1);
            imageView = findViewById(R.id.imageView1);
            if (storeId.toLowerCase().startsWith("k013")) {
                setVideo(R.raw.mmth);
            } else if (storeId.toLowerCase().startsWith("k047")) {
                setImage(R.drawable.blushaak_dual_monitor_logo);
            } else if (storeId.toLowerCase().startsWith("k064")) {
                setImage(R.drawable.milkypresso_dual_monitor_logo);
            }

        }

        private void setImage(int imageResource) {
            imageView.setImageResource(imageResource);
            imageView.setVisibility(View.VISIBLE);
        }

        // 동영상 파일 매머드만 존재
        private void setVideo(int videoResource) {
            videoUrl = "android.resource://" + packageName + "/" + videoResource;
            Uri videoUri = Uri.parse(videoUrl);

            videoView.setVideoURI(videoUri);

            videoView.setOnPreparedListener(new MediaPlayer.OnPreparedListener() {
                @Override
                public void onPrepared(MediaPlayer mp) {
                    mp.setVolume(0f, 0f); // 왼쪽, 오른쪽 음량을 모두 0으로 설정
                    // 동영상 크기 최적화
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
                        videoView.start(); // 재생이 완료되면 다시 시작
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
                // Request permission. Service will be started in onRequestPermissionsResult if
                // granted.
                requestPermissions(new String[] { Manifest.permission.POST_NOTIFICATIONS },
                        REQUEST_CODE_POST_NOTIFICATION);
            } else {
                Log.d("MainActivity", "Notification permission already granted. Starting service.");
                startOrderAgentService();
            }
        } else {
            // Below Tiramisu, permission is not needed
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
                // Fallback: Open battery optimization settings for the user to manually
                // configure
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
        cal.add(Calendar.MONTH, -6); // Calculate date 6 months ago
        long cutoffMillis = cal.getTimeInMillis();
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd", Locale.getDefault());

        Log.d("MainActivity", "Checking for log files older than 6 months in: " + logDir.getAbsolutePath());

        for (File file : logFiles) {
            if (file.isFile() && file.getName().endsWith(".txt")) {
                String fileName = file.getName();
                try {
                    // Extract date string from filename (e.g., "2023-10-27" from "2023-10-27.txt")
                    String dateString = fileName.substring(0, fileName.length() - 4);
                    Date fileDate = dateFormat.parse(dateString);

                    if (fileDate != null && fileDate.getTime() < cutoffMillis) {
                        Log.i("MainActivity", "Deleting old log file: " + fileName);
                        if (file.delete()) {
                            Log.d("MainActivity", "Successfully deleted: " + fileName);
                            appendLogToFile("Successfully deleted: " + fileName);
                        } else {
                            Log.w("MainActivity", "Failed to delete: " + fileName);
                            appendLogToFile("Failed to delete: " + fileName);
                        }
                    } else {
                        // Log.d("MainActivity", "Keeping log file (not older than 6 months): " +
                        // fileName);
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

    public void saveStoreIdToNative(String storeId, boolean isKdsMode, String mainURL) {
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();
        editor.putString(KEY_STORE_ID, storeId);
        editor.putBoolean(KEY_IS_KDS_MODE, isKdsMode);
        editor.putString(KEY_MAIN_URL, mainURL);
        editor.apply();
    }

    public void appendLogToFile(String text) {
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.getDefault());
        String timestampedText = sdf.format(new Date()) + " " + text + "\n";
        String date = getDate(System.currentTimeMillis());
        String fileName = "appfit_" + date + ".txt";

        // 1순위: Documents/appfit/에 직접 File I/O
        // (Android 7~9: WRITE_EXTERNAL_STORAGE, Android 10:
        // requestLegacyExternalStorage,
        // Android 11+: MANAGE_EXTERNAL_STORAGE)
        if (!appendLogToFileDirectIO(timestampedText, fileName)) {
            // 2순위: 앱 전용 외부 폴더 (권한 불필요, 앱 삭제 시 함께 삭제됨)
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

        // 1순위: Documents/appfit/에 직접 File I/O
        if (!appendLogToFileDirectIO(combinedText, fileName)) {
            // 2순위: 앱 전용 외부 폴더
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

                // 기존 핸들러에 전달 (앱 종료 등 기본 처리 수행)
                if (originalHandler != null) {
                    originalHandler.uncaughtException(thread, throwable);
                }
            }
        });
    }

    public boolean setAutoStartup(boolean enable) {
        try {
            Log.d("MainActivity", "Setting auto startup: " + enable);

            // KEY_AUTO_LAUNCH 값을 SharedPreferences에 저장
            SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
            SharedPreferences.Editor editor = prefs.edit();
            editor.putBoolean(KEY_AUTO_LAUNCH, enable);

            // 설정 즉시 적용
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
        // 뒤로가기 버튼이 눌렸을 때 앱을 종료하지 않고 백그라운드로 이동
        Log.d("MainActivity", "Back button pressed, moving to background");

        // 홈 화면으로 이동
        Intent intent = new Intent(Intent.ACTION_MAIN);
        intent.addCategory(Intent.CATEGORY_HOME);
        intent.setFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(intent);
    }

    public String readLegacyOrderNumberFile() {
        File downloadDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
        File appfitDir = new File(downloadDir, "appfit");
        File orderNumDir = new File(appfitDir, "orderNum");
        File currentNumFile = new File(orderNumDir, "current_num.txt");

        // 파일 존재 여부 확인
        if (!currentNumFile.exists() || !currentNumFile.isFile()) {
            Log.w("MainActivity", "Legacy order number file does not exist: " + currentNumFile.getAbsolutePath());
            appendLogToFile("Legacy order number file does not exist: " + currentNumFile.getAbsolutePath());
            return "";
        }

        // 파일 읽기
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