package co.kr.waldlust.order.receive.util.print;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Build;

/**
 * 라벨 프린터 USB 권한 요청 공용 헬퍼.
 *
 * <p>원래 이 로직은 구 XD5-40d 드라이버 안에만 있었고, Caysn/REXOD 경로
 * ({@link LabelPrinter})는 SDK 내부(autoreplyprint.aar 의 {@code NZUSBClientIO.Open})
 * 요청에 의존해 왔다. 그 구현은 {@code PendingIntent.getBroadcast(..., flags=0)} 을
 * 쓰는데, <b>Android 12+ 단말에서는</b> FLAG_IMMUTABLE/FLAG_MUTABLE 중 하나가 필수라
 * IllegalArgumentException 이 나고 SDK 가 그것을 삼킨다 — 그 단말에서는 권한 요청이
 * 사실상 존재하지 않는다. Android 11 이하(D2s_KDS 등)에서는 SDK 요청도 동작하지만,
 * <b>요청 결과를 기다리지 않고 곧바로 openDevice 로 진행</b>하는 것은 버전과 무관하다.
 * 두 벤더가 같은 규칙을 쓰도록 여기로 모은다.
 *
 * <p>이 action 을 수신하는 리시버는 앱에 없다. 승인 판정은 broadcast 가 아니라
 * {@code UsbManager.hasPermission()} 재조회로 한다 — BIXOLON 경로가 이미 그렇게
 * 동작해 왔고, 리시버 등록 여부와 무관하게 시스템이 권한을 부여하기 때문이다.
 */
public final class UsbPermissionHelper {

    /** 권한 결과 PendingIntent 의 action. 구독자는 없다 (위 클래스 주석 참조). */
    public static final String ACTION_USB_PERMISSION =
            "co.kr.waldlust.order.receive.LABEL_USB_PERMISSION";

    private UsbPermissionHelper() {
    }

    /**
     * 시스템 USB 권한 다이얼로그를 띄운다. 승인 대기는 하지 않는다 (호출자 책임).
     *
     * <p>호출 전에 {@code hasPermission()} 으로 필요 여부를 먼저 확인할 것 —
     * 권한이 이미 있으면 다이얼로그가 뜨지 않지만, 불필요한 요청 자체를 남기지 않는다.
     */
    public static void request(Context ctx, UsbManager usbManager, UsbDevice device) {
        if (ctx == null || usbManager == null || device == null) {
            return;
        }
        int flags;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ 는 권한 승인 extra 를 시스템이 채워 넣기 위해 FLAG_MUTABLE 필요.
            flags = PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT;
        } else {
            flags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent permissionIntent = PendingIntent.getBroadcast(
                ctx.getApplicationContext(), 0,
                new Intent(ACTION_USB_PERMISSION), flags);
        usbManager.requestPermission(device, permissionIntent);
    }
}
