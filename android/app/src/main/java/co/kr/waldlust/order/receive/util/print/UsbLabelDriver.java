package co.kr.waldlust.order.receive.util.print;

import android.content.Context;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.hardware.usb.UsbConstants;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbDeviceConnection;
import android.hardware.usb.UsbEndpoint;
import android.hardware.usb.UsbInterface;
import android.hardware.usb.UsbManager;
import android.util.Log;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
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

    /**
     * TSPL {@code BITMAP} 의 비트 극성. 스펙상 <b>비트 0 = 검정(인쇄)</b>, 1 = 흰색으로
     * 일반적인 감각과 반대다.
     *
     * <p><b>2026-08-13 RXLA-561 실측 확정</b> — 판별 카드
     * ({@link #polarityCardCommands()})에서 왼쪽 블록(전 비트 0)이 검게 인쇄됐다.
     * 스펙과 일치하므로 이 값을 뒤집을 일은 없어야 하지만, 다른 기종을 붙일 때는
     * 카드를 한 장 뽑아 다시 확인할 것.
     */
    public static final boolean TSPL_ZERO_IS_BLACK = true;

    /**
     * 이 휘도 미만을 검정으로 본다.
     *
     * <p>이 값이 <b>획 굵기를 좌우한다</b>. LabelPainter 는 안티에일리어싱으로 글자
     * 가장자리를 회색으로 렌더하는데, 임계값이 낮으면 그 회색이 전부 흰색으로 버려져
     * 획이 가늘어진다. Caysn 의 {@code CP_ImageBinarizationMethod_Thresholding}
     * 내부 임계값은 공개돼 있지 않아 실측으로만 맞출 수 있었다.
     *
     * <p><b>232 = 2026-08-13 실기기 확정.</b> PoC 기본값 128 로 뽑았더니 Caysn
     * 출력물보다 글자가 눈에 띄게 얇았다. 128/176/216 → 216 선택(끝값이라 재확인),
     * 216/232/244 → <b>232 선택</b>. 즉 Caysn 은 128 보다 훨씬 관대한 임계값을
     * 쓰고 있었다는 뜻이다.
     *
     * <p>⚠️ 이 값을 더 올리면 QR 모듈까지 굵어져 모듈 사이 여백이 메워진다.
     * 바꿀 때는 획 굵기만 보지 말고 <b>QR 스캔을 함께</b> 확인할 것.
     * 후보 비교는 {@code probeDirectBitmapTuning} 으로 재빌드 없이 돌릴 수 있다.
     */
    private static final int LUMA_THRESHOLD = 232;

    /**
     * TSPL {@code DENSITY} 기본값(0~15). -1 이면 명령을 보내지 않고 펌웨어 기본값에
     * 맡긴다 — Caysn 경로도 {@code CP_Pos_ResetPrinter} 뒤에 농도를 따로 지정하지
     * 않으므로, 기본은 "안 건드림" 이 두 경로의 조건을 같게 만든다.
     */
    private static final int DEFAULT_DENSITY = -1;

    /**
     * 라벨 <b>용지</b>의 물리 치수(mm). 이미지 크기에서 유도하지 않는다 — SIZE 는
     * 펌웨어에 "얼마나 피드할지" 를 알려주는 매체 속성이라, 이미지가 작아도 매체
     * 크기여야 갭 검출이 맞는다.
     *
     * <p>LabelPainter 캔버스 490x600 dot @203dpi(8 dot/mm) = 61.25mm x 75mm 이고,
     * 61 x 75 로 2026-08-13 실기기 정상 출력을 확인했다. 용지를 바꾸면 여기도 바꿀 것.
     */
    private static final int MEDIA_WIDTH_MM = 61;
    private static final int MEDIA_HEIGHT_MM = 75;
    private static final int GAP_MM = 2;

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

    // ── TSPL BITMAP ─────────────────────────────────────────────────────────

    /**
     * 라벨 한 장의 공통 머리말. <b>SIZE/GAP 를 반드시 먼저 보내야 인쇄된다</b> —
     * 이걸 빼고 {@code CLS+TEXT+PRINT} 만 보내면 모터 소리만 나고 용지가 안 나온다
     * (2026-08-13 실측).
     */
    private static String preamble() {
        return "SIZE " + MEDIA_WIDTH_MM + " mm," + MEDIA_HEIGHT_MM + " mm\r\n"
                + "GAP " + GAP_MM + " mm,0 mm\r\n"
                + "DIRECTION 0\r\n"
                + "CLS\r\n";
    }

    /**
     * {@link Bitmap} 을 TSPL {@code BITMAP} 이 받는 1bpp 패킹으로 변환한다.
     * 행 stride 는 {@code ceil(width/8)} 바이트, 각 바이트는 MSB 가 왼쪽 dot.
     *
     * <p><b>패딩 비트 주의.</b> 폭이 8의 배수가 아니면 오른쪽에 남는 dot 이 생긴다
     * (490 dot → 62바이트 = 496 dot, 6 dot 잉여). 이 비트를 0 으로 두면
     * {@code zeroIsBlack} 극성에서 라벨 오른쪽 끝에 6 dot 짜리 검은 띠가 인쇄된다.
     * 그래서 버퍼 전체를 <b>흰색 값으로 먼저 채운 뒤</b> 실제 픽셀만 덮어쓴다.
     *
     * @param zeroIsBlack true 면 검정 픽셀을 비트 0 으로 (TSPL 스펙),
     *                    false 면 비트 1 로 (반전 극성).
     */
    public static byte[] packMonochrome(Bitmap src, boolean zeroIsBlack) {
        return packMonochrome(src, zeroIsBlack, LUMA_THRESHOLD);
    }

    /** @param threshold 이 휘도 <b>미만</b>을 검정으로 본다. 클수록 획이 굵어진다. */
    public static byte[] packMonochrome(Bitmap src, boolean zeroIsBlack,
                                        int threshold) {
        final int w = src.getWidth();
        final int h = src.getHeight();
        final int widthBytes = (w + 7) / 8;
        final byte[] out = new byte[widthBytes * h];
        Arrays.fill(out, (byte) (zeroIsBlack ? 0xFF : 0x00));

        final int[] row = new int[w];
        for (int y = 0; y < h; y++) {
            src.getPixels(row, 0, w, 0, y, w, 1);
            final int base = y * widthBytes;
            for (int x = 0; x < w; x++) {
                final int p = row[x];
                final int a = (p >>> 24) & 0xFF;
                final int r = (p >>> 16) & 0xFF;
                final int g = (p >>> 8) & 0xFF;
                final int b = p & 0xFF;
                // 투명 픽셀은 흰색으로 본다. LabelPainter 는 흰 배경을 깔지만
                // (label_painter.dart 의 drawRect(Colors.white)), 배경 없는 비트맵이
                // 들어와도 라벨이 통째로 검게 뒤집히지 않게 하는 방어다.
                final boolean black = a >= 128
                        && (r * 299 + g * 587 + b * 114) / 1000 < threshold;
                final int mask = 0x80 >> (x & 7);
                if (black == zeroIsBlack) {
                    out[base + (x >> 3)] &= (byte) ~mask;
                } else {
                    out[base + (x >> 3)] |= (byte) mask;
                }
            }
        }
        return out;
    }

    /**
     * {@code BITMAP x,y,widthBytes,height,mode,<raw>} 한 덩어리.
     *
     * <p>raw 구간은 <b>길이로 구분</b>된다({@code widthBytes * height} 바이트) —
     * 그래서 데이터 안에 0x0A/0x0D 가 섞여도 파서가 명령 끝으로 오해하지 않는다.
     * 대신 데이터 <b>뒤</b>에는 CRLF 를 붙여야 다음 명령이 인식된다.
     */
    private static byte[] bitmapCommand(int x, int y, int widthBytes, int height,
                                        byte[] packed) throws IOException {
        final ByteArrayOutputStream buf =
                new ByteArrayOutputStream(packed.length + 64);
        buf.write(ascii("BITMAP " + x + "," + y + "," + widthBytes + ","
                + height + ",0,"));
        buf.write(packed);
        buf.write(ascii("\r\n"));
        return buf.toByteArray();
    }

    /**
     * LabelPainter 가 만든 비트맵을 라벨 한 장으로 인쇄한다.
     *
     * <p>이것이 경로 B 의 본 인쇄 경로다 — Caysn 의
     * {@code CP_Label_PageBegin + DrawImageFromBitmap + PagePrint} 3단계를
     * TSPL 한 덩어리로 대체한다.
     *
     * @return 전송 성공 여부. <b>인쇄 완료가 아니다</b> — 완료 판정은 status 비콘
     *         기반 paper-state machine 이 붙은 뒤에 가능하다.
     */
    public boolean printLabelBitmap(Bitmap bmp, boolean zeroIsBlack) {
        return printLabelBitmap(bmp, zeroIsBlack, LUMA_THRESHOLD, DEFAULT_DENSITY);
    }

    /**
     * @param threshold 이진화 임계값(0~255). 클수록 획이 굵어진다.
     * @param density   TSPL {@code DENSITY} (0~15). 음수면 명령을 보내지 않는다.
     */
    public boolean printLabelBitmap(Bitmap bmp, boolean zeroIsBlack,
                                    int threshold, int density) {
        if (bmp == null || !isOpen()) return false;
        final int w = bmp.getWidth();
        final int h = bmp.getHeight();
        if (w <= 0 || h <= 0) return false;
        final int widthBytes = (w + 7) / 8;
        try {
            final byte[] packed = packMonochrome(bmp, zeroIsBlack, threshold);
            final ByteArrayOutputStream job =
                    new ByteArrayOutputStream(packed.length + 256);
            // DENSITY 는 SIZE/GAP 앞에 둔다 — 페이지 설정 명령 사이에 끼면 일부
            // 펌웨어가 무시한다.
            if (density >= 0) job.write(ascii("DENSITY " + density + "\r\n"));
            job.write(ascii(preamble()));
            job.write(bitmapCommand(0, 0, widthBytes, h, packed));
            job.write(ascii("PRINT 1,1\r\n"));
            final byte[] bytes = job.toByteArray();
            log("BITMAP 전송 " + w + "x" + h + " (" + widthBytes + "바이트/행, 총 "
                    + bytes.length + "바이트, 0=검정:" + zeroIsBlack
                    + ", 임계값=" + threshold
                    + ", 농도=" + (density >= 0 ? density : "기본") + ")");
            return write(bytes);
        } catch (IOException e) {
            log("BITMAP 조립 실패: " + e.getMessage());
            return false;
        }
    }

    /**
     * 비트 극성 판별 카드 한 장.
     *
     * <p>실제 라벨을 반대 극성으로 뽑으면 <b>490x600 전면이 새까맣게</b> 인쇄된다 —
     * 용지도 열도 아깝고 감열지에 부담이다. 그래서 잉크를 거의 안 쓰는 작은 블록
     * 두 개(왼쪽 = 전 비트 0, 오른쪽 = 전 비트 1)로 먼저 가른다.
     *
     * <ul>
     *   <li><b>왼쪽(0x00)이 검게</b> 나오면 → 비트 0 = 검정 (TSPL 스펙, 현재 가정)</li>
     *   <li><b>오른쪽(0xFF)이 검게</b> 나오면 → 비트 1 = 검정 → 상수를 뒤집을 것</li>
     * </ul>
     */
    private static byte[] polarityCardCommands() throws IOException {
        final int widthBytes = 6;   // 48 dot
        final int height = 96;      // 12mm
        final byte[] allZero = new byte[widthBytes * height];
        final byte[] allOne = new byte[widthBytes * height];
        Arrays.fill(allOne, (byte) 0xFF);

        final ByteArrayOutputStream job = new ByteArrayOutputStream(4096);
        job.write(ascii(preamble()));
        job.write(ascii("TEXT 24,24,\"3\",0,1,1,\"BIT POLARITY\"\r\n"));
        job.write(ascii("TEXT 24,180,\"3\",0,1,1,\"L=0x00\"\r\n"));
        job.write(ascii("TEXT 240,180,\"3\",0,1,1,\"R=0xFF\"\r\n"));
        job.write(bitmapCommand(24, 72, widthBytes, height, allZero));
        job.write(bitmapCommand(240, 72, widthBytes, height, allOne));
        job.write(ascii("TEXT 24,224,\"3\",0,1,1,\"black side = bit value\"\r\n"));
        job.write(ascii("PRINT 1,1\r\n"));
        return job.toByteArray();
    }

    private static byte[] ascii(String s) {
        return s.getBytes(StandardCharsets.US_ASCII);
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

    // ── paper-state machine (표준 ESC/POS) ──────────────────────────────────
    //
    // 완료 판정의 유일한 신호원. Caysn 의 벤더 비콘을 쓰지 않는다 — 그건
    // CP_Port_OpenUsb 가 켜 줘야만 오고, Caysn 은 첫 매칭 한 대만 열 수 있어
    // 2대 운용에서 나머지 한 대가 영영 조용하기 때문이다(2026-08-13 확정).

    /** ESC/POS 실시간 용지 센서 조회. 인쇄 중에도 즉시 처리된다. */
    private static final byte[] PAPER_QUERY = {0x10, 0x04, 0x04};

    /**
     * {@code DLE EOT 4} 응답의 peel 비트.
     *
     * <p><b>0 = 라벨이 peel 위치에 있음(아직 안 뗌)</b>, 1 = 없음.
     * 실측 전이 {@code 1E → 1A → 1E} (제출 → 도달 → 떼기), 2026-08-13.
     * Caysn 의 {@code INFO_PAPERNOFETCH} 와 같은 신호다.
     */
    private static final int PEEL_BIT = 0x04;

    /** 마지막으로 관측한 "라벨이 peel 위치에 있는가". */
    private boolean labelAtPeel;
    private boolean peelStateKnown;

    /**
     * 라벨이 peel 위치에 <b>도달</b>한 횟수(없음→있음 전이).
     *
     * <p>이 카운터가 완료 판정의 핵심이다. 절대값이 아니라 <b>증가</b>를 보는 이유는
     * edge 귀속 때문이다 — 앞 라벨을 안 뗐으면 제출 시점에 이미 "있음" 이라 내 라벨의
     * 도달을 상태값만으로는 구분할 수 없다. 펌웨어는 앞 라벨을 뗄 때까지 보류하므로
     * 실제 순서는 "떼짐(있음→없음) → 내 것 도달(없음→있음)" 이 되고, 제출 전
     * 스냅샷 대비 증가를 기다리면 자연히 내 라벨에 귀속된다.
     */
    private int arrivalCount;

    /** 폴링 1회. 상태가 바뀌면 카운터를 갱신한다. @return 조회 성공 여부 */
    public boolean pollPaperState() {
        final byte[] r = query(PAPER_QUERY, 400);
        if (r == null || r.length < 1) return false;
        final boolean present = (r[0] & PEEL_BIT) == 0;
        if (peelStateKnown && present && !labelAtPeel) {
            arrivalCount++;
        }
        labelAtPeel = present;
        peelStateKnown = true;
        return true;
    }

    public boolean isLabelAtPeel() {
        return peelStateKnown && labelAtPeel;
    }

    /**
     * 라벨 1장을 인쇄하고 <b>실제로 나왔는지</b>까지 판정한다.
     *
     * <p>반환은 {@link LabelPrinter} 의 3분류와 같은 계약이다. 이 계약은 라벨 2장
     * 인쇄 사고(852a4c4)의 재발 방지선이므로 의미를 바꾸지 말 것:
     * <ul>
     *   <li>{@code RESULT_SUCCESS} — 도달 관측</li>
     *   <li>{@code RESULT_RETRYABLE} — <b>제출 전</b> 실패. 재시도해도 중복이 안 난다</li>
     *   <li>{@code RESULT_SUBMITTED_NO_ACK} — 제출은 됐는데 확인을 못 함.
     *       <b>절대 재시도 금지</b> — 페이지가 이미 펌웨어에 있어 한 장 더 나온다</li>
     * </ul>
     *
     * <p>제출 여부의 경계가 깔끔한 것은 {@code PRINT} 명령이 job 의 <b>마지막</b>
     * 바이트이기 때문이다. 중간 청크가 실패하면 PRINT 가 도달하지 않아 인쇄가
     * 시작되지 않는다 → 전송 실패는 곧 미제출이다.
     *
     * <p><b>보류는 무한 대기한다.</b> 상한이 지났는데 peel 위치에 라벨이 있으면,
     * 그건 앞 라벨을 아직 안 뗀 것이고 펌웨어가 내 페이지를 정상적으로 붙들고 있는
     * 상태다. 러시아워의 정상 운영이지 고장이 아니므로 기다린다
     * (현행 Caysn 경로와 같은 의미).
     */
    public int printLabelAwait(Bitmap bmp, long capMs, String tag) {
        if (bmp == null || !isOpen()) return LabelPrinter.RESULT_RETRYABLE;

        // 제출 전 기준선. 여기서 한 번 폴링해 두지 않으면 첫 전이를 놓친다.
        pollPaperState();
        final int baseline = arrivalCount;
        final long t0 = System.currentTimeMillis();

        // ★ 전송이 끝나기 전에는 절대 폴링하지 말 것 — BITMAP 스트리밍 중에
        //   DLE EOT 를 끼워 넣으면 이미지 데이터로 먹혀 라벨이 깨진다.
        if (!printLabelBitmap(bmp, TSPL_ZERO_IS_BLACK)) {
            log(tag + " 전송 실패 → 재시도가능 (미제출)");
            return LabelPrinter.RESULT_RETRYABLE;
        }
        final long submitted = System.currentTimeMillis();

        long lastNotice = submitted;
        while (true) {
            if (!sleep(POLL_INTERVAL_MS)) return LabelPrinter.RESULT_SUBMITTED_NO_ACK;
            pollPaperState();
            if (arrivalCount > baseline) {
                log(tag + " 도달 (" + (System.currentTimeMillis() - t0) + "ms)");
                return LabelPrinter.RESULT_SUCCESS;
            }
            final long elapsed = System.currentTimeMillis() - submitted;
            if (elapsed < capMs) continue;

            // 상한 초과. 여기서 갈린다.
            if (isLabelAtPeel()) {
                if (System.currentTimeMillis() - lastNotice >= 60_000L) {
                    log(tag + " 보류 대기중 " + (elapsed / 1000) + "s — 앞 라벨 미회수");
                    lastNotice = System.currentTimeMillis();
                }
                continue; // 정상 보류 → 계속 기다린다
            }
            log(tag + " 무응답 (" + elapsed + "ms, peel 비어 있음) → 제출후무확인");
            return LabelPrinter.RESULT_SUBMITTED_NO_ACK;
        }
    }

    /** 폴링 주기. 실측 도달이 ~715ms 라 이 정도면 충분히 촘촘하다. */
    private static final int POLL_INTERVAL_MS = 200;

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
        awaitPermissions(activity, um, devices);

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
            if (!sleep(2500)) break;
        }

        out.append("\n각 기계가 자기 번호(USB-1 / USB-2)를 뽑았으면 2대 제어 성공");
        log("===== USB Direct 2대 진단 끝 =====");
        return out.toString();
    }

    /**
     * <b>실제 라벨 이미지</b>(LabelPainter PNG)를 TSPL BITMAP 으로 각 프린터에 인쇄한다.
     *
     * <p>{@link #probeDirectTwoDevices} 가 "지목이 되는가" 를 갈랐다면, 이 프로브는
     * "운영 라벨을 그대로 뽑을 수 있는가" 를 가른다. 순서:
     *
     * <ol>
     *   <li><b>극성 판별 카드</b> 1장 (장치1) — 비트 0/1 중 어느 쪽이 검정인지 확정</li>
     *   <li>장치마다 <b>실제 라벨</b> 1장 — {@link #TSPL_ZERO_IS_BLACK} 가정으로 인쇄</li>
     * </ol>
     *
     * <p>1번 카드가 "오른쪽이 검정" 으로 나오면 2번 라벨들은 전면 반전(새까맣게)되어
     * 나온다. 그때는 {@link #TSPL_ZERO_IS_BLACK} 를 뒤집고 한 번 더 돌리면 된다 —
     * 한 번의 왕복으로 극성과 파이프라인을 둘 다 확인하려는 배치다.
     *
     * <p>펌웨어는 앞 라벨을 떼지 않으면 다음 인쇄를 보류하므로(정상 동작), 같은 장치에
     * 두 장을 보낼 때는 사이에 떼기 시간을 준다.
     */
    public static String probeDirectBitmap(MainActivity activity, byte[] pngBytes) {
        final StringBuilder out = new StringBuilder();
        log("===== USB Direct BITMAP 진단 시작 =====");

        if (pngBytes == null || pngBytes.length == 0) {
            return "라벨 이미지가 비어 있습니다.";
        }
        final Bitmap bmp = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.length);
        if (bmp == null) return "라벨 이미지 디코드 실패";
        log("라벨 이미지 " + bmp.getWidth() + "x" + bmp.getHeight()
                + " (" + pngBytes.length + "바이트 PNG)");

        // Caysn 이 잡고 있는 포트를 놓아준다 — 같은 장치를 동시에 claim 하면 서로를
        // 빼앗아 결과가 오염된다.
        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }

        final UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";

        final List<UsbDevice> devices = findDevices(activity);
        out.append("발견 ").append(devices.size()).append("대\n");
        if (devices.isEmpty()) return out.append("라벨 프린터 없음").toString();
        awaitPermissions(activity, um, devices);

        // 전부 열어 두고 시작한다 — 열고 닫기를 반복하지 않는 것이 운영 레지스트리의
        // 최종 형태이기도 하고, 중간에 claim 을 놓으면 커널 usblp 가 다시 물 수 있다.
        final List<UsbLabelDriver> opened = new ArrayList<>();
        for (UsbDevice d : devices) {
            final UsbLabelDriver drv = new UsbLabelDriver(d);
            if (drv.open(activity)) {
                opened.add(drv);
            } else {
                out.append("bus ").append(busNumberOf(d)).append(": open 실패\n");
            }
        }
        if (opened.isEmpty()) return out.append("열 수 있는 장치 없음").toString();

        try {
            // ① 극성 판별 카드 — 장치1 에만.
            final UsbLabelDriver first = opened.get(0);
            try {
                final boolean ok = first.write(polarityCardCommands());
                log("극성 카드 전송 -> " + ok + " (bus " + first.getBusNumber() + ")");
                out.append("① 극성 카드 (bus ").append(first.getBusNumber())
                        .append("): 전송 ").append(ok).append('\n');
            } catch (IOException e) {
                out.append("① 극성 카드 조립 실패: ").append(e.getMessage()).append('\n');
            }
            log("극성 카드를 떼어 주세요 — 10초 후 실제 라벨을 보냅니다");
            sleep(10_000);

            // ② 실제 라벨 — 장치마다 1장.
            int index = 0;
            for (UsbLabelDriver drv : opened) {
                index++;
                final boolean ok = drv.printLabelBitmap(bmp, TSPL_ZERO_IS_BLACK);
                out.append("② 라벨 ").append(index).append(" (bus ")
                        .append(drv.getBusNumber()).append("): 전송 ").append(ok)
                        .append('\n');
                // 비콘이 오는지도 함께 본다. 장치1 만 응답이 없는 비대칭이 관측된
                // 상태라(2026-08-13), 같은 조건에서 재현되는지 확인할 관찰점이다.
                final byte[] resp = drv.read(3000);
                log("장치" + index + " (bus " + drv.getBusNumber() + ") 응답 "
                        + describeBytes(resp));
                out.append("   응답 ").append(describeBytes(resp)).append('\n');
                if (index < opened.size()) sleep(2500);
            }
        } finally {
            for (UsbLabelDriver drv : opened) drv.close();
        }

        out.append("\n카드의 검은 블록이 왼쪽(L=0x00)이면 극성 정상.\n")
                .append("오른쪽(R=0xFF)이 검으면 라벨이 반전되어 나옵니다 — 보고해 주세요.");
        log("===== USB Direct BITMAP 진단 끝 =====");
        return out.toString();
    }

    /**
     * 같은 라벨을 <b>이진화 임계값만 바꿔가며</b> 한 기계에서 연속으로 뽑는다.
     *
     * <p>USB Direct 로 옮긴 라벨이 Caysn 출력물보다 "글자가 얇다" 는 관찰
     * (2026-08-13)을 좁히기 위한 프로브다. 얇아짐은 농도가 아니라 이진화 축의
     * 증상이다 — LabelPainter 가 글자 가장자리를 안티에일리어싱 회색으로 렌더하는데,
     * 임계값 128 은 "50% 이상 덮인 픽셀만 검정" 이라 그 회색을 전부 버린다.
     * 임계값을 올리면 덜 덮인 가장자리까지 살아나 획이 굵어진다.
     *
     * <p><b>반드시 한 기계에서만</b> 뽑는다. 두 기계에 나눠 뽑으면 헤드 편차가
     * 임계값 효과와 섞여 비교가 무의미해진다.
     *
     * @param pngs       조합마다 하나씩. 어떤 조합인지 라벨 안(memo)에 박혀 있어야
     *                   인쇄물만 보고 고를 수 있다.
     * @param thresholds {@code pngs} 와 같은 길이. 조합별 이진화 임계값.
     * @param densities  {@code pngs} 와 같은 길이. 음수면 농도 명령 생략.
     */
    public static String probeDirectBitmapTuning(MainActivity activity,
                                                 List<byte[]> pngs,
                                                 int[] thresholds,
                                                 int[] densities) {
        log("===== USB Direct BITMAP 튜닝 시작 =====");
        if (pngs == null || pngs.isEmpty()) return "튜닝 이미지가 비어 있습니다.";
        if (thresholds == null || densities == null
                || thresholds.length != pngs.size()
                || densities.length != pngs.size()) {
            return "튜닝 파라미터 길이 불일치 (이미지 " + pngs.size() + ")";
        }

        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }

        final UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";
        final List<UsbDevice> devices = findDevices(activity);
        if (devices.isEmpty()) return "라벨 프린터 없음";
        awaitPermissions(activity, um, devices);

        final UsbLabelDriver drv = new UsbLabelDriver(devices.get(0));
        if (!drv.open(activity)) return "장치 open 실패 (bus " + busNumberOf(devices.get(0)) + ")";

        final StringBuilder out = new StringBuilder();
        out.append("bus ").append(drv.getBusNumber()).append(" 에 ")
                .append(pngs.size()).append("장 인쇄\n");
        try {
            for (int i = 0; i < pngs.size(); i++) {
                final byte[] png = pngs.get(i);
                final Bitmap bmp = (png == null || png.length == 0)
                        ? null : BitmapFactory.decodeByteArray(png, 0, png.length);
                if (bmp == null) {
                    out.append(i + 1).append(") 디코드 실패\n");
                    continue;
                }
                final boolean ok = drv.printLabelBitmap(
                        bmp, TSPL_ZERO_IS_BLACK, thresholds[i], densities[i]);
                out.append(i + 1).append(") 임계값=").append(thresholds[i])
                        .append(" 농도=")
                        .append(densities[i] >= 0 ? densities[i] : "기본")
                        .append(" → 전송 ").append(ok).append('\n');
                bmp.recycle();
                if (i < pngs.size() - 1) {
                    // 펌웨어는 앞 라벨을 떼기 전에는 다음 장을 보류한다(정상 동작).
                    // 떼는 시간을 주지 않으면 뒤 장들이 한꺼번에 쏟아져 순서를 잃는다.
                    log("라벨을 떼어 주세요 — 10초 후 다음 장");
                    if (!sleep(10_000)) break;
                }
            }
        } finally {
            drv.close();
        }
        out.append("\n기존 Caysn 출력물과 나란히 놓고 획 굵기가 맞는 장을 고르세요.");
        log("===== USB Direct BITMAP 튜닝 끝 =====");
        return out.toString();
    }

    /**
     * 인쇄 없이 <b>idle status 비콘</b>만 장치별로 세어 IN 채널 비대칭을 가른다.
     *
     * <p>1차 실증에서 장치1(bus 3)은 응답 0건, 장치2(bus 5)는 정상 수신이었다.
     * 그런데 그 관측만으로는 원인이 <b>그 기계의 특성</b>인지 <b>"먼저 처리한
     * 장치" 라는 위치의 특성</b>인지 구분되지 않는다 — 둘이 완전히 교락돼 있었다.
     *
     * <p><b>2026-08-13 1차 결과 — 순서 요인은 배제됐다.</b> 정순/역순 두 번 모두
     * bus 3 = 0건, bus 5 = 5~6건. "먼저 연 장치" 문제가 아니다.
     *
     * <p>그래서 2차는 축을 바꾼다. <b>자발적 비콘이 없어도 능동 질의에는 답하는가</b>
     * 를 본다 — TSPL 의 {@code <ESC>!?} 는 "프린터 에러 중에도 언제나" 상태를
     * 돌려주게 돼 있다. 답이 오면 IN 채널 자체는 살아 있고 <b>자발적 통지만</b>
     * 꺼진 것이므로 폴링으로 우회할 수 있다. 답도 없으면 그 장치의 IN 은 죽은 것이다.
     *
     * <p>이게 왜 중요한가: <b>비콘이 안 오는 프린터에서도 완료 판정이 돼야 한다.</b>
     * 자발적 비콘에만 의존하는 설계는 이런 한 대 때문에 통째로 무너진다.
     *
     * <p>인쇄를 하지 않으므로 용지 소모가 없다.
     */
    public static String probeDirectInChannel(MainActivity activity) {
        log("===== IN 채널 비대칭 진단 시작 =====");
        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }

        final UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";
        final List<UsbDevice> devices = findDevices(activity);
        if (devices.isEmpty()) return "라벨 프린터 없음";
        awaitPermissions(activity, um, devices);

        final StringBuilder out = new StringBuilder();
        out.append("장치 ").append(devices.size()).append("대\n");

        for (UsbDevice d : devices) {
            final UsbLabelDriver drv = new UsbLabelDriver(d);
            if (!drv.open(activity)) {
                out.append("bus ").append(busNumberOf(d)).append(": open 실패\n");
                continue;
            }
            try {
                out.append("bus ").append(drv.getBusNumber()).append('\n');
                out.append("  수동 비콘: ")
                        .append(drv.countBeacons(BEACON_LISTEN_MS)).append('\n');
                for (StatusQuery q : STATUS_QUERIES) {
                    out.append("  ").append(q.name).append(": ")
                            .append(drv.askStatus(q)).append('\n');
                }
            } finally {
                drv.close();
            }
        }

        out.append("\n비콘 0건인데 능동 질의에 답이 오면 폴링으로 완료 판정이 가능합니다.\n")
                .append("둘 다 무응답이면 그 장치의 IN 채널은 쓸 수 없습니다.\n")
                .append("※ 케이블을 서로 바꿔 꽂고 한 번 더 돌리면 '기계'와 '포트'가 갈립니다.");
        log("===== IN 채널 비대칭 진단 끝 =====");
        return out.toString();
    }

    /** 능동 상태 질의 한 종류. */
    private static final class StatusQuery {
        final String name;
        final byte[] command;

        StatusQuery(String name, byte[] command) {
            this.name = name;
            this.command = command;
        }
    }

    /**
     * TSPL 능동 상태 질의 후보.
     *
     * <p>{@code <ESC>!?} 는 TSPL2 표준으로 "프린터 에러 중에도 언제나" 1바이트
     * 상태를 돌려주게 돼 있다(0x00 정상 / 0x01 헤드열림 / 0x04 용지없음 /
     * 0x20 인쇄중 …). {@code <ESC>!S} 는 더 상세한 상태.
     * {@code ~!@} 는 라인 명령이라 CRLF 가 필요하다 — {@code <ESC>!} 계열은
     * 즉시 명령이라 붙이지 않는다.
     *
     * <p>어느 것이 이 펌웨어에서 실제로 동작하는지 모르므로 셋 다 쏴 보고 고른다.
     */
    private static final StatusQuery[] STATUS_QUERIES = {
            new StatusQuery("<ESC>!? (표준 1바이트)", new byte[]{0x1B, 0x21, 0x3F}),
            new StatusQuery("<ESC>!S (상세)", new byte[]{0x1B, 0x21, 0x53}),
            new StatusQuery("~!@ (라인)", new byte[]{0x7E, 0x21, 0x40, 0x0D, 0x0A}),
    };

    /**
     * 능동 상태 질의를 보내고 응답을 모은다.
     *
     * <p>질의 전에 IN 을 <b>비운다</b> — 안 비우면 큐에 남아 있던 자발적 비콘이
     * 질의 응답으로 오독된다(비콘이 오는 장치에서 특히). 응답도 한 건만 읽지 않고
     * 잠깐 더 모은다 — 자발적 비콘과 섞여 오므로 첫 패킷이 답이라는 보장이 없다.
     */
    public String askStatus(StatusQuery query) {
        if (!isOpen() || endpointIn == null) return "IN 엔드포인트 없음";
        int drained = 0;
        while (read(50) != null && drained < 32) drained++;
        if (!write(query.command)) return "전송 실패";

        final StringBuilder sb = new StringBuilder();
        int count = 0;
        final long deadline = System.currentTimeMillis() + QUERY_LISTEN_MS;
        while (System.currentTimeMillis() < deadline) {
            final byte[] pkt = read(300);
            if (pkt == null) continue;
            count++;
            if (count <= 3) sb.append(describeBytes(pkt)).append(' ');
        }
        final String result = count == 0
                ? "무응답" + (drained > 0 ? " (사전 배출 " + drained + "건)" : "")
                : count + "건 " + sb;
        log("bus " + getBusNumber() + " " + query.name + " -> " + result);
        return result;
    }

    /** 능동 질의 응답 청취 시간. */
    private static final int QUERY_LISTEN_MS = 2000;

    // ── USB Printer Class 표준 제어 전송 ─────────────────────────────────────
    //
    // 벤더 auto-reply 프로토콜과 <b>무관하게</b> 동작하는 채널이다. Caysn 이 켜 주지
    // 않은 장치에서도 답해야 정상이므로, 여기서 답이 오면 완료 판정의 대안 경로가 된다.

    private static final int PRINTER_CLASS_IN = 0xA1; // device->host, class, interface
    private static final int REQ_GET_DEVICE_ID = 0;
    private static final int REQ_GET_PORT_STATUS = 1;

    /**
     * IEEE-1284 장치 식별 문자열 (GET_DEVICE_ID).
     *
     * <p>여기에 {@code SN:} 이 들어 있으면 <b>버스 번호 대신 진짜 프린터 고유
     * 식별자</b>를 얻는다 — USB 디스크립터의 iSerialNumber 가 없어서 막혔던
     * 장치 지목 문제를 다른 경로로 푸는 셈이다. 케이블을 옮겨도 따라오는 키가 된다.
     *
     * <p>응답은 앞 2바이트가 big-endian 길이, 그 뒤가 ASCII.
     */
    public String deviceIdString() {
        if (connection == null || iface == null) return "미연결";
        final byte[] buf = new byte[1024];
        // wIndex = (interface << 8) | altsetting — GET_DEVICE_ID 만 이 형식이다.
        final int n = connection.controlTransfer(PRINTER_CLASS_IN, REQ_GET_DEVICE_ID,
                0, iface.getId() << 8, buf, buf.length, 1000);
        if (n < 0) return "미지원(rc=" + n + ")";
        if (n < 2) return "응답 " + n + "바이트";
        final int len = Math.min(((buf[0] & 0xFF) << 8) | (buf[1] & 0xFF), n);
        return new String(buf, 2, Math.max(0, len - 2), StandardCharsets.US_ASCII)
                .trim();
    }

    /**
     * USB Printer Class 포트 상태 1바이트 (GET_PORT_STATUS).
     * bit3 = NoError, bit4 = Select/OnLine, bit5 = PaperEmpty.
     */
    public String portStatus() {
        if (connection == null || iface == null) return "미연결";
        final byte[] buf = new byte[1];
        final int n = connection.controlTransfer(PRINTER_CLASS_IN, REQ_GET_PORT_STATUS,
                0, iface.getId(), buf, 1, 1000);
        if (n < 1) return "미지원(rc=" + n + ")";
        final int s = buf[0] & 0xFF;
        return String.format("0x%02X", s)
                + (((s & 0x20) != 0) ? " [용지없음]" : "")
                + (((s & 0x10) != 0) ? " [온라인]" : "")
                + (((s & 0x08) != 0) ? " [에러없음]" : "");
    }

    /**
     * auto-reply 를 켜는 명령 후보. 하나씩 쏘고 응답이 시작되는지 본다.
     *
     * <p>{@code GS a n}(0x1D 0x61)은 ESC/POS 의 <b>Automatic Status Back</b> —
     * 이름 그대로 "상태를 자동으로 보내라" 이고, Caysn 이 부르는 "autoreplymode" 와
     * 같은 개념이다. 이 SDK 는 {@code CP_Pos_*} 를 가진 POS 겸용이라 앞서 쏜 TSPL
     * 계열({@code <ESC>!?})이 아니라 이쪽일 공산이 크다.
     */
    private static final StatusQuery[] ENABLE_CANDIDATES = {
            new StatusQuery("GS a 255 (ASB 전체)", new byte[]{0x1D, 0x61, (byte) 0xFF}),
            new StatusQuery("GS a 2 (ASB 에러)", new byte[]{0x1D, 0x61, 0x02}),
            new StatusQuery("DLE EOT 1 (실시간)", new byte[]{0x10, 0x04, 0x01}),
            new StatusQuery("ESC = 1 (장치선택)", new byte[]{0x1B, 0x3D, 0x01}),
            new StatusQuery("ESC @ (초기화)", new byte[]{0x1B, 0x40}),
    };

    /**
     * 조용한 장치를 <b>말하게 만들 수 있는지</b> 가른다.
     *
     * <p>Caysn 의 {@code CP_Port_OpenUsb(name, 1)} 이 auto-reply 를 켠다는 것까지는
     * 확인됐다(2026-08-13). 하지만 Caysn 은 첫 매칭 한 대만 열 수 있으므로, 2대
     * 운용을 하려면 <b>우리가 직접 켜는 방법</b>을 찾아야 한다.
     *
     * <p>정적 추출(.so 에서 XOR 유효 8바이트 프레임 스캔)은 실패했다 — SDK 가 프레임을
     * 런타임 조립한다. 그래서 표준 명령 후보를 하나씩 쏘고 응답 시작 여부를 본다.
     *
     * <p>표준 제어 전송(GET_DEVICE_ID / GET_PORT_STATUS)도 함께 찍는다. 이쪽은
     * 벤더 프로토콜과 무관하게 답해야 하므로, auto-reply 를 못 켜더라도 완료 판정의
     * 대안이 된다. GET_DEVICE_ID 에 {@code SN:} 이 있으면 장치 매핑 키도 얻는다.
     */
    public static String probeDirectEnable(MainActivity activity) {
        log("===== auto-reply 활성화 후보 진단 시작 =====");
        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }

        final UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";
        final List<UsbDevice> devices = findDevices(activity);
        if (devices.isEmpty()) return "라벨 프린터 없음";
        awaitPermissions(activity, um, devices);

        final StringBuilder out = new StringBuilder();
        for (UsbDevice d : devices) {
            final UsbLabelDriver drv = new UsbLabelDriver(d);
            if (!drv.open(activity)) {
                out.append("bus ").append(busNumberOf(d)).append(": open 실패\n");
                continue;
            }
            try {
                out.append("bus ").append(drv.getBusNumber()).append('\n');

                final String devId = drv.deviceIdString();
                final String port = drv.portStatus();
                log("bus " + drv.getBusNumber() + " GET_DEVICE_ID = " + devId);
                log("bus " + drv.getBusNumber() + " GET_PORT_STATUS = " + port);
                out.append("  식별문자열: ").append(devId).append('\n');
                out.append("  포트상태: ").append(port).append('\n');

                // 이미 말하고 있는 장치인지 먼저 확인 — 그래야 후보의 효과와
                // 원래 상태를 혼동하지 않는다.
                final String before = drv.countBeacons(3000);
                out.append("  사전 비콘(3초): ").append(before).append('\n');

                for (StatusQuery c : ENABLE_CANDIDATES) {
                    out.append("  ").append(c.name).append(" → ")
                            .append(drv.askStatus(c)).append('\n');
                }
            } finally {
                drv.close();
            }
        }
        out.append("\n조용하던 장치가 어느 후보 뒤부터 응답하기 시작하면 그게 활성화 명령입니다.");
        log("===== auto-reply 활성화 후보 진단 끝 =====");
        return out.toString();
    }

    /** 비콘 청취 시간. ~2초 주기라면 이 안에 여러 건이 잡혀야 정상이다. */
    private static final int BEACON_LISTEN_MS = 10_000;

    /**
     * [listenMs] 동안 bulk IN 을 계속 읽어 수신 건수와 첫/마지막 패킷을 요약한다.
     *
     * <p>read 한 번의 timeout 은 짧게 잡는다 — 길게 잡으면 "주기적으로 오는가" 를
     * 못 보고 "한 번은 오더라" 만 보게 된다.
     */
    public String countBeacons(int listenMs) {
        if (!isOpen() || endpointIn == null) return "IN 엔드포인트 없음";
        final long deadline = System.currentTimeMillis() + listenMs;
        int count = 0;
        byte[] first = null;
        byte[] last = null;
        while (System.currentTimeMillis() < deadline) {
            final byte[] pkt = read(500);
            if (pkt == null) continue;
            count++;
            if (first == null) first = pkt;
            last = pkt;
        }
        final StringBuilder sb = new StringBuilder(count + "건");
        if (count > 0) {
            sb.append(" 첫=").append(describeBytes(first));
            if (count > 1) sb.append(" 끝=").append(describeBytes(last));
        }
        log("bus " + getBusNumber() + " 비콘 " + sb);
        return sb.toString();
    }

    /**
     * 라벨 1장을 뽑고 <b>상태 비트가 언제 어떻게 바뀌는지</b> 기록한다.
     *
     * <p>여기서 가리는 것: <b>표준 ESC/POS 상태 채널로 "라벨을 뗐다" 를 감지할 수
     * 있는가.</b> 이게 되면 Caysn 의 벤더 비콘에 의존하지 않고 완료 판정을 만들 수
     * 있고, 그러면 2대 운용의 마지막 미지수가 풀린다.
     *
     * <p>2026-05 PoC 가 만든 paper-state machine 은 Caysn 비콘의 byte7 마스크에
     * 기대고 있었는데, byte7 은 상태가 아니라 <b>XOR 체크섬</b>임이 밝혀졌다
     * (2026-08-13). 그러니 어차피 상태 비트는 처음부터 다시 유도해야 한다.
     *
     * <p>기록은 <b>변화가 있을 때만</b> 남긴다 — 40초를 400ms 로 폴링하면 수백 줄이
     * 되지만, 우리가 찾는 건 값이 아니라 <b>전이 시점</b>이다. 사용자가 라벨을 떼는
     * 순간에 어떤 바이트의 어떤 비트가 뒤집히는지가 답이다.
     */
    public static String probeDirectPeelState(MainActivity activity, byte[] png) {
        log("===== 떼기 감지 진단 시작 =====");
        if (png == null || png.length == 0) return "라벨 이미지가 비어 있습니다.";
        final Bitmap bmp = BitmapFactory.decodeByteArray(png, 0, png.length);
        if (bmp == null) return "라벨 이미지 디코드 실패";

        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }
        final UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";
        final List<UsbDevice> devices = findDevices(activity);
        if (devices.isEmpty()) return "라벨 프린터 없음";
        awaitPermissions(activity, um, devices);

        final UsbLabelDriver drv = new UsbLabelDriver(devices.get(0));
        if (!drv.open(activity)) {
            return "장치 open 실패 (bus " + busNumberOf(devices.get(0)) + ")";
        }

        final StringBuilder out = new StringBuilder();
        out.append("bus ").append(drv.getBusNumber()).append(" 에서 1장 인쇄 후 ")
                .append(PEEL_WATCH_MS / 1000).append("초 관찰\n");
        try {
            // ASB 를 켜 두면 상태 변화 시 자발적으로 밀어 준다. 폴링과 병행해
            // 어느 채널이 먼저/정확히 잡는지도 함께 본다.
            drv.write(new byte[]{0x1D, 0x61, (byte) 0xFF});
            while (drv.read(100) != null) { /* 사전 배출 */ }

            final long t0 = System.currentTimeMillis();
            drv.printLabelBitmap(bmp, TSPL_ZERO_IS_BLACK);
            out.append("인쇄 전송 완료\n");

            String lastPush = "";
            final String[] lastPoll = new String[PEEL_QUERIES.length];
            final long deadline = t0 + PEEL_WATCH_MS;
            while (System.currentTimeMillis() < deadline) {
                // ① 자발적 푸시 (ASB / 벤더 비콘 둘 다 여기로 온다)
                final byte[] push = drv.read(120);
                if (push != null) {
                    final String s = describeBytes(push);
                    if (!s.equals(lastPush)) {
                        lastPush = s;
                        record(out, t0, "푸시", s);
                    }
                }
                // ② 동기 폴링
                for (int q = 0; q < PEEL_QUERIES.length; q++) {
                    final byte[] r = drv.query(PEEL_QUERIES[q].command, 400);
                    final String s = r == null ? "무응답" : describeBytes(r);
                    if (!s.equals(lastPoll[q])) {
                        lastPoll[q] = s;
                        record(out, t0, PEEL_QUERIES[q].name, s);
                    }
                }
                if (!sleep(300)) break;
            }
        } finally {
            drv.close();
            bmp.recycle();
        }
        out.append("\n라벨을 떼는 순간에 바뀐 줄이 떼기 신호입니다.");
        log("===== 떼기 감지 진단 끝 =====");
        return out.toString();
    }

    /** 관찰 시간. 사용자가 라벨을 떼고 그 전후를 다 담을 만큼 길어야 한다. */
    private static final int PEEL_WATCH_MS = 45_000;

    /**
     * 떼기 관찰에 쓰는 동기 폴링 명령.
     *
     * <p>ESC/POS 실시간 상태 4종. {@code DLE EOT 4}(용지 센서)가 본命 후보지만,
     * 라벨 프린터 펌웨어가 어느 비트에 peel 을 싣는지 모르므로 넷 다 본다.
     */
    private static final StatusQuery[] PEEL_QUERIES = {
            new StatusQuery("EOT1 프린터", new byte[]{0x10, 0x04, 0x01}),
            new StatusQuery("EOT2 오프라인", new byte[]{0x10, 0x04, 0x02}),
            new StatusQuery("EOT3 에러", new byte[]{0x10, 0x04, 0x03}),
            new StatusQuery("EOT4 용지", new byte[]{0x10, 0x04, 0x04}),
    };

    private static void record(StringBuilder out, long t0, String label, String value) {
        final long ms = System.currentTimeMillis() - t0;
        final String line = String.format("%6dms %-12s %s", ms, label, value);
        log("[PEEL] " + line);
        out.append(line).append('\n');
    }

    /** 명령을 보내고 한 패킷 받는다. 응답 없으면 null. */
    public byte[] query(byte[] command, int timeoutMs) {
        if (!write(command)) return null;
        return read(timeoutMs);
    }

    /**
     * 연결된 프린터 <b>전부에 동시에</b> 라벨을 여러 장 뽑으며 완료 판정을 검증한다.
     *
     * <p>경로 B 의 종합 시험이다. 여기서 보는 것 셋:
     * <ol>
     *   <li><b>완료 판정</b> — 장마다 3분류 결과와 소요 시간</li>
     *   <li><b>격리</b> — 한 대에서 라벨을 안 떼도 다른 대는 계속 나가는가.
     *       Caysn 단일 핸들에서는 구조적으로 불가능했던 것이다</li>
     *   <li><b>순서</b> — 각 라벨에 기계 번호와 순번이 찍혀 나온다</li>
     * </ol>
     *
     * <p>장치마다 <b>별도 스레드</b>로 돌린다. 한 스레드가 보류 대기로 막혀도 다른
     * 쪽이 진행되는 것이 요점이므로, 순차로 돌리면 검증하려는 성질 자체가 사라진다.
     *
     * @param pngsPerDevice 장치 <b>한 대당</b> 뽑을 라벨들. 어느 기계·몇 번째인지는
     *                      호출부가 이미지 안에 박아 둔다.
     */
    public static String probeDirectDualPrint(MainActivity activity,
                                              List<byte[]> pngsPerDevice) {
        log("===== 2대 동시 인쇄 + 완료 판정 시험 시작 =====");
        if (pngsPerDevice == null || pngsPerDevice.isEmpty()) return "이미지가 비어 있습니다.";

        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            log("Caysn 포트 close 예외: " + t.getMessage());
        }
        final UsbManager um = (UsbManager) activity.getSystemService(Context.USB_SERVICE);
        if (um == null) return "USB 서비스 없음";
        final List<UsbDevice> devices = findDevices(activity);
        if (devices.isEmpty()) return "라벨 프린터 없음";
        awaitPermissions(activity, um, devices);

        final List<Bitmap> pages = new ArrayList<>();
        for (byte[] png : pngsPerDevice) {
            final Bitmap b = (png == null || png.length == 0)
                    ? null : BitmapFactory.decodeByteArray(png, 0, png.length);
            if (b != null) pages.add(b);
        }
        if (pages.isEmpty()) return "이미지 디코드 실패";

        final StringBuilder[] reports = new StringBuilder[devices.size()];
        final Thread[] workers = new Thread[devices.size()];
        for (int i = 0; i < devices.size(); i++) {
            final int index = i;
            final UsbDevice d = devices.get(i);
            reports[i] = new StringBuilder();
            workers[i] = new Thread(() -> {
                final StringBuilder r = reports[index];
                final UsbLabelDriver drv = new UsbLabelDriver(d);
                if (!drv.open(activity)) {
                    r.append("bus ").append(busNumberOf(d)).append(": open 실패\n");
                    return;
                }
                try {
                    r.append("bus ").append(drv.getBusNumber()).append('\n');
                    for (int p = 0; p < pages.size(); p++) {
                        final String tag = "[bus " + drv.getBusNumber()
                                + " " + (p + 1) + "/" + pages.size() + "]";
                        final long t0 = System.currentTimeMillis();
                        final int rc = drv.printLabelAwait(
                                pages.get(p), DUAL_PRINT_CAP_MS, tag);
                        r.append("  ").append(p + 1).append("장: ")
                                .append(describeResult(rc)).append(" (")
                                .append(System.currentTimeMillis() - t0)
                                .append("ms)\n");
                        // 재시도 정책은 여기서 흉내내지 않는다 — 이 프로브의 목적은
                        // 판정이 맞는지 보는 것이고, 재시도는 Dart 큐의 책임이다.
                    }
                } finally {
                    drv.close();
                }
            }, "usb-label-" + busNumberOf(d));
            workers[i].start();
        }

        for (Thread w : workers) {
            try {
                w.join();
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                break;
            }
        }
        for (Bitmap b : pages) b.recycle();

        final StringBuilder out = new StringBuilder();
        for (StringBuilder r : reports) out.append(r);
        out.append("\n한 대에서 라벨을 안 떼고 두면 그 대만 대기하고 다른 대는 계속 나와야 정상입니다.");
        log("===== 2대 동시 인쇄 + 완료 판정 시험 끝 =====");
        return out.toString();
    }

    /** 한 장당 완료 대기 상한. 넘어도 peel 에 라벨이 있으면 계속 기다린다. */
    private static final long DUAL_PRINT_CAP_MS = 30_000L;

    private static String describeResult(int rc) {
        if (rc == LabelPrinter.RESULT_SUCCESS) return "성공";
        if (rc == LabelPrinter.RESULT_RETRYABLE) return "재시도가능(미제출)";
        return "제출후무확인";
    }

    /** 화이트리스트 장치 <b>전부</b>에 USB 권한을 요청하고 최대 8초 기다린다. */
    private static void awaitPermissions(MainActivity activity, UsbManager um,
                                         List<UsbDevice> devices) {
        int requested = 0;
        for (UsbDevice d : devices) {
            if (!um.hasPermission(d)) {
                UsbPermissionHelper.request(activity, um, d);
                requested++;
            }
        }
        if (requested == 0) return;
        log("권한 요청 " + requested + "건 — 최대 8초 대기");
        for (int i = 0; i < 16; i++) {
            boolean all = true;
            for (UsbDevice d : devices) {
                if (!um.hasPermission(d)) { all = false; break; }
            }
            if (all) return;
            if (!sleep(500)) return;
        }
    }

    /** @return 정상적으로 잤으면 true, 인터럽트되면 false. */
    private static boolean sleep(long ms) {
        try {
            Thread.sleep(ms);
            return true;
        } catch (InterruptedException ie) {
            Thread.currentThread().interrupt();
            return false;
        }
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
