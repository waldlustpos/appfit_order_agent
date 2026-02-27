package co.kr.waldlust.order.receive.overlay;

import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.os.IBinder;
import android.provider.Settings;
import android.util.Log;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.MotionEvent;
import android.view.View;
import android.view.WindowManager;
import android.view.animation.AlphaAnimation;
import android.view.animation.Animation;
import android.widget.ImageView;
import androidx.annotation.Nullable;
import androidx.cardview.widget.CardView;

import co.kr.waldlust.order.receive.MainActivity;
import co.kr.waldlust.order.receive.R;

public class FloatingBubbleService extends Service {
    private WindowManager windowManager;
    private View bubbleView;
    private WindowManager.LayoutParams params;
    private CardView cardView;
    private ImageView iconView;
    private Animation blinkAnimation;
    private Handler animationHandler;
    private Runnable animationRunnable;
    private boolean isBlinking = false;

    private static final String TAG = "FloatingBubbleService";
    private static final int BUBBLE_SIZE_DP = 80;
    private static final String PREFERENCES_NAME = "KOKONUT_AGENT";
    private static final String KEY_OVERLAY_X = "KOKONUT_KEY_OVERLAY_X";
    private static final String KEY_OVERLAY_Y = "KOKONUT_KEY_OVERLAY_Y";
    
    private int initialX;
    private int initialY;
    private float initialTouchX;
    private float initialTouchY;
    
    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Service onCreate");
        
        // 윈도우 매니저 초기화
        windowManager = (WindowManager) getSystemService(WINDOW_SERVICE);
        
        // 애니메이션 초기화
        setupAnimations();
        
        // 애니메이션 핸들러 초기화
        animationHandler = new Handler();
    }

    private void setupAnimations() {
        // 이미지 애니메이션 설정
        blinkAnimation = new AlphaAnimation(1.0f, 1.0f); // 투명도 변화 없음
        blinkAnimation.setDuration(500); // 0.5초마다 이미지 교체
        blinkAnimation.setRepeatMode(Animation.RESTART);
        blinkAnimation.setRepeatCount(Animation.INFINITE);
        
        // 애니메이션 리스너를 통해 이미지 교체
        blinkAnimation.setAnimationListener(new Animation.AnimationListener() {
            private boolean showOnImage = true;
            
            @Override
            public void onAnimationStart(Animation animation) {
                // 초기 이미지 설정
                if (iconView != null) {
                    iconView.setImageResource(R.drawable.ic_order_on);
                }
            }

            @Override
            public void onAnimationEnd(Animation animation) {
                // 사용하지 않음 (무한 반복)
            }

            @Override
            public void onAnimationRepeat(Animation animation) {
                // 이미지 토글
                if (iconView != null) {
                    if (showOnImage) {
                        iconView.setImageResource(R.drawable.ic_order_off);
                    } else {
                        iconView.setImageResource(R.drawable.ic_order_on);
                    }
                    showOnImage = !showOnImage;
                }
            }
        });
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        // 버블 뷰가 이미 존재하고, 유효한 인텐트가 전달된 경우
        if (bubbleView != null && windowManager != null && intent != null) {
            Log.d(TAG, "Bubble already exists. Checking for new order flag.");
            boolean hasNewOrder = intent.getBooleanExtra("has_new_order", false);
            if (hasNewOrder) {
                // 이미 존재하는 뷰에 대해 애니메이션만 시작
                startBlinking();
            }
            // 뷰를 다시 생성하지 않고 종료
            return START_STICKY;
        }

        // 기존에 뷰가 있으면 제거 (이 로직은 사실상 위의 조건문 때문에 실행되지 않지만 안전하게 남겨둠)
        if (bubbleView != null) {
             try { // 혹시 모를 예외 처리
               windowManager.removeView(bubbleView);
            } catch (Exception e) {
               Log.e(TAG, "Error removing existing bubble view", e);
            }
            bubbleView = null;
        }

        // 버블 뷰 인플레이트
        bubbleView = LayoutInflater.from(this).inflate(R.layout.bubble_layout, null);
        
        // 카드뷰와 아이콘 뷰 참조 얻기
        cardView = bubbleView.findViewById(R.id.bubble_card_view);
        iconView = bubbleView.findViewById(R.id.bubble_icon);
        
        // 아이콘 변경 (기본 이미지)
        iconView.setImageResource(R.drawable.ic_order_on);
        
        // 새 주문 알림 확인 (인텐트에서 전달된 경우)
        boolean hasNewOrder = false;
        if (intent != null) {
            hasNewOrder = intent.getBooleanExtra("has_new_order", false);
        }
        
        // 레이아웃 파라미터 설정
        int LAYOUT_FLAG;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            LAYOUT_FLAG = WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY;
        } else {
            LAYOUT_FLAG = WindowManager.LayoutParams.TYPE_PHONE;
        }
        
        // 픽셀 변환 (DP -> Pixels)
        float density = getResources().getDisplayMetrics().density;
        int bubbleSizePixels = (int) (BUBBLE_SIZE_DP * density);
        
        // 윈도우 레이아웃 파라미터 설정
        params = new WindowManager.LayoutParams(
                bubbleSizePixels,
                bubbleSizePixels,
                LAYOUT_FLAG,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT);
        
        // 초기 위치 설정
        params.gravity = Gravity.TOP | Gravity.START;
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        int x = prefs.getInt(KEY_OVERLAY_X, 100); // 저장된 값 또는 기본값
        int y = prefs.getInt(KEY_OVERLAY_Y, 100);
        params.x = x;
        params.y = y;
        
        // 버블 뷰에 터치 리스너 설정
        bubbleView.setOnTouchListener(new View.OnTouchListener() {
            @Override
            public boolean onTouch(View v, MotionEvent event) {
                switch (event.getAction()) {
                    case MotionEvent.ACTION_DOWN:
                        initialX = params.x;
                        initialY = params.y;
                        initialTouchX = event.getRawX();
                        initialTouchY = event.getRawY();
                        return true;
                        
                    case MotionEvent.ACTION_MOVE:
                        params.x = initialX + (int) (event.getRawX() - initialTouchX);
                        params.y = initialY + (int) (event.getRawY() - initialTouchY);
                        if (bubbleView != null && windowManager != null) {
                            try {
                                windowManager.updateViewLayout(bubbleView, params);
                            } catch (IllegalArgumentException e) {
                                Log.e(TAG, "Failed to update view layout", e);
                                return false;
                            }
                        }
                        return true;
                        
                    case MotionEvent.ACTION_UP:
                        int xDiff = Math.abs(params.x - initialX);
                        int yDiff = Math.abs(params.y - initialY);
                        
                        if (xDiff < 10 && yDiff < 10) {
                            Log.d(TAG, "Bubble clicked");
                            stopBlinking();
                            Intent mainActivityIntent = new Intent(getApplicationContext(), MainActivity.class);
                            mainActivityIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
                            startActivity(mainActivityIntent);
                            stopSelf();
                        } else {
                            savePosition(params.x, params.y);
                        }
                        return true;
                }
                return false;
            }
        });
        
        // 윈도우에 뷰 추가
        try {
            windowManager.addView(bubbleView, params);
            Log.d(TAG, "Bubble view added to window at position: " + params.x + ", " + params.y);
        } catch (Exception e) {
             Log.e(TAG, "Error adding bubble view to window", e);
             stopSelf(); // 뷰 추가 실패 시 서비스 종료
             return START_NOT_STICKY;
        }
        
        // 새 주문이 있으면 애니메이션 시작
        if (hasNewOrder) {
            startBlinking();
        }
        
        return START_STICKY;
    }
    
    private void savePosition(int x, int y) {
        Log.d(TAG, "Saving bubble position: " + x + ", " + y);
        SharedPreferences prefs = getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
        SharedPreferences.Editor editor = prefs.edit();
        editor.putInt(KEY_OVERLAY_X, x);
        editor.putInt(KEY_OVERLAY_Y, y);
        editor.apply();
    }
    
    // 새 주문 알림 설정 - 외부에서 호출
    public static void notifyNewOrder(Context context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (Settings.canDrawOverlays(context)) {
                // 현재 위치 불러오기
                SharedPreferences prefs = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE);
                int x = prefs.getInt(KEY_OVERLAY_X, 100);
                int y = prefs.getInt(KEY_OVERLAY_Y, 100);

                // 새 주문 플래그와 함께 서비스 재시작
                Intent intent = new Intent(context, FloatingBubbleService.class);
                intent.putExtra("has_new_order", true);
                intent.putExtra("initial_x", x);
                intent.putExtra("initial_y", y);
                context.startService(intent);
            }
        }
    }
    
    // 점멸 효과 시작
    public void startBlinking() {
        if (isBlinking) return;
        
        isBlinking = true;
        Log.d(TAG, "Starting blinking animation");
        
        if (iconView != null) {
            iconView.startAnimation(blinkAnimation);
        }

    }
    
    // 점멸 효과 중지
    public void stopBlinking() {
        if (!isBlinking) return;
        
        isBlinking = false;
        Log.d(TAG, "Stopping blinking animation");
        
        if (iconView != null) {
            iconView.clearAnimation();
            // 기본 이미지로 복원
            iconView.setImageResource(R.drawable.ic_order_on);
        }
        
        // 예약된 애니메이션 중지 작업 취소
        if (animationHandler != null && animationRunnable != null) {
            animationHandler.removeCallbacks(animationRunnable);
        }
    }
    
    @Override
    public void onDestroy() {
        super.onDestroy();
        Log.d(TAG, "Service onDestroy");
        
        // 애니메이션 중지
        stopBlinking();
        
        if (bubbleView != null && windowManager != null) {
            // 윈도우에서 뷰 제거
            windowManager.removeView(bubbleView);
            bubbleView = null;
        }
    }
    
    @Nullable
    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }

    // --- onTaskRemoved() 오버라이드 시작 ---
    @Override
    public void onTaskRemoved(Intent rootIntent) {
        Log.d(TAG, "onTaskRemoved called - stopping service");
        stopSelf(); // 태스크 제거 시 서비스 종료
        super.onTaskRemoved(rootIntent);
    }
    // --- onTaskRemoved() 오버라이드 끝 ---
} 