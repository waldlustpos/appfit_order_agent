package co.kr.waldlust.order.receive;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;
import android.view.Surface;

public class AutoStartReceiver extends BroadcastReceiver {
    private static final String TAG = "AutoStartReceiver";

    private void applyRotationFromPrefs(Context context) {
        // Flutter shared_preferences 플러그인은 "FlutterSharedPreferences" 파일에 저장함
        SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        // Flutter shared_preferences 플러그인은 모든 키에 "flutter." 접두사를 붙여 저장
        boolean isRotated180 = prefs.getBoolean("flutter.KEY_IS_ROTATED_180", false);
        if (Settings.System.canWrite(context)) {
            Settings.System.putInt(context.getContentResolver(),
                    Settings.System.ACCELEROMETER_ROTATION, 0);
            Settings.System.putInt(context.getContentResolver(),
                    Settings.System.USER_ROTATION,
                    isRotated180 ? Surface.ROTATION_180 : Surface.ROTATION_0);
            Log.d(TAG, "화면 회전 복원 완료 — " + (isRotated180 ? "180도" : "정상"));
        } else {
            Log.w(TAG, "WRITE_SETTINGS 권한 없음 — 화면 회전 복원 건너뜀");
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();

        // USER_UNLOCKED: OS 초기화 완료 후 발화 — 커스텀 OS가 BOOT_COMPLETED 이후 rotation을
        // 리셋하는 경우를 커버. 잠금화면 없는 기기에서도 발화됨.
        if (android.content.Intent.ACTION_USER_UNLOCKED.equals(action)) {
            Log.d(TAG, "User unlocked — 화면 회전 복원 시도");
            applyRotationFromPrefs(context);
            return;
        }

        if (!Intent.ACTION_BOOT_COMPLETED.equals(action)) return;

        Log.d(TAG, "Boot completed received");

        // BOOT_COMPLETED 시점에 즉시 1차 적용 (빠른 복원)
        applyRotationFromPrefs(context);

        // 커스텀 OS가 BOOT_COMPLETED 이후에도 rotation을 리셋할 수 있으므로
        // 3초 후 한 번 더 적용 (USER_UNLOCKED가 없는 환경 대비)
        new Thread(() -> {
            try {
                Thread.sleep(3000);
                applyRotationFromPrefs(context);
                Log.d(TAG, "Boot: 3초 후 화면 회전 재적용 완료");
            } catch (Exception e) {
                Log.e(TAG, "Boot: 회전 재적용 실패 — " + e.getMessage());
            }
        }).start();

        // SharedPreferences에서 자동 실행 설정 확인
        SharedPreferences prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        boolean autoStart = prefs.getBoolean("flutter.KEY_AUTO_LAUNCH", false);

        if (autoStart) {
            Log.d(TAG, "Auto start is enabled, launching app");

            Intent launchIntent = new Intent(context, MainActivity.class);
            launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                new Thread(() -> {
                    try {
                        Thread.sleep(10000);
                        context.startActivity(launchIntent);
                        Log.d(TAG, "App launched after delay on Android 10+");
                    } catch (Exception e) {
                        Log.e(TAG, "Error launching app: " + e.getMessage());
                    }
                }).start();
            } else {
                context.startActivity(launchIntent);
                Log.d(TAG, "App launched immediately on Android 9 or below");
            }
        } else {
            Log.d(TAG, "Auto start is disabled, not launching app");
        }
    }
} 