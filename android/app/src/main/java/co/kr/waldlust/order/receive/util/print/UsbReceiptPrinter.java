package co.kr.waldlust.order.receive.util.print;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.os.Build;
import android.util.Log;

import java.util.HashMap;
import java.util.Map;

/**
 * 범용 USB ESC/POS 영수증 프린터 전송 계층.
 * <p>
 * 기존의 Posbank PrinterManager 래퍼(PrintUtil)를 안드로이드 표준
 * UsbManager + UsbDeviceConnection.bulkTransfer 위의 얇은 계층으로 대체한다.
 * Dart 측이 ReceiptEscPosBuilder.toBytesCp949() 로 CP949 인코딩이 끝난 ESC/POS
 * 바이트 스트림을 통째로 만들어 넘기고, 이 클래스는 디바이스 탐색·권한 요청·
 * 인터페이스/엔드포인트 선택·bulk OUT 전송만 담당한다.
 * <p>
 * 스레드: 상태를 바꾸는 public 메서드는 모두 synchronized. 실제 전송은
 * NativeMethodHandler.receiptPrintExecutor (단일 스레드 직렬화) 에서만 호출돼야 한다.
 */
public class UsbReceiptPrinter {

    private static final String TAG = "UsbReceiptPrinter";

    public static final String ACTION_USB_PERMISSION =
            "co.kr.waldlust.order.receive.RECEIPT_USB_PERMISSION";

    // Posbank VID — 인터페이스 클래스가 7(Printer) 이 아닌 모델을 명시적으로 잡기 위한 힌트.
    private static final int VID_POSBANK = 0x1552;

    // bulkTransfer 청크 분할: 구버전 안드로이드는 단일 bulkTransfer 호출 한계가 16 KiB 라
    // 그 절반 수준으로 안전하게 쪼갠다. 로고 비트맵 포함 영수증은 30~80 KiB 까지 갈 수 있다.
    private static final int CHUNK_SIZE = 8 * 1024;
    private static final int CHUNK_TIMEOUT_MS = 5000;

    private final Context appContext;
    private final UsbManager usbManager;

    private final Object lock = new Object();

    // 현재 열려 있는 전송 채널 상태. 디바이스 open 전엔 모두 null.
    private UsbDevice openDevice;
    private UsbDeviceConnection connection;
    private UsbInterface claimedInterface;
    private UsbEndpoint bulkOut;

    public UsbReceiptPrinter(Context context) {
        this.appContext = context.getApplicationContext();
        this.usbManager = (UsbManager) appContext.getSystemService(Context.USB_SERVICE);
    }

    /**
     * 연결된 USB 디바이스를 순회하면서 라벨 프린터는 건너뛰고, 첫 번째 영수증
     * 프린터 후보를 열어 본다. 권한이 없으면 시스템 권한 다이얼로그를 띄우고
     * 반환하며, 사용자가 승인하면 MainActivity 의 BroadcastReceiver 가
     * {@link #onPermissionGranted(UsbDevice)} 를 호출한다.
     * <p>
     * 멱등(idempotent): 동일 디바이스 연결이 이미 살아 있으면 그대로 재사용,
     * 다른 후보로 바뀌었을 때만 기존 연결을 닫고 재오픈한다.
     */
    public void discover() {
        synchronized (lock) {
            if (usbManager == null) {
                Log.w(TAG, "discover: UsbManager unavailable");
                return;
            }

            HashMap<String, UsbDevice> devices = usbManager.getDeviceList();
            Log.d(TAG, "discover: device count = " + (devices != null ? devices.size() : 0));
            if (devices == null || devices.isEmpty()) return;

            UsbDevice candidate = null;
            for (UsbDevice d : devices.values()) {
                logDeviceDescriptor(d);
                if (isLabelPrinter(d)) continue;
                if (!isReceiptCandidate(d)) continue;
                if (candidate == null) {
                    candidate = d;
                } else {
                    Log.w(TAG, "discover: additional receipt candidate ignored: " + d.getDeviceName());
                }
            }

            if (candidate == null) {
                Log.w(TAG, "discover: no receipt printer candidate found");
                return;
            }

            if (openDevice != null && openDevice.getDeviceId() == candidate.getDeviceId()
                    && bulkOut != null) {
                Log.d(TAG, "discover: already open on " + candidate.getDeviceName());
                return;
            }

            // 아직 열린 연결이 없거나 다른 디바이스가 후보가 됐을 때 — 닫고 (재)오픈.
            closeLocked();

            if (!usbManager.hasPermission(candidate)) {
                Log.i(TAG, "discover: requesting permission for " + candidate.getDeviceName());
                requestPermission(candidate);
                return;
            }

            openLocked(candidate);
        }
    }

    /**
     * 사용자가 권한 다이얼로그에서 승인했을 때 MainActivity 의
     * USB 권한 BroadcastReceiver 가 호출하는 진입점.
     */
    public void onPermissionGranted(UsbDevice device) {
        if (device == null) return;
        synchronized (lock) {
            if (isLabelPrinter(device) || !isReceiptCandidate(device)) {
                Log.d(TAG, "onPermissionGranted: ignoring non-candidate " + device.getDeviceName());
                return;
            }
            if (openDevice != null && openDevice.getDeviceId() == device.getDeviceId()
                    && bulkOut != null) {
                return;
            }
            closeLocked();
            openLocked(device);
        }
    }

    /**
     * USB 디바이스가 물리적으로 분리됐을 때 MainActivity 가 호출한다.
     * 분리된 디바이스가 현재 열려 있는 디바이스와 일치하면 연결을 닫는다.
     */
    public void onUsbDetached(UsbDevice device) {
        if (device == null) return;
        synchronized (lock) {
            if (openDevice != null && openDevice.getDeviceId() == device.getDeviceId()) {
                Log.i(TAG, "onUsbDetached: closing " + device.getDeviceName());
                closeLocked();
            }
        }
    }

    public boolean isConnected() {
        synchronized (lock) {
            return connection != null && bulkOut != null;
        }
    }

    /**
     * 주어진 ESC/POS 바이트 스트림을 8 KiB 청크 단위로 영수증 프린터에 전송한다.
     * 어떤 청크라도 실패하면 false 를 반환하고 연결을 강제로 닫아, 다음
     * discover() 호출에서 복구할 수 있게 한다.
     */
    public boolean writeBytes(byte[] data, String jobName) {
        if (data == null || data.length == 0) return false;
        UsbDeviceConnection conn;
        UsbEndpoint out;
        synchronized (lock) {
            conn = connection;
            out = bulkOut;
        }
        if (conn == null || out == null) {
            Log.e(TAG, "writeBytes: not connected (job=" + jobName + ")");
            return false;
        }

        int offset = 0;
        while (offset < data.length) {
            int len = Math.min(CHUNK_SIZE, data.length - offset);
            byte[] chunk;
            if (offset == 0 && len == data.length) {
                chunk = data;
            } else {
                chunk = new byte[len];
                System.arraycopy(data, offset, chunk, 0, len);
            }
            int sent = conn.bulkTransfer(out, chunk, len, CHUNK_TIMEOUT_MS);
            if (sent < 0) {
                Log.e(TAG, "writeBytes: bulkTransfer failed at offset=" + offset
                        + " len=" + len + " (job=" + jobName + ")");
                synchronized (lock) {
                    closeLocked();
                }
                return false;
            }
            offset += sent;
        }
        Log.d(TAG, "writeBytes: " + data.length + " bytes sent (job=" + jobName + ")");
        return true;
    }

    public void close() {
        synchronized (lock) {
            closeLocked();
        }
    }

    // ---- 내부 구현 -------------------------------------------------------

    private void openLocked(UsbDevice device) {
        int[] sel = selectInterfaceAndEndpoint(device);
        if (sel == null) {
            Log.e(TAG, "openLocked: no usable interface/endpoint on " + device.getDeviceName());
            return;
        }
        UsbInterface intf = device.getInterface(sel[0]);
        UsbEndpoint ep = intf.getEndpoint(sel[1]);

        UsbDeviceConnection conn = usbManager.openDevice(device);
        if (conn == null) {
            Log.e(TAG, "openLocked: openDevice returned null for " + device.getDeviceName());
            return;
        }
        if (!conn.claimInterface(intf, true)) {
            Log.e(TAG, "openLocked: claimInterface failed for " + device.getDeviceName());
            conn.close();
            return;
        }
        this.openDevice = device;
        this.connection = conn;
        this.claimedInterface = intf;
        this.bulkOut = ep;
        Log.i(TAG, "openLocked: connected " + device.getDeviceName()
                + " intf=" + sel[0] + " ep=" + sel[1]);
    }

    private void closeLocked() {
        if (connection != null) {
            try {
                if (claimedInterface != null) {
                    connection.releaseInterface(claimedInterface);
                }
            } catch (Exception e) {
                Log.w(TAG, "closeLocked: releaseInterface error", e);
            }
            try {
                connection.close();
            } catch (Exception e) {
                Log.w(TAG, "closeLocked: connection.close error", e);
            }
        }
        openDevice = null;
        connection = null;
        claimedInterface = null;
        bulkOut = null;
    }

    private void requestPermission(UsbDevice device) {
        int flags;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ 는 권한 승인 extra 를 시스템이 채워 넣기 위해 FLAG_MUTABLE 이 필요하다.
            flags = PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT;
        } else {
            flags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent permissionIntent = PendingIntent.getBroadcast(
                appContext, 0, new Intent(ACTION_USB_PERMISSION), flags);
        usbManager.requestPermission(device, permissionIntent);
    }

    /**
     * 인터페이스 + bulk OUT 엔드포인트 쌍을 3단계(tier)로 선택한다:
     *   1) USB Printer class(7), subclass 1, protocol 1/2/3 + bulk OUT.
     *   2) vendor-specific class(0xFF) 인터페이스 + bulk OUT
     *      (윈도우 전용 드라이버만 제공하면서 class 7 디스크립터를 노출하지
     *      않는 ESC/POS 프린터에서 자주 발견됨).
     *   3) 클래스 무관, bulk OUT 엔드포인트가 존재하는 모든 인터페이스.
     *
     * @return int[]{ 인터페이스 인덱스, 엔드포인트 인덱스 }, 못 찾으면 null.
     */
    private int[] selectInterfaceAndEndpoint(UsbDevice device) {
        if (device == null || device.getInterfaceCount() == 0) return null;

        // Tier 1: 표준 USB Printer class.
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface intf = device.getInterface(i);
            if (intf.getInterfaceClass() == UsbConstants.USB_CLASS_PRINTER
                    && intf.getInterfaceSubclass() == 1
                    && (intf.getInterfaceProtocol() == 1
                            || intf.getInterfaceProtocol() == 2
                            || intf.getInterfaceProtocol() == 3)) {
                int ep = findBulkOutEndpoint(intf);
                if (ep >= 0) {
                    Log.d(TAG, "selectInterfaceAndEndpoint: tier1 class=7 intf=" + i + " ep=" + ep);
                    return new int[] { i, ep };
                }
            }
        }

        // Tier 2: vendor-specific class + bulk OUT.
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface intf = device.getInterface(i);
            if (intf.getInterfaceClass() == UsbConstants.USB_CLASS_VENDOR_SPEC) {
                int ep = findBulkOutEndpoint(intf);
                if (ep >= 0) {
                    Log.d(TAG, "selectInterfaceAndEndpoint: tier2 vendor-spec intf=" + i + " ep=" + ep);
                    return new int[] { i, ep };
                }
            }
        }

        // Tier 3: 클래스 무관 bulk OUT 보유 인터페이스.
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface intf = device.getInterface(i);
            int ep = findBulkOutEndpoint(intf);
            if (ep >= 0) {
                Log.d(TAG, "selectInterfaceAndEndpoint: tier3 any-bulk intf=" + i
                        + " cls=" + intf.getInterfaceClass() + " ep=" + ep);
                return new int[] { i, ep };
            }
        }

        Log.e(TAG, "selectInterfaceAndEndpoint: no bulk OUT endpoint on any interface");
        return null;
    }

    private static int findBulkOutEndpoint(UsbInterface intf) {
        for (int j = 0; j < intf.getEndpointCount(); j++) {
            UsbEndpoint ep = intf.getEndpoint(j);
            if (ep.getDirection() == UsbConstants.USB_DIR_OUT
                    && ep.getType() == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                return j;
            }
        }
        return -1;
    }

    /**
     * 영수증 프린터 전송 채널 채택 여부를 3단계로 판정한다:
     *   STRICT    -- 어떤 인터페이스라도 USB Printer class(7)를 노출하면 채택.
     *   WHITELIST -- VID 가 알려진 영수증 프린터 제조사 목록에 포함되면 채택.
     *   RELAXED   -- 명백한 비프린터 인터페이스 클래스가 없고, 디바이스 어딘가
     *                bulk OUT 엔드포인트가 1개 이상 존재하면 채택. 윈도우 전용
     *                드라이버만 제공하면서 vendor-specific(0xFF) 인터페이스만
     *                노출하는 ESC/POS 프린터를 커버한다.
     *
     * 라벨 프린터는 상위 단계의 {@link #isLabelPrinter} 에서 이미 걸러진다 —
     * 이 메서드는 그 필터를 통과한 디바이스만 받는다고 가정한다.
     */
    private boolean isReceiptCandidate(UsbDevice d) {
        if (d == null) return false;

        // STRICT
        for (int i = 0; i < d.getInterfaceCount(); i++) {
            if (d.getInterface(i).getInterfaceClass() == UsbConstants.USB_CLASS_PRINTER) {
                Log.d(TAG, "isReceiptCandidate: accept STRICT (class=7) " + d.getDeviceName());
                return true;
            }
        }

        // WHITELIST
        if (isWhitelistedReceiptVendor(d.getVendorId())) {
            Log.d(TAG, "isReceiptCandidate: accept WHITELIST vid=0x"
                    + Integer.toHexString(d.getVendorId()) + " " + d.getDeviceName());
            return true;
        }

        // RELAXED
        if (hasBlockedNonPrinterClass(d)) {
            Log.d(TAG, "isReceiptCandidate: reject RELAXED (non-printer class) "
                    + d.getDeviceName());
            return false;
        }
        if (!hasAnyBulkOut(d)) {
            Log.d(TAG, "isReceiptCandidate: reject RELAXED (no bulk OUT) "
                    + d.getDeviceName());
            return false;
        }
        Log.i(TAG, "isReceiptCandidate: accept RELAXED vid=0x"
                + Integer.toHexString(d.getVendorId())
                + " pid=0x" + Integer.toHexString(d.getProductId())
                + " " + d.getDeviceName());
        return true;
    }

    private static boolean isWhitelistedReceiptVendor(int vid) {
        // 현장에서 새로 식별되는 영수증 프린터 제조사 VID 가 있을 때마다 추가.
        return vid == VID_POSBANK;
    }

    // 비프린터 디바이스임이 거의 확실한 인터페이스 클래스 목록. 어떤
    // 인터페이스라도 이 중 하나를 노출하면 RELAXED 경로에서 즉시 거부한다.
    // class 7(Printer)은 의도적으로 빠져 있다 — 그건 STRICT 단계의 채택
    // 시그널이고 이 리스트를 우회한다.
    private static final int[] BLOCKED_NON_PRINTER_CLASSES = new int[] {
            UsbConstants.USB_CLASS_AUDIO,                // 1
            UsbConstants.USB_CLASS_HID,                  // 3
            UsbConstants.USB_CLASS_MASS_STORAGE,         // 8
            UsbConstants.USB_CLASS_HUB,                  // 9
            UsbConstants.USB_CLASS_CSCID,                // 11 smart card
            UsbConstants.USB_CLASS_VIDEO,                // 14
            UsbConstants.USB_CLASS_WIRELESS_CONTROLLER,  // 224
    };

    private static boolean hasBlockedNonPrinterClass(UsbDevice d) {
        for (int i = 0; i < d.getInterfaceCount(); i++) {
            int cls = d.getInterface(i).getInterfaceClass();
            for (int blocked : BLOCKED_NON_PRINTER_CLASSES) {
                if (cls == blocked) return true;
            }
        }
        return false;
    }

    private static boolean hasAnyBulkOut(UsbDevice d) {
        for (int i = 0; i < d.getInterfaceCount(); i++) {
            if (findBulkOutEndpoint(d.getInterface(i)) >= 0) return true;
        }
        return false;
    }

    /**
     * 라벨 프린터(LabelPrinter.java 를 통해 autoreplyprint.aar 가 담당)는
     * 영수증 프린터 탐색에서 제외해야 한다. VID/PID 목록은 LabelPrinter 가
     * 지원하는 모델 그대로다.
     */
    private boolean isLabelPrinter(UsbDevice d) {
        if (d == null) return false;
        int vid = d.getVendorId();
        int pid = d.getProductId();
        return (vid == 0x4B43 && (pid == 0x3538 || pid == 0x3830))
                || (vid == 0x0FE6 && pid == 0x811E)
                || (vid == 0x067B && pid == 0x2303);
    }

    private void logDeviceDescriptor(UsbDevice d) {
        StringBuilder sb = new StringBuilder();
        sb.append("device=").append(d.getDeviceName())
                .append(" vid=0x").append(Integer.toHexString(d.getVendorId()))
                .append(" pid=0x").append(Integer.toHexString(d.getProductId()))
                .append(" cls=").append(d.getDeviceClass())
                .append(" intfCount=").append(d.getInterfaceCount());
        for (int i = 0; i < d.getInterfaceCount(); i++) {
            UsbInterface intf = d.getInterface(i);
            sb.append(" [intf").append(i)
                    .append(" cls=").append(intf.getInterfaceClass())
                    .append(" sub=").append(intf.getInterfaceSubclass())
                    .append(" proto=").append(intf.getInterfaceProtocol())
                    .append("]");
        }
        Log.d(TAG, sb.toString());
    }
}
