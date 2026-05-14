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
 * Generic USB ESC/POS receipt printer transport.
 * <p>
 * Replaces the Posbank PrinterManager wrapper (PrintUtil) with a thin layer over
 * Android's standard UsbManager + UsbDeviceConnection.bulkTransfer. The Dart side
 * builds the entire ESC/POS byte stream (already CP949-encoded) via
 * ReceiptEscPosBuilder.toBytesCp949(); this class only handles discovery,
 * permission, interface/endpoint selection, and bulk-out writes.
 * <p>
 * Threading: all public mutating methods are synchronized. Writes must run on
 * NativeMethodHandler.receiptPrintExecutor (single-thread serialization).
 */
public class UsbReceiptPrinter {

    private static final String TAG = "UsbReceiptPrinter";

    public static final String ACTION_USB_PERMISSION =
            "co.kr.waldlust.order.receive.RECEIPT_USB_PERMISSION";

    // Posbank VID — kept as an explicit hint when interface class is not 7 (printer).
    private static final int VID_POSBANK = 0x1552;

    // bulkTransfer chunking: older Android builds cap a single bulkTransfer at 16 KiB.
    // Stay well under that to be safe. Receipts with logo bitmap can be 30-80 KiB.
    private static final int CHUNK_SIZE = 8 * 1024;
    private static final int CHUNK_TIMEOUT_MS = 5000;

    private final Context appContext;
    private final UsbManager usbManager;

    private final Object lock = new Object();

    // Currently open transport state. null until a device is opened.
    private UsbDevice openDevice;
    private UsbDeviceConnection connection;
    private UsbInterface claimedInterface;
    private UsbEndpoint bulkOut;

    public UsbReceiptPrinter(Context context) {
        this.appContext = context.getApplicationContext();
        this.usbManager = (UsbManager) appContext.getSystemService(Context.USB_SERVICE);
    }

    /**
     * Enumerate connected USB devices, skip label printers, and try to open the
     * first matching receipt-printer candidate. If permission is missing, fires
     * a system permission dialog and returns; MainActivity's broadcast receiver
     * will call {@link #onPermissionGranted(UsbDevice)} on user approval.
     * <p>
     * Idempotent: reuses an already-open connection to the same device; closes
     * and reopens if the candidate has changed.
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

            // Either nothing open, or a different device — close and (re)open.
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
     * Called from MainActivity's USB permission BroadcastReceiver after the
     * user grants access to a device.
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
     * Called from MainActivity when a USB device is physically detached.
     * Closes the connection if it matches the currently open device.
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
     * Write the given ESC/POS byte stream to the receipt printer in 8 KiB chunks.
     * Returns false on any chunk failure (and tears down the connection so the
     * next discover() can recover).
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

    // ---- internals -------------------------------------------------------

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
            // Android 12+ requires FLAG_MUTABLE so the system can add the permission-grant extra.
            flags = PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT;
        } else {
            flags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent permissionIntent = PendingIntent.getBroadcast(
                appContext, 0, new Intent(ACTION_USB_PERMISSION), flags);
        usbManager.requestPermission(device, permissionIntent);
    }

    /**
     * Prefer USB Printer class interface (class 7, subclass 1). Fall back to
     * the device's first interface for vendor-specific ESC/POS printers. Within
     * the chosen interface, pick the first bulk OUT endpoint.
     *
     * @return int[]{ interfaceIndex, endpointIndex } or null when nothing matches.
     */
    private int[] selectInterfaceAndEndpoint(UsbDevice device) {
        if (device == null || device.getInterfaceCount() == 0) return null;

        int chosenIntf = -1;
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            UsbInterface intf = device.getInterface(i);
            if (intf.getInterfaceClass() == UsbConstants.USB_CLASS_PRINTER
                    && intf.getInterfaceSubclass() == 1
                    && (intf.getInterfaceProtocol() == 1
                            || intf.getInterfaceProtocol() == 2
                            || intf.getInterfaceProtocol() == 3)) {
                chosenIntf = i;
                break;
            }
        }
        if (chosenIntf < 0) chosenIntf = 0; // fallback

        UsbInterface intf = device.getInterface(chosenIntf);
        for (int j = 0; j < intf.getEndpointCount(); j++) {
            UsbEndpoint ep = intf.getEndpoint(j);
            if (ep.getDirection() == UsbConstants.USB_DIR_OUT
                    && ep.getType() == UsbConstants.USB_ENDPOINT_XFER_BULK) {
                return new int[] { chosenIntf, j };
            }
        }
        return null;
    }

    private boolean isReceiptCandidate(UsbDevice d) {
        if (d == null) return false;
        if (d.getVendorId() == VID_POSBANK) return true;
        for (int i = 0; i < d.getInterfaceCount(); i++) {
            if (d.getInterface(i).getInterfaceClass() == UsbConstants.USB_CLASS_PRINTER) {
                return true;
            }
        }
        return false;
    }

    /**
     * Label printers (handled by autoreplyprint.aar via LabelPrinter.java) must
     * be excluded from receipt-printer discovery. VID/PID list mirrors
     * LabelPrinter's supported devices.
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
