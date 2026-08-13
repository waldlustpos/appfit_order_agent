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
     * <p>그래서 <b>정순 → 역순</b>으로 두 번 돌린다:
     * <ul>
     *   <li>순서를 바꿔도 같은 bus 가 0건 → <b>기계/케이블 고유</b> 문제</li>
     *   <li>순서를 바꾸면 0건인 쪽도 바뀜 → <b>먼저 연 장치</b>가 못 받는 구조 문제
     *       (커널 usblp 잔여 claim, 첫 read 의 pipe stall 등)</li>
     *   <li>둘 다 정상 수신 → 1차 관측은 read timeout(2~3초)이 비콘 주기(~2초)
     *       경계에 걸린 <b>측정 아티팩트</b></li>
     * </ul>
     *
     * <p>인쇄를 하지 않으므로 용지 소모가 없다. 완료 판정을 비콘에 의존하려면
     * 이 비대칭을 먼저 풀어야 한다 — paper-state machine 의 선행조건이다.
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
        out.append("장치 ").append(devices.size()).append("대 · 각 ")
                .append(BEACON_LISTEN_MS / 1000).append("초씩 정순/역순 청취\n");

        for (int pass = 0; pass < 2; pass++) {
            final boolean reverse = pass == 1;
            out.append(reverse ? "\n[역순]\n" : "[정순]\n");
            for (int i = 0; i < devices.size(); i++) {
                final UsbDevice d = devices.get(reverse ? devices.size() - 1 - i : i);
                final UsbLabelDriver drv = new UsbLabelDriver(d);
                if (!drv.open(activity)) {
                    out.append("  bus ").append(busNumberOf(d)).append(": open 실패\n");
                    continue;
                }
                try {
                    out.append("  bus ").append(drv.getBusNumber()).append(": ")
                            .append(drv.countBeacons(BEACON_LISTEN_MS)).append('\n');
                } finally {
                    drv.close();
                }
            }
        }

        out.append("\n같은 bus 가 두 번 다 0건이면 기계/케이블 문제,\n")
                .append("순서에 따라 0건이 옮겨가면 '먼저 연 장치' 구조 문제입니다.");
        log("===== IN 채널 비대칭 진단 끝 =====");
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
