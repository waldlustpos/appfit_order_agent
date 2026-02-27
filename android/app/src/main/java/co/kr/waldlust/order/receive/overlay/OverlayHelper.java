package co.kr.waldlust.order.receive.overlay;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.provider.Settings;
import android.util.Log;

public class OverlayHelper {
    private static final String TAG = "OverlayHelper";
    public static final int REQUEST_OVERLAY_PERMISSION = 1234;

    /**
     * 오버레이 권한이 있는지 확인
     */
    public static boolean canDrawOverlays(Context context) {
        return Settings.canDrawOverlays(context);
    }

    /**
     * 오버레이 권한 요청 화면으로 이동
     */
    public static void requestOverlayPermission(Activity activity) {
        Log.d(TAG, "Requesting overlay permission");

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Intent intent = new Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:" + activity.getPackageName()));
            activity.startActivityForResult(intent, REQUEST_OVERLAY_PERMISSION);
        }
    }

    /**
     * 플로팅 버블 서비스 시작
     */
    public static void showBubble(Context context, float x, float y) {
        Log.d(TAG, "Starting floating bubble service at position: " + x + ", " + y);

        if (canDrawOverlays(context)) {
            Intent intent = new Intent(context, FloatingBubbleService.class);
            intent.putExtra("initial_x", x);
            intent.putExtra("initial_y", y);
            context.startService(intent);
        } else {
            Log.e(TAG, "Cannot show bubble: overlay permission not granted");
        }
    }

    /**
     * 기본 위치에 플로팅 버블 서비스 시작 (하위 호환성 유지)
     */
    public static void showBubble(Context context) {
        showBubble(context, 0, 100);
    }

    /**
     * 플로팅 버블 서비스 종료
     */
    public static void hideBubble(Context context) {
        Log.d(TAG, "Stopping floating bubble service");

        Intent intent = new Intent(context, FloatingBubbleService.class);
        context.stopService(intent);
    }

    /**
     * 새 주문 알림 (버블 깜빡임 효과)
     */
    public static void notifyNewOrder(Context context) {
        Log.d(TAG, "Notifying new order to bubble service");
        FloatingBubbleService.notifyNewOrder(context);
    }
}