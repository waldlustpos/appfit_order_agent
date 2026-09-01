package co.kr.waldlust.order.receive.util.print;

import android.content.Context;
import android.graphics.Bitmap;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.util.Log;

import com.bxl.config.editor.BXLConfigLoader;

import jpos.JposException;
import jpos.POSPrinter;
import jpos.POSPrinterConst;
import jpos.config.JposEntry;

import java.util.List;

import co.kr.waldlust.order.receive.MainActivity;

/**
 * BIXOLON G30 라벨 프린터 드라이버 (USB 전용).
 *
 * <p>★ 이 드라이버는 {@link LabelPrinter}(Caysn/REXOD)와 <b>공유하는 코드가 없다.</b> BIXOLON 이
 * G30 에 배포하는 것은 라벨 명령셋(SLCS) 이 아니라 <b>UPOS/JavaPOS SDK</b>
 * (V2.2.10, {@code com.bxl.**} / {@code jpos.**})이고, {@code PRODUCT_NAME_G30 = "G30"} 이
 * {@link BXLConfigLoader} 에 POS 프린터 카테고리로 등록돼 있다. 연결·인쇄·상태조회 API 가
 * 전부 다르므로 기존 라벨 드라이버를 상속/재사용하지 않고 새로 작성했다.
 *
 * <p>용지도 다르다 — Caysn/REXOD 는 갭 라벨(고정 크기 낱장 + 갭센서 + 피러 떼기대기)이지만
 * G30 은 <b>연속 용지</b>(가로 고정 + 세로 무제한, 커터로 장 구분)다. 그래서 이 드라이버에는
 * 떼기대기(PAUSED_IN_PEELER)나 상태 byte variant 학습 같은 갭 라벨 특유 로직이 전혀 없다 —
 * 존재하지 않는 상태를 흉내내면 영원히 안 풀리는 대기가 된다.
 *
 * <p><b>UPOS 동기 모드의 완료 판정</b>: {@code setAsyncMode(false)} 로 열면 JavaPOS 표준상
 * 출력 메서드(정확히는 트랜잭션을 flush 하는 마지막 {@code transactionPrint(NORMAL)})가
 * <b>물리적으로 인쇄가 끝날 때까지 블로킹</b>한다. 즉 SLCS 처럼 별도 완료 폴링 루프가
 * 필요 없다 — 예외 없이 반환하면 그 자체가 완료 신호다. (SLCS 의 {@code endTransactionPrint}
 * 는 "전송 완료" 만 보장하고 실제 인쇄 완료는 status byte 폴링으로 따로 확인해야 했던 것과
 * 다르다.)
 *
 * <p><b>중복 인쇄 방지(submit-wins)</b>: {@code transactionPrint(PTR_S_RECEIPT, PTR_TP_NORMAL)}
 * 호출 시점부터가 실제 전송 경계다. TRANSACTION 모드는 그 이전 {@code printBitmap}/
 * {@code printNormal}(커터) 호출을 소프트웨어 버퍼에 쌓기만 하고 하드웨어로 보내지
 * 않는다(JavaPOS 표준 동작 — <b>실기기 검증 전까지는 가정</b>). 그래서:
 * <ul>
 *   <li>버퍼링 단계({@code printBitmap}/커터)에서 예외 → 아직 아무것도 전송 안 됨 →
 *       {@code clearOutput()} 로 버퍼 폐기 후 재시도 안전(false, 재시도 가능)</li>
 *   <li>flush 단계({@code transactionPrint(NORMAL)})에서 예외 → 전송 여부 불명 →
 *       {@code getCoverOpen()} 재조회로 2차 판별. 응답하면 연결이 살아있다는 뜻이므로
 *       submit-wins(true) — false 를 주면 Dart 재시도가 같은 라벨을 한 장 더 발사한다
 *       (Caysn 745번 2장 사고, 구 XD5-40d 드라이버의 {@code endTransactionPrint=-1}
 *       처리와 동일 뿌리).
 *       조회도 실패하면 연결 자체가 죽은 것으로 보고 재시도 위임(false).</li>
 * </ul>
 *
 * <p>PID 는 실기기로 확인됐다({@link #KNOWN_PRODUCT_IDS} = 0x147). 제품명 부분일치는
 * PID 미매칭 개체(리퍼브/다른 로트)를 위한 보조 판정으로 남겨둔다.
 */
public class BixolonPosDriver {
    private static final String TAG = "BixolonPosDriver";

    /** BIXOLON vendor id (0x1504 = 5380). device_filter.xml 은 이 VID 를 PID 없이 등록한다. */
    public static final int BIXOLON_VENDOR_ID = 0x1504;

    /**
     * G30 실기기 PID (2026-08-21 UsbReceiptPrinter discover 로그 실측: vid=0x1504 pid=0x147).
     * 제품명 부분일치는 이제 보조 판정으로 격하 — 제품명은 로캘/펌웨어에 따라 흔들릴 수 있어
     * PID 가 우선한다.
     */
    private static final int[] KNOWN_PRODUCT_IDS = {0x147};

    /** BXLConfigLoader 에 등록할 논리 이름. jpos.xml 엔트리 키이자 open() 인자. */
    private static final String LOGICAL_NAME = "G30";

    /**
     * 사전 이진화 임계값 (luminance &lt; threshold → 검정). {@link #binarizeForPrint} 와
     * {@code printBitmap} 의 level 인자가 함께 쓴다.
     *
     * <p>SDK 자체 이진화에 맡기지 않는 근거(구 XD5-40d 드라이버에서 계승, 실기기 검증):
     * SDK level 이진화는 임계가 낮게 동작해 AA 로 회색화된 얇은 글자·1px 구분선·
     * black26 구분자(흰 배경 합성 시 ≈189)가 소실됐다(순흑 로고/큰 글자만 선명).
     * Java 에서 결정론적으로 이진화해 Caysn thresholding 출력과 시각 동등을 맞춘다.
     *
     * <p>값 근거: 라벨 팔레트의 가장 밝은 잉크가 black26(≈189) 이므로 그보다 높게,
     * 흰 배경(255) 과는 여유를 두고 210. 출력이 너무 두꺼우면 낮추고 얇은 요소가
     * 빠지면 올린다.
     *
     * <p>★ 조정 시 (0,255) 를 벗어나지 말 것 — 같은 상수를 SDK {@code printBitmap} 의
     * level 인자로도 넘기고 있다. 사전 이진화 후 픽셀이 순흑/순백뿐이라 그 인자는
     * 실질적으로 무의미하지만, 극단값은 SDK 쪽 의미론을 깨울 수 있다.
     *
     * <p>★ 이 값의 근거가 레포에 남은 <b>유일한 사본</b>이다. Windows 쪽 복제본 2곳
     * (구 {@code label_bmp_converter.dart} / {@code bxllapi_constants.dart})은 XD5-40d
     * 지원 종료와 함께 삭제됐다 — BXLPAPI 이식 시 재유도하지 말고 이 값을 가져갈 것.
     */
    private static final int BINARIZE_THRESHOLD = 210;

    /**
     * 전송폭 상한 — **헤드 물리 최대폭**(getRecLineWidth() 보고값 576dot ≈ 72mm)이다.
     * 용지별 인쇄폭이 아니다.
     *
     * <p>이 값이 용지폭(40mm=320dot)이면 안 되는 이유: G30 은 한 대가 가이드 부품 교체만으로
     * 40mm/58mm 겸용이라 58mm 비트맵(320dot 초과)이 정상적으로 들어온다. 상한을 320 으로
     * 두면 그 비트맵이 조용히 잘려 나가고, 눈금자 진단조차 항상 320dot 에서 끊겨 "58mm
     * 유효폭 = 320dot" 이라는 가짜 실측값을 만든다(2026-08-26 수정 전 상태).
     *
     * <p>용지별 실제 인쇄폭은 Dart 측 {@code LabelMediaSpec}(continuous40 / continuous58)이
     * 결정한다 — 여기서는 헤드 밖 인쇄만 막는 안전망이다.
     */
    private static final int MAX_PRINT_WIDTH_DOTS = 576;

    /**
     * BIXOLON POS 커스텀 명령 프리픽스 (ESC + '|' = 0x1B 0x7C). UPOS SDK 샘플의
     * {@code EscapeSequence.ESCAPE_CHARACTERS} 와 동일 값이지만 그 클래스는 샘플 소스에만
     * 있고 SDK jar 에는 없어(컴파일 불가) 값만 가져와 로컬 상수로 둔다.
     */
    private static final String ESC_PREFIX = new String(new byte[]{0x1B, 0x7C});

    private static final long CLAIM_TIMEOUT_MS = 10_000L;
    private static final long PERMISSION_WAIT_MS = 30_000L;
    private static final long STATUS_POLL_INTERVAL_MS = 200L;
    private static final long RECOVERY_HEARTBEAT_MS = 60_000L;

    private static MainActivity sActivity = null;
    private static BXLConfigLoader sConfigLoader = null;
    /** 클래스 lock 으로 보호. 연결마다 재생성. */
    private static POSPrinter sSdk = null;
    /** JavaPOS 는 SLCS 의 isConnected() 같은 조회 API 가 없어 자체 추적한다. */
    private static volatile boolean sConnected = false;

    /**
     * USB detach 통지 플래그 (구 XD5-40d 드라이버에서 계승한 근거) —
     * printBitmap 이 복구대기로 클래스 lock 을 오래 쥘 수 있어 메인 스레드가 직접
     * synchronized close() 에 들어가면 ANR 위험. 플래그만 세우고 close 는 백그라운드 위임.
     */
    private static volatile boolean sDetachRequested = false;

    public static void init(MainActivity activity) {
        sActivity = activity;
    }

    /**
     * G30 장치 존재 여부 — NativeMethodHandler 의 벤더 라우팅 판정.
     *
     * <p>판정이 <b>좁다</b>(VID + PID/제품명). BIXOLON 지원 기종이 G30 하나뿐이라 VID-only 로
     * 넓히고 싶어지지만 그러지 않는다 — 미식별 0x1504 기기를 G30 으로 몰아 UPOS 로 구동하면
     * 실패 원인이 흐려진다. 넓히려면 대상 기기의 PID 를 {@link #KNOWN_PRODUCT_IDS} 에
     * 추가하는 쪽이 맞다. 미식별 0x1504 는 어느 드라이버로도 가지 않는다(폴백 없음).
     */
    public static boolean isG30Attached(Context ctx) {
        UsbManager usbManager = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        if (usbManager == null) return false;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            if (isG30Device(device)) return true;
        }
        return false;
    }

    /**
     * 단일 디바이스 G30 판정. package-private — {@link UsbReceiptPrinter#isLabelPrinter}
     * 가 영수증 프린터 claim 대상에서 G30 을 제외하는 데 쓴다. 조건을 그쪽에 복제하면
     * 화이트리스트가 또 갈라진다(2026-09-01 사고: G30 추가 때 UsbReceiptPrinter 쪽만
     * 갱신이 빠져 영수증 경로가 G30 을 선점 → 라벨 인쇄가 exclusive claim 실패).
     */
    static boolean isG30Device(UsbDevice device) {
        if (device.getVendorId() != BIXOLON_VENDOR_ID) return false;
        for (int pid : KNOWN_PRODUCT_IDS) {
            if (device.getProductId() == pid) return true;
        }
        String productName = device.getProductName();
        return productName != null && productName.toUpperCase().contains(LOGICAL_NAME);
    }

    /**
     * 라벨 한 장을 인쇄한다. 전 구간 동기 블로킹 — labelPrintExecutor(단일 스레드)에서
     * 호출되므로 라벨 간 직렬화는 executor + synchronized 로 이중 보장된다.
     *
     * <p>width 는 호출자가 넘긴 비트맵의 실제 폭을 그대로 쓴다({@link #MAX_PRINT_WIDTH_DOTS}
     * 안전망 clamp 포함). Dart 측 연속용지 painter 는 캔버스 자체를 용지별 실측 유효
     * 인쇄폭({@code LabelMediaSpec.continuous40} = 272dot / {@code continuous58})으로
     * 생성해 넘긴다 — 용지 물리폭이 아니다. 인쇄 시작 위치 자체가 하드웨어에 고정돼
     * 있어(아래 주석 참조) 캔버스를 물리폭으로 넓게 잡아도 시각적 중앙 보정에 못 쓰기
     * 때문. 별도 스케일링 없이 그대로 맞는다.
     */
    public static synchronized boolean printBitmap(Bitmap bitmap,
                                                    String orderNo,
                                                    int labelIndex,
                                                    int totalLabels) {
        final long startTime = System.currentTimeMillis();
        final String orderTag = "[" + orderNo
                + (totalLabels > 1 ? " " + labelIndex + "/" + totalLabels : "") + "]";
        log(orderTag + " 출력시작");

        try {
            if (!ensureConnectedLocked(orderTag)) {
                logElapsed(orderTag, "실패 [연결오류]", startTime);
                return false;
            }

            if (!waitEntryGateLocked(orderTag)) {
                logElapsed(orderTag, "실패 [복구대기 중단]", startTime);
                return false;
            }

            // 실기기 확정 지식(2026-08): getRecLineWidth()=576dots 는 헤드 물리 최대폭
            // (80mm급)이지 로드된 용지 폭이 아니다 — 40mm/58mm 는 용지 장착 시 끼우는
            // 가이드 부품으로 고정하는 구조라 SDK 가 자동보고하지 않는다. 40mm 용지는
            // 이 가이드가 헤드 정중앙(dot 128~448, 폭 320)에 고정한다.
            //
            // 다만 **실제 인쇄 가능폭은 그보다 좁다** — 눈금자 테스트(LEFT 정렬, 0~40mm
            // 전체 눈금) 실기기 판독 결과 35mm(280dot) 지점에서 잘림을 3회 재현 확인.
            //
            // 여기서 좌측 padding 을 0.5mm~6mm 로 바꿔가며 시각 중앙을 맞춰보려 했으나
            // 전부 실패 — padding 을 키울수록 콘텐츠가 그만큼 그대로 더 오른쪽으로
            // 밀렸다(실기기 확인). 원인은 **인쇄 시작 위치 자체가 하드웨어에 고정**돼
            // 있어서다 — padding 0.5mm 인 상태로 눈금자를 찍어도 "인쇄 자체가 이미 왼쪽
            // 공백이 있는 상태로 시작"하는 게 실물에서 확인됐다(2026-08-21). 즉 캔버스에
            // 아무리 여백을 조정해도 그 시작 위치는 안 움직인다 — 시각 중앙 보정은
            // 소프트웨어 영역 밖(용지 가이드 재장착 등 하드웨어 쪽 확인 필요).
            //
            // 그래서 Dart 측은 40mm 캔버스에 margin 으로 중앙을 맞추는 접근을 버리고,
            // 캔버스 자체를 실측 유효 인쇄폭(280dot=35mm) 그대로 잡는다(안전마진은 좌우
            // 4dot 씩만, LabelMediaSpec.continuous40 참조) — "잘리지 않는 최대 폭"만
            // 보장한다. 아래 clamp 는 헤드 물리 최대폭(MAX_PRINT_WIDTH_DOTS=576)이 상한
            // — 용지폭이 아니다(58mm 비트맵을 잘라내지 않기 위함, 상수 주석 참조).
            final int width = Math.min(bitmap.getWidth(), MAX_PRINT_WIDTH_DOTS);
            final Bitmap prepared = binarizeForPrint(bitmap);

            // 원본/이진화 비트맵 크기와 검정 픽셀 비율을 남긴다 — blackRatio=0 이면
            // Dart 쪽(ContinuousLabelPainter)이 빈 이미지를 만든 것이고, >0 인데
            // 실물이 백지면 SDK/하드웨어 단계 문제로 좁혀진다.
            log(orderTag + " 이미지 원본=" + bitmap.getWidth() + "x" + bitmap.getHeight()
                    + " 이진화후=" + prepared.getWidth() + "x" + prepared.getHeight()
                    + " 검정비율=" + String.format("%.1f%%", blackRatio(prepared) * 100)
                    + " 전송폭=" + width);

            // ── 트랜잭션 시작: 이 이후 명령은 하드웨어로 즉시 전송되지 않고 버퍼링된다 ──
            sSdk.transactionPrint(POSPrinterConst.PTR_S_RECEIPT, POSPrinterConst.PTR_TP_TRANSACTION);

            try {
                // PTR_BM_LEFT 확정(2026-08) — PTR_BM_CENTER 는 이 기기/펌웨어에서
                // 백지 출력을 일으킨다(재현 확인). LEFT 인쇄 시작 위치는 하드웨어에
                // 고정돼 있어 소프트웨어로 조정 불가 — 좌우 시각 여백은 Dart 측
                // LabelMediaSpec.continuous40 의 캔버스 폭/margin 으로만 다룬다.
                sSdk.printBitmap(POSPrinterConst.PTR_S_RECEIPT, prepared, width,
                        POSPrinterConst.PTR_BM_LEFT, BINARIZE_THRESHOLD);
                // 라벨(장) 구분은 갭 센서가 아니라 커터 — Feed Partial Cut.
                sSdk.printNormal(POSPrinterConst.PTR_S_RECEIPT, ESC_PREFIX + "90fP");
            } catch (JposException bufferEx) {
                // 버퍼링 단계 실패 — 아직 아무것도 전송되지 않았다(가정, javadoc 클래스 참조).
                // 재시도 안전. clearOutput 은 best-effort — 실패해도 판정에 영향 없음.
                safeClearOutput();
                logElapsed(orderTag, "실패 [버퍼링오류: " + bufferEx.getMessage() + " — 재시도 위임]",
                        startTime);
                return false;
            }

            // ── flush: 여기서부터 submit-wins 구간 ─────────────────────────────
            try {
                sSdk.transactionPrint(POSPrinterConst.PTR_S_RECEIPT, POSPrinterConst.PTR_TP_NORMAL);
            } catch (JposException flushEx) {
                if (probeAliveLocked()) {
                    log(orderTag + " flush 응답 불명(" + flushEx.getMessage()
                            + ") — 연결 응답 확인, submit-wins 진행");
                } else {
                    closeLocked();
                    logElapsed(orderTag, "실패 [flush오류: " + flushEx.getMessage()
                            + " — 재시도 위임]", startTime);
                    return false;
                }
            }

            logElapsed(orderTag, "출력끝", startTime);
            return true;

        } catch (Exception e) {
            logElapsed(orderTag, "실패 [예외: " + e.getMessage() + "]", startTime);
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
            closeLocked();
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 연결 관리
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * 앱 시작 시점의 warm-up — 연결만 수행, 인쇄는 하지 않는다.
     * {@link LabelPrinter#warmup(int)} 의 G30 대응물. 벤더 분기는 인쇄 경로와 동일 규칙을
     * 써야 한다 — 어긋나면 첫 인쇄가 모드 불일치로 포트를 닫고 다시 연다.
     */
    public static synchronized boolean warmup() {
        try {
            return ensureConnectedLocked("[warmup]");
        } catch (Exception e) {
            log("[warmup] 예외: " + e.getMessage());
            return false;
        }
    }

    /** 연결 보장. 실패 시 false. 클래스 lock 하에서만 호출. */
    private static boolean ensureConnectedLocked(String orderTag) {
        if (sDetachRequested) {
            closeLocked();
        }
        if (sSdk != null && sConnected) {
            return true;
        }
        closeLocked();

        if (sActivity == null) {
            Log.e(TAG, "ensureConnected: not initialized (init() not called)");
            return false;
        }
        UsbManager usbManager = (UsbManager) sActivity.getSystemService(Context.USB_SERVICE);
        if (usbManager == null) return false;

        UsbDevice target = null;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            if (isG30Device(device)) {
                target = device;
                break;
            }
        }
        if (target == null) {
            log(orderTag + " 연결불가 [G30 장치 없음]");
            return false;
        }

        // USB 권한: device_filter attach 승계가 1차 (VID:0x1504 는 이미 등록돼 있어 G30 도
        // 상속받는다). 없으면 다이얼로그 요청 후 폴링 대기.
        if (!usbManager.hasPermission(target)) {
            log(orderTag + " USB 권한 요청 " + String.format("VID:0x%04X PID:0x%04X",
                    target.getVendorId(), target.getProductId()));
            UsbPermissionHelper.request(sActivity, usbManager, target);
            long waitStart = System.currentTimeMillis();
            while (!usbManager.hasPermission(target)
                    && (System.currentTimeMillis() - waitStart) < PERMISSION_WAIT_MS) {
                if (sDetachRequested || Thread.currentThread().isInterrupted()) return false;
                sleep(STATUS_POLL_INTERVAL_MS);
            }
            if (!usbManager.hasPermission(target)) {
                log(orderTag + " 연결불가 [USB 권한 거부/시간초과]");
                return false;
            }
        }

        try {
            if (sConfigLoader == null) {
                sConfigLoader = new BXLConfigLoader(sActivity.getApplicationContext());
                try {
                    sConfigLoader.openFile();
                } catch (Exception e) {
                    sConfigLoader.newFile();
                }
            }

            // 매 연결마다 엔트리를 최신 USB 경로로 갱신 — Android 는 재연결 시 device path
            // (getDeviceName())가 바뀔 수 있다.
            List<JposEntry> entries = sConfigLoader.getEntries();
            for (JposEntry entry : entries) {
                if (LOGICAL_NAME.equals(entry.getLogicalName())) {
                    sConfigLoader.removeEntry(LOGICAL_NAME);
                    break;
                }
            }
            sConfigLoader.addEntry(LOGICAL_NAME, BXLConfigLoader.DEVICE_CATEGORY_POS_PRINTER,
                    BXLConfigLoader.PRODUCT_NAME_G30, BXLConfigLoader.DEVICE_BUS_USB,
                    target.getDeviceName());
            sConfigLoader.saveFile();

            sSdk = new POSPrinter(sActivity.getApplicationContext());
            sSdk.open(LOGICAL_NAME);
            sSdk.claim((int) CLAIM_TIMEOUT_MS);
            sSdk.setDeviceEnabled(true);
            // 동기 모드 — transactionPrint(NORMAL) 이 물리 인쇄 완료까지 블로킹한다
            // (클래스 javadoc 참조). 별도 완료 폴링이 필요 없어지는 핵심 전제.
            sSdk.setAsyncMode(false);
            sConnected = true;

            log(orderTag + " 연결됨 " + String.format("VID:0x%04X PID:0x%04X",
                    target.getVendorId(), target.getProductId()));
            try {
                log(orderTag + " 인쇄가능폭=" + sSdk.getRecLineWidth() + "dots (실측 참고용)");
            } catch (JposException ignore) {
                // 진단 로그일 뿐 — 실패해도 연결 자체는 유효.
            }
            return true;
        } catch (Exception e) {
            log(orderTag + " 연결불가 [" + e.getMessage() + "]");
            closeLocked();
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 상태 게이트
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * 진입 게이트 — 용지없음/커버열림은 운영자 개입 신뢰, 무한 복구대기
     * (Caysn/REXOD 경로와 동등한 정책).
     * 그 외 조회 자체가 실패하면(연결 사망) false.
     */
    private static boolean waitEntryGateLocked(String orderTag) {
        long waitStart = System.currentTimeMillis();
        long lastNotice = waitStart;
        boolean noticed = false;
        while (true) {
            if (sDetachRequested || Thread.currentThread().isInterrupted()) return false;
            boolean coverOpen;
            boolean recEmpty;
            try {
                coverOpen = sSdk.getCoverOpen();
                recEmpty = sSdk.getRecEmpty();
            } catch (JposException e) {
                closeLocked();
                log(orderTag + " 진입게이트 조회 실패 [" + e.getMessage() + "] — 연결오류");
                return false;
            }
            if (!coverOpen && !recEmpty) {
                if (noticed) {
                    long waited = System.currentTimeMillis() - waitStart;
                    log(orderTag + " 복구감지 wait=" + waited + "ms — 인쇄재개");
                }
                return true;
            }
            if (!noticed) {
                log(orderTag + " 복구대기 진입 [" + describeEntry(coverOpen, recEmpty) + "]");
                noticed = true;
            }
            long now = System.currentTimeMillis();
            if (now - lastNotice >= RECOVERY_HEARTBEAT_MS) {
                log(orderTag + " 복구대기중 elapsed=" + ((now - waitStart) / 1000) + "s");
                lastNotice = now;
            }
            sleep(STATUS_POLL_INTERVAL_MS);
        }
    }

    private static String describeEntry(boolean coverOpen, boolean recEmpty) {
        if (coverOpen && recEmpty) return "용지없음+커버열림";
        if (recEmpty) return "용지없음";
        return "커버열림";
    }

    /** flush 예외 후 2차 판별 — 연결이 응답하면 submit-wins 로 본다. */
    private static boolean probeAliveLocked() {
        try {
            sSdk.getCoverOpen();
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    /**
     * 인쇄 전 사전 이진화 — luminance &lt; {@link #BINARIZE_THRESHOLD} → 순흑, 그 외 순백.
     * 결과 픽셀이 0/255 뿐이라 SDK level 이진화 의미론에서 완전히 독립된다.
     * 490x600 기준 수 ms (labelPrintExecutor 스레드에서 실행).
     */
    private static Bitmap binarizeForPrint(Bitmap src) {
        final int w = src.getWidth();
        final int h = src.getHeight();
        final int[] pixels = new int[w * h];
        src.getPixels(pixels, 0, w, 0, 0, w, h);
        for (int i = 0; i < pixels.length; i++) {
            final int p = pixels[i];
            final int a = p >>> 24;
            int r = (p >> 16) & 0xFF;
            int g = (p >> 8) & 0xFF;
            int b = p & 0xFF;
            if (a < 255) {
                // 투명 픽셀은 흰 배경에 합성 (painter 가 흰 배경을 먼저 칠하므로 방어용).
                r = (r * a + 255 * (255 - a)) / 255;
                g = (g * a + 255 * (255 - a)) / 255;
                b = (b * a + 255 * (255 - a)) / 255;
            }
            final int lum = (r * 299 + g * 587 + b * 114) / 1000;
            pixels[i] = (lum < BINARIZE_THRESHOLD) ? 0xFF000000 : 0xFFFFFFFF;
        }
        Bitmap out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        out.setPixels(pixels, 0, w, 0, 0, w, h);
        return out;
    }

    /** 진단용 — 이진화된(0xFF000000/0xFFFFFFFF 뿐) 비트맵의 검정 픽셀 비율. */
    private static double blackRatio(Bitmap b) {
        final int w = b.getWidth();
        final int h = b.getHeight();
        if (w <= 0 || h <= 0) return 0.0;
        final int[] pixels = new int[w * h];
        b.getPixels(pixels, 0, w, 0, 0, w, h);
        int black = 0;
        for (int p : pixels) {
            if ((p & 0x00FFFFFF) == 0) black++;
        }
        return (double) black / pixels.length;
    }

    private static void safeClearOutput() {
        try {
            sSdk.clearOutput();
        } catch (Exception e) {
            Log.w(TAG, "clearOutput failed: " + e.getMessage());
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 해제
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * USB detach 통지 (MainActivity 리시버, 메인 스레드). 블로킹 금지 — 플래그로 대기 루프를
     * 깨우고 close 는 백그라운드로 위임한다.
     */
    public static void onUsbDetached(UsbDevice device) {
        if (device == null || device.getVendorId() != BIXOLON_VENDOR_ID) return;
        Log.i(TAG, "[DETACH] " + device.getDeviceName());
        sDetachRequested = true;
        new Thread(BixolonPosDriver::close, "bixolon-pos-detach-close").start();
    }

    public static synchronized void close() {
        closeLocked();
    }

    /** 클래스 lock 하에서만 호출. */
    private static void closeLocked() {
        if (sSdk != null) {
            log("[CLOSE] Closing G30 connection");
            try {
                if (sSdk.getClaimed()) {
                    sSdk.setDeviceEnabled(false);
                    sSdk.release();
                }
                sSdk.close();
            } catch (Exception e) {
                Log.w(TAG, "close failed: " + e.getMessage());
            }
            sSdk = null;
        }
        sConnected = false;
        sDetachRequested = false;
    }

    // ─────────────────────────────────────────────────────────────────────────

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void logElapsed(String orderTag, String message, long startTime) {
        long elapsed = System.currentTimeMillis() - startTime;
        log(orderTag + " " + message + " (" + elapsed + "ms)");
    }

    private static void log(String message) {
        String logLine = "[BixolonPos] " + message;
        Log.i(TAG, message);
        if (sActivity != null) {
            sActivity.appendLogToFile(logLine);
        }
    }
}
