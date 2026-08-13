package co.kr.waldlust.order.receive.util.print;

import android.content.Context;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.util.Log;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import co.kr.waldlust.order.receive.MainActivity;

/**
 * Android USB Host API 로 라벨 프린터를 <b>직접</b> 제어하는 드라이버.
 *
 * <h3>왜 필요한가 — Caysn SDK 로는 2대를 구분할 수 없다</h3>
 * RXLA-561 은 USB serial 을 보고하지 않고({@code product_name=Virtual PRN},
 * {@code serial_number=null}), 벤더 유틸의 SYSTEM NAME/SERIAL 은 펌웨어 내부 값이라
 * USB 디스크립터에 안 실린다(전원 재인가 후에도 불변, 2026-08-13 실측). 따라서
 * {@code CP_Port_OpenUsb} 가 받는 포트명 4형식이 두 대에서 전부 같은 문자열이 되고,
 * SDK 내부 {@code NZUSBClientIO.Open} 은 첫 매칭에서 즉시 반환해 2번 장치에 도달할
 * 코드 경로가 없다. 같은 이름으로 두 번 열면 같은 장치를 force-claim 해 <b>기존 연결이
 * 죽는다</b>(3중 교차 검증 완료).
 *
 * <p>반면 USB Host API 는 {@link UsbDevice} <b>객체</b>로 장치를 지목하므로 serial 이
 * 없어도 두 대가 자연히 갈린다. Gate A 는 하드웨어 한계가 아니라 SDK 포트명 문법의
 * 한계였다.
 *
 * <h3>장치 식별 키 = USB 버스 번호</h3>
 * {@code /dev/bus/usb/BBB/DDD} 의 <b>device 번호(DDD)는 재열거마다 바뀐다</b>
 * (실측: 002→003→005). 게다가 전원 재인가 시 {@code getDeviceList()} 순회 순서까지
 * 뒤집힌다. 반면 <b>버스 번호(BBB)는 물리 포트에 대응해 안정적</b>이었다(003/005 유지).
 * 그래서 매핑 키로 버스 번호를 쓴다 — 케이블을 다른 포트로 옮기면 재지정이 필요하고,
 * 그건 설정 화면의 "이 프린터에 테스트 출력" 으로 확인하면 된다.
 *
 * <h3>프로토콜</h3>
 * USB Printer Class(7), bulk OUT/IN. 명령셋은 TSPL. 자세한 status 비콘 포맷과
 * paper-state machine 은 2026-05 USB Direct PoC 에서 역공학된 값을 따른다.
 */
public class UsbLabelDriver {
    private static final String TAG = "UsbLabelDriver";

    /** {@link LabelPrinter} 화이트리스트와 동일 유지. */
    private static final int[][] SUPPORTED_IDS = {
            {0x4B43, 0x3538}, // Caysn D2
            {0x4B43, 0x3830}, // Caysn D3
            {0x0FE6, 0x811E}, // REXOD RXLA-561
    };

    private static final int TRANSFER_TIMEOUT_MS = 5000;

    private final UsbDevice device;
    private UsbDeviceConnection connection;
    private UsbInterface iface;
    private UsbEndpoint endpointOut;
    private UsbEndpoint endpointIn;

    public UsbLabelDriver(UsbDevice device) {
        this.device = device;
    }

    // ── 장치 열거 ────────────────────────────────────────────────────────────

    public static boolean isSupported(UsbDevice d) {
        for (int[] id : SUPPORTED_IDS) {
            if (d.getVendorId() == id[0] && d.getProductId() == id[1]) {
                return true;
            }
        }
        return false;
    }

    /**
     * 연결된 라벨 프린터 전부. <b>버스 번호 오름차순으로 정렬</b>해서 돌려준다 —
     * {@code getDeviceList()} 는 HashMap 이라 순서가 비결정적이고 전원 재인가 시
     * 실제로 뒤집히는 것을 관측했다. 정렬해야 호출부가 안정적인 순서를 본다.
     */
    public static List<UsbDevice> findDevices(Context ctx) {
        final List<UsbDevice> found = new ArrayList<>();
        UsbManager um = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        if (um == null) return found;
        for (UsbDevice d : um.getDeviceList().values()) {
            if (isSupported(d)) found.add(d);
        }
        // Comparator 대신 삽입 정렬 — 항목이 2~3개라 의존성 추가할 이유가 없다.
        for (int i = 1; i < found.size(); i++) {
            UsbDevice cur = found.get(i);
            int j = i - 1;
            while (j >= 0 && busNumberOf(found.get(j)) > busNumberOf(cur)) {
                found.set(j + 1, found.get(j));
                j--;
            }
            found.set(j + 1, cur);
        }
        return found;
    }

    /**
     * {@code /dev/bus/usb/003/005} → {@code 3}. 파싱 실패 시 -1.
     *
     * <p>이 값이 장치 매핑 키다 — device 번호와 달리 재열거에도 안 바뀐다.
     */
    public static int busNumberOf(UsbDevice d) {
        try {
            final String name = d.getDeviceName(); // /dev/bus/usb/BBB/DDD
            final String[] parts = name.split("/");
            if (parts.length >= 2) {
                return Integer.parseInt(parts[parts.length - 2]);
            }
        } catch (Throwable ignored) {
        }
        return -1;
    }

    public UsbDevice getDevice() {
        return device;
    }

    public int getBusNumber() {
        return busNumberOf(device);
    }

    // ── 연결 ────────────────────────────────────────────────────────────────

    /**
     * 프린터 인터페이스를 찾아 claim 하고 bulk 엔드포인트를 잡는다.
     *
     * <p>USB Printer Class(7) 인터페이스를 우선 찾고, 없으면 bulk IN/OUT 을 가진
     * 아무 인터페이스나 쓴다 — 일부 OEM 보드가 vendor-specific class 로 올라온다.
     *
     * @return 성공 여부. 실패 사유는 로그에 남는다.
     */
    public boolean open(Context ctx) {
        UsbManager um = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        if (um == null) {
            log("open 실패: UsbManager 없음");
            return false;
        }
        if (!um.hasPermission(device)) {
            log("open 실패: 권한 없음 " + device.getDeviceName());
            return false;
        }

        UsbInterface chosen = null;
        UsbEndpoint out = null;
        UsbEndpoint in = null;
        for (int i = 0; i < device.getInterfaceCount(); i++) {
            final UsbInterface candidate = device.getInterface(i);
            UsbEndpoint cOut = null;
            UsbEndpoint cIn = null;
            for (int e = 0; e < candidate.getEndpointCount(); e++) {
                final UsbEndpoint ep = candidate.getEndpoint(e);
                if (ep.getType() != UsbConstants.USB_ENDPOINT_XFER_BULK) continue;
                if (ep.getDirection() == UsbConstants.USB_DIR_OUT && cOut == null) {
                    cOut = ep;
                } else if (ep.getDirection() == UsbConstants.USB_DIR_IN && cIn == null) {
                    cIn = ep;
                }
            }
            if (cOut == null) continue;
            final boolean isPrinterClass =
                    candidate.getInterfaceClass() == UsbConstants.USB_CLASS_PRINTER;
            if (isPrinterClass || chosen == null) {
                chosen = candidate;
                out = cOut;
                in = cIn;
                if (isPrinterClass) break; // 프린터 클래스면 더 볼 것 없다
            }
        }
        if (chosen == null || out == null) {
            log("open 실패: bulk OUT 엔드포인트를 못 찾음 " + device.getDeviceName());
            return false;
        }

        final UsbDeviceConnection conn = um.openDevice(device);
        if (conn == null) {
            log("open 실패: openDevice null " + device.getDeviceName());
            return false;
        }
        // force=true — 커널 usblp 가 물고 있을 수 있다.
        if (!conn.claimInterface(chosen, true)) {
            log("open 실패: claimInterface " + device.getDeviceName());
            conn.close();
            return false;
        }

        this.connection = conn;
        this.iface = chosen;
        this.endpointOut = out;
        this.endpointIn = in;
        log("open 성공 " + describe());
        return true;
    }

    public boolean isOpen() {
        return connection != null && endpointOut != null;
    }

    public void close() {
        if (connection != null) {
            try {
                if (iface != null) connection.releaseInterface(iface);
            } catch (Throwable ignored) {
            }
            try {
                connection.close();
            } catch (Throwable ignored) {
            }
        }
        connection = null;
        iface = null;
        endpointOut = null;
        endpointIn = null;
    }

    public String describe() {
        return "bus=" + getBusNumber() + " node=" + device.getDeviceName()
                + " if=" + (iface == null ? "-" : iface.getInterfaceClass())
                + " out=" + (endpointOut == null ? "-" : endpointOut.getAddress())
                + " in=" + (endpointIn == null ? "-" : endpointIn.getAddress());
    }

    // ── 전송 ────────────────────────────────────────────────────────────────

    /**
     * bulk OUT 으로 raw 바이트를 보낸다. 엔드포인트 maxPacketSize 배수로 쪼개지 않고
     * 큰 버퍼를 한 번에 넘기면 일부 커널에서 잘리므로 청크로 나눈다.
     *
     * @return 전부 보냈으면 true
     */
    public boolean write(byte[] data) {
        if (!isOpen()) return false;
        final int chunk = 4096;
        int sent = 0;
        while (sent < data.length) {
            final int len = Math.min(chunk, data.length - sent);
            final byte[] buf = new byte[len];
            System.arraycopy(data, sent, buf, 0, len);
            final int n = connection.bulkTransfer(
                    endpointOut, buf, len, TRANSFER_TIMEOUT_MS);
            if (n < 0) {
                log("write 실패 at " + sent + "/" + data.length);
                return false;
            }
            sent += n;
        }
        return true;
    }

    /** TSPL 명령 문자열 전송. 개행은 CRLF 로 정규화한다. */
    public boolean sendTspl(String command) {
        final String normalized = command.endsWith("\r\n") ? command : command + "\r\n";
        return write(normalized.getBytes(StandardCharsets.US_ASCII));
    }

    /**
     * bulk IN 에서 한 패킷 읽는다. 응답이 없으면 null.
     *
     * <p>펌웨어가 ~2초 주기로 status 비콘을 자발적으로 보내므로, 이 read 는
     * 명령 ACK 와 비콘을 섞어서 받는다. 호출부가 헤더로 구분해야 한다.
     */
    public byte[] read(int timeoutMs) {
        if (!isOpen() || endpointIn == null) return null;
        final byte[] buf = new byte[64];
        final int n = connection.bulkTransfer(endpointIn, buf, buf.length, timeoutMs);
        if (n <= 0) return null;
        final byte[] out = new byte[n];
        System.arraycopy(buf, 0, out, 0, n);
        return out;
    }

    // ── 진단 ────────────────────────────────────────────────────────────────

    /**
     * 연결된 라벨 프린터 <b>각각</b>에 서로 다른 내용의 TSPL 텍스트 라벨을 1장씩 인쇄한다.
     *
     * <p>USB Direct 로 두 대를 독립 제어할 수 있는지 실증하는 것이 목적이다.
     * 라벨 이미지(BITMAP) 파이프라인 이식 전에 <b>지목이 되는지부터</b> 가른다 —
     * 여기서 두 기계가 각각 자기 번호를 뽑으면 경로 B 전체가 성립한다.
     *
     * <p>Caysn 운영 핸들과 같은 장치를 두고 다투게 되므로 <b>개발자 옵션 전용</b>이며,
     * 호출 전에 {@link LabelPrinter#close()} 로 SDK 쪽 포트를 닫는다.
     */
    public static String probeDirectTwoDevices(MainActivity activity) {
        final StringBuilder out = new StringBuilder();
        log("===== USB Direct 2대 진단 시작 =====");

        // SDK 가 잡고 있는 포트를 먼저 놓아준다. 같은 장치를 동시에 claim 하면
        // 서로를 빼앗아 결과가 오염된다(Caysn 이중 open 실험에서 확인한 현상).
        try {
            LabelPrinter.close();
            log("Caysn 포트 close 완료 (충돌 방지)");
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }

        UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";

        final List<UsbDevice> devices = findDevices(activity);
        log("발견 " + devices.size() + "대");
        out.append("발견 ").append(devices.size()).append("대\n");
        if (devices.isEmpty()) return out.append("라벨 프린터 없음").toString();

        // 권한 확보 — 없으면 open 이 실패해 "지목 불가" 로 오독된다.
        int requested = 0;
        for (UsbDevice d : devices) {
            if (!um.hasPermission(d)) {
                UsbPermissionHelper.request(activity, um, d);
                requested++;
            }
        }
        if (requested > 0) {
            log("권한 요청 " + requested + "건 — 최대 8초 대기");
            for (int i = 0; i < 16; i++) {
                boolean all = true;
                for (UsbDevice d : devices) {
                    if (!um.hasPermission(d)) { all = false; break; }
                }
                if (all) break;
                try {
                    Thread.sleep(500);
                } catch (InterruptedException ie) {
                    Thread.currentThread().interrupt();
                    break;
                }
            }
        }

        int index = 0;
        for (UsbDevice d : devices) {
            index++;
            final UsbLabelDriver drv = new UsbLabelDriver(d);
            final boolean opened = drv.open(activity);
            log("장치" + index + " open=" + opened + " " + drv.describe());
            if (!opened) {
                out.append("장치").append(index).append(" (bus ")
                        .append(busNumberOf(d)).append("): open 실패\n");
                continue;
            }
            try {
                // 각 기계가 자기 번호를 뽑는다 — 어느 물리 기계인지 눈으로 대조.
                //
                // ★ SIZE/GAP 를 반드시 먼저 보낸다. 이걸 빼고 CLS+TEXT+PRINT 만
                //   보냈더니 모터 소리만 나고 용지가 안 나왔다(2026-08-13 실측) —
                //   라벨 길이를 모르면 펌웨어가 인쇄를 건너뛴다.
                //   치수는 LabelPainter 캔버스 기준: 490×600 dot @203dpi(8 dot/mm)
                //   = 61mm × 75mm.
                final String label = "USB-" + index;
                final boolean ok = drv.sendTspl(
                        "SIZE 61 mm,75 mm\r\n"
                        + "GAP 2 mm,0 mm\r\n"
                        + "DIRECTION 0\r\n"
                        + "CLS\r\n"
                        + "TEXT 40,60,\"4\",0,2,2,\"" + label + "\"\r\n"
                        + "TEXT 40,160,\"3\",0,1,1,\"bus " + busNumberOf(d) + "\"\r\n"
                        + "PRINT 1,1\r\n");
                log("장치" + index + " TSPL 전송 -> " + ok + " (라벨 '" + label + "')");
                out.append("장치").append(index).append(" (bus ")
                        .append(busNumberOf(d)).append("): 전송 ").append(ok)
                        .append(" → '").append(label).append("'\n");

                // 응답이 오는지도 본다 — 양방향이면 완료 판정에 쓸 수 있다.
                final byte[] resp = drv.read(2000);
                log("장치" + index + " 응답 " + describeBytes(resp));
            } finally {
                drv.close();
            }
            // 다음 장치로 넘어가기 전에 텀 — 두 기계가 동시에 뱉으면 어느 쪽이
            // 어느 라벨인지 눈으로 구분하기 어렵다.
            try {
                Thread.sleep(2500);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                break;
            }
        }

        out.append("\n각 기계가 자기 번호(USB-1 / USB-2)를 뽑았으면 2대 제어 성공");
        log("===== USB Direct 2대 진단 끝 =====");
        return out.toString();
    }

    private static String describeBytes(byte[] b) {
        if (b == null) return "없음";
        final StringBuilder sb = new StringBuilder(b.length + "바이트 [");
        for (int i = 0; i < b.length && i < 16; i++) {
            sb.append(String.format("%02X ", b[i]));
        }
        return sb.append(']').toString();
    }

    private static void log(String message) {
        Log.i(TAG, message);
    }
}
