package co.kr.waldlust.order.receive;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;
import android.util.Log;

public class AutoStartReceiver extends BroadcastReceiver {
    private static final String TAG = "AutoStartReceiver";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            Log.d(TAG, "Boot completed received");
            
            // SharedPreferences에서 자동 실행 설정 확인
            SharedPreferences prefs = context.getSharedPreferences("KOKONUT_AGENT", Context.MODE_PRIVATE);
            boolean autoStart = prefs.getBoolean("KEY_AUTO_LAUNCH", false);
            
            if (autoStart) {
                Log.d(TAG, "Auto start is enabled, launching app");
                
                // 앱 실행을 위한 인텐트 생성
                Intent launchIntent = new Intent(context, MainActivity.class);
                launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                
                // Android 10 이상에서는 약간의 지연 후 실행
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    new Thread(() -> {
                        try {
                            // 부팅 완료 후 약간의 지연을 주어 시스템이 안정화될 시간을 확보
                            Thread.sleep(10000);
                            context.startActivity(launchIntent);
                            Log.d(TAG, "App launched after delay on Android 10+");
                        } catch (Exception e) {
                            Log.e(TAG, "Error launching app: " + e.getMessage());
                        }
                    }).start();
                } else {
                    // Android 9 이하에서는 즉시 실행
                    context.startActivity(launchIntent);
                    Log.d(TAG, "App launched immediately on Android 9 or below");
                }
            } else {
                Log.d(TAG, "Auto start is disabled, not launching app");
            }
        }
    }
} 