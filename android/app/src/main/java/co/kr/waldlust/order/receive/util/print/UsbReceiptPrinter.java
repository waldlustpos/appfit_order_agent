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

    /**
     * Result code propagated back to Dart via PlatformException for retry/queue
     * classification in PrinterJobQueue. See lib/services/printer_transport.dart.
     */
    public enum WriteResult {
        SUCCESS,
        BUSY,            // candidate found, claim/open failed -> likely contended
        NO_DEVICE,       // no candidate enumerated, or permission missing
        TRANSPORT_ERROR  // open OK, bulkTransfer failed mid-stream
    }

    private static final String TAG = "UsbReceiptPrinter";

    public static final String ACTION_USB_PERMISSION =
            "co.kr.waldlust.order.receive.RECEIPT_USB_PERMISSION";

    // RELAXED 후보 경로에서 인터페이스 클래스가 7(Printer) 이 아닌 모델도
    // VID 만으로 영수증 프린터로 채택하기 위한 whitelist.
    //   0x1552 - Posbank
    //   0x0D28 - NXP Semiconductors (다수의 ESC/POS 프린터에 들어가는 LPC
    //            마이크로컨트롤러. D3 MINI 현장 단말 PID 0x4C59 가 이 VID.)
    private static final int VID_POSBANK = 0x1552;
    private static final int VID_NXP = 0x0D28;

    // 영수증 프린터가 절대 아니지만 bulk OUT 엔드포인트를 노출해 RELAXED 후보
    // (cls=255 + bulk OUT) 경로로 새어 들어오는 VID 의 hard blocklist. D3 MINI
    // 의 내장 LAN 포트가 ASIX AX88772B USB-Ethernet 으로 enumerate 되며 chip 이
    // 어떤 바이트든 ACK 해서 verifyConnection ESC @ 까지 통과한다 -- VID 차단이
    // 유일한 안전한 회피책.
    //   0x0B95 - ASIX Electronics (USB-to-Ethernet, AX88772/AX88179 등)
    private static final int VID_ASIX = 0x0B95;

    // bulkTransfer 청크 분할: 구버전 안드로이드는 단일 bulkTransfer 호출 한계가 16 KiB 라
    // 그 절반 수준으로 안전하게 쪼갠다. 로고 비트맵 포함 영수증은 30~80 KiB 까지 갈 수 있다.
    private static final int CHUNK_SIZE = 8 * 1024;
    private static final int CHUNK_TIMEOUT_MS = 5000;

    // ESC @ (0x1B 0x40) - "Initialize printer". 표준 ESC/POS 상태 reset no-op.
    // verifyConnection() 이 실제 물리 출력 없이 USB writability 를 검증할 때 사용.
    private static final byte[] ESC_INIT = new byte[] { 0x1B, 0x40 };
    private static final int VERIFY_TIMEOUT_MS = 500;

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
     * 가볍지만 실제 USB write 까지 확인하는 connection probe.
     * ESC @ (printer initialize, 2 bytes) 를 bulk OUT 으로 짧은 timeout 으로 보낸다.
     * 전송 실패면 connection 을 tear-down 해 다음 discover() 가 복구할 수 있게 한다.
     * <p>
     * connection 자체가 없으면 false 반환 (caller 가 놀라지 않도록). 실제 USB
     * write 성공만 true. ESC @ 는 보편적 ESC/POS reset 이라 영수증 출력물에는
     * 아무런 영향이 없다.
     * <p>
     * writeBytes 와 동일 lock 을 사용해 영수증 출력 중에는 probe 가 끼어들 수 없다.
     */
    public boolean verifyConnection() {
        synchronized (lock) {
            if (connection == null || bulkOut == null) return false;
            int sent = -1;
            try {
                sent = connection.bulkTransfer(bulkOut, ESC_INIT, ESC_INIT.length, VERIFY_TIMEOUT_MS);
            } catch (Exception e) {
                Log.w(TAG, "verifyConnection: bulkTransfer threw", e);
            }
            if (sent < 0) {
                Log.w(TAG, "verifyConnection: ESC @ probe failed (sent=" + sent + "), tearing down");
                closeLocked();
                return false;
            }
            return true;
        }
    }

    /**
     * 주어진 ESC/POS 바이트 스트림을 8 KiB 청크 단위로 영수증 프린터에 전송한다.
     * 어떤 청크라도 실패하면 false 를 반환하고 연결을 강제로 닫아, 다음
     * discover() 호출에서 복구할 수 있게 한다.
     */
    public WriteResult writeBytes(byte[] data, String jobName) {
        if (data == null || data.length == 0) return WriteResult.TRANSPORT_ERROR;

        UsbDeviceConnection conn;
        UsbEndpoint out;
        synchronized (lock) {
            if (connection == null || bulkOut == null) {
                WriteResult open = attemptOpenIfNeededLocked();
                if (open != WriteResult.SUCCESS) {
                    Log.w(TAG, "writeBytes: open required but failed=" + open
                            + " (job=" + jobName + ")");
                    return open;
                }
            }
            conn = connection;
            out = bulkOut;
        }
        if (conn == null || out == null) {
            return WriteResult.NO_DEVICE;
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
                return WriteResult.TRANSPORT_ERROR;
            }
            offset += sent;
        }
        Log.d(TAG, "writeBytes: " + data.length + " bytes sent (job=" + jobName + ")");
        return WriteResult.SUCCESS;
    }

    /**
     * Inline open attempt when writeBytes is invoked while disconnected.
     * Must be called with {@link #lock} held.
     */
    private WriteResult attemptOpenIfNeededLocked() {
        if (connection != null && bulkOut != null) return WriteResult.SUCCESS;
        if (usbManager == null) return WriteResult.NO_DEVICE;

        HashMap<String, UsbDevice> devices = usbManager.getDeviceList();
        if (devices == null || devices.isEmpty()) return WriteResult.NO_DEVICE;

        UsbDevice candidate = null;
        for (UsbDevice d : devices.values()) {
            if (isLabelPrinter(d)) continue;
            if (!isReceiptCandidate(d)) continue;
            candidate = d;
            break;
        }
        if (candidate == null) return WriteResult.NO_DEVICE;

        if (!usbManager.hasPermission(candidate)) {
            requestPermission(candidate);
            return WriteResult.NO_DEVICE;
        }

        int[] sel = selectInterfaceAndEndpoint(candidate);
        if (sel == null) return WriteResult.NO_DEVICE;

        UsbInterface intf = candidate.getInterface(sel[0]);
        UsbEndpoint ep = intf.getEndpoint(sel[1]);

        UsbDeviceConnection conn = usbManager.openDevice(candidate);
        if (conn == null) {
            Log.w(TAG, "attemptOpenIfNeededLocked: openDevice returned null for "
                    + candidate.getDeviceName());
            return WriteResult.BUSY;
        }
        if (!conn.claimInterface(intf, true)) {
            Log.w(TAG, "attemptOpenIfNeededLocked: claimInterface failed for "
                    + candidate.getDeviceName());
            conn.close();
            return WriteResult.BUSY;
        }
        this.openDevice = candidate;
        this.connection = conn;
        this.claimedInterface = intf;
        this.bulkOut = ep;
        Log.i(TAG, "attemptOpenIfNeededLocked: connected " + candidate.getDeviceName()
                + " intf=" + sel[0] + " ep=" + sel[1]);
        return WriteResult.SUCCESS;
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

        // Tier 0 (NXP composite quirk): NXP LPC 기반 ESC/POS 프린터 (VID 0x0D28)
        // 는 cosmetic 한 USB Printer Class 인터페이스 (intf 0, cls=7, proto=2)
        // 를 노출하지만 그쪽 bulk OUT 으로 보내면 데이터가 silently swallow 되고
        // 종이는 안 나온다. 실제 print pipeline 은 CDC-ACM data 인터페이스
        // (cls=10) 의 intf 2. 윈도우 측에서 동일 프린터를 가상 COM 포트로 구동
        // 하는 동작과 일치한다.
        //
        // 현장 D3 MINI (PID 0x4C59) 에서 확인됨. cls=7 을 정상적으로 사용하는
        // 다른 디바이스의 동작을 바꾸지 않도록 NXP + composite (intfCount >= 3)
        // 조건으로 제한.
        if (device.getVendorId() == VID_NXP && device.getInterfaceCount() >= 3) {
            for (int i = 0; i < device.getInterfaceCount(); i++) {
                UsbInterface intf = device.getInterface(i);
                if (intf.getInterfaceClass() == UsbConstants.USB_CLASS_CDC_DATA) {
                    int ep = findBulkOutEndpoint(intf);
                    if (ep >= 0) {
                        Log.d(TAG, "selectInterfaceAndEndpoint: tier0 NXP-composite CDC-data intf="
                                + i + " ep=" + ep);
                        return new int[] { i, ep };
                    }
                }
            }
        }

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

        // BLOCKLIST -- 어떤 단계에 도달하기도 전에 거부한다. 프린터가 아님이
        // 확정된 VID 의 "accept STRICT" 로그를 남기지 않기 위함 (D3 MINI 내장
        // ASIX USB-Ethernet 등).
        if (isBlockedReceiptVendor(d.getVendorId())) {
            Log.d(TAG, "isReceiptCandidate: reject BLOCKLIST vid=0x"
                    + Integer.toHexString(d.getVendorId()) + " " + d.getDeviceName());
            return false;
        }

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
        return vid == VID_POSBANK || vid == VID_NXP;
    }

    private static boolean isBlockedReceiptVendor(int vid) {
        // RELAXED 경로로 새어 들어오지만 영수증 프린터가 아님이 현장에서
        // 확정된 VID 만 추가한다.
        return vid == VID_ASIX;
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
     * 지원하는 고정 모델 그대로다.
     *
     * 주의: 범용 USB-Serial 브리지 칩(예: Prolific PL2303 = 0x067B:0x2303) 은
     * 절대 넣지 말 것. 외부 ESC/POS 영수증 프린터가 그런 칩으로 연결되면 여기서
     * 라벨로 오인되어 영수증 탐색에서 continue 스킵 → 외부 프린터 미탐(false
     * negative) 이 된다. (Windows _kUsbPortCandidates 와 동일 정책.)
     */
    /**
     * 라벨 프린터는 영수증 경로가 절대 건드리면 안 된다 — 여기서 빠지면
     * {@link #isReceiptCandidate} 의 STRICT 단계(USB Printer class 7)가 그대로 채택해
     * 영수증 채널이 디바이스를 선점하고, 라벨 드라이버는
     * {@code This device cannot be claimed for exclusive access.} 로 인쇄 자체를 못 한다.
     *
     * <p>★ 라벨 기종 목록은 각 드라이버가 정본이다. 여기에 조건을 복제하지 말 것 —
     * 2026-09-01 에 정확히 그 이유로 사고가 났다(G30 추가 시 드라이버 쪽 화이트리스트만
     * 갱신되고 이 메서드는 빠져서, G30 이 영수증 후보로 선점됨). Caysn/REXOD 목록도
     * 언젠가 {@link LabelPrinter} 쪽으로 위임하는 게 맞다.
     */
    private boolean isLabelPrinter(UsbDevice d) {
        if (d == null) return false;
        if (BixolonPosDriver.isG30Device(d)) return true;
        int vid = d.getVendorId();
        int pid = d.getProductId();
        return (vid == 0x4B43 && (pid == 0x3538 || pid == 0x3830))
                || (vid == 0x0FE6 && pid == 0x811E);
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
