package co.kr.waldlust.order.receive.util.print;

import android.content.Context;
import android.graphics.Bitmap;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Message;
import android.util.Log;

import androidx.annotation.NonNull;

import com.bixolon.labelprinter.BixolonLabelPrinter;

import java.util.concurrent.atomic.AtomicInteger;

import co.kr.waldlust.order.receive.MainActivity;

/**
 * BIXOLON XD5-40d 라벨 프린터 드라이버 (USB 전용).
 *
 * <p>{@link LabelPrinter}(Caysn/REXOD) 와 동일한 계약을 유지한다:
 * <ul>
 *   <li>{@code printBitmap} 은 synchronized + 동기 블로킹 — 다음 호출의 진입을 자연 직렬화</li>
 *   <li>용지없음/커버열림 → 운영자 개입 신뢰, 무한 복구대기 후 인쇄 재개 (false 반환 안 함)</li>
 *   <li>그 외 프린터 에러 → 0.5초 짧은 게이트 후 false 반환 (Dart 측 1.5초 재시도 위임)</li>
 *   <li>★ 중복 인쇄 방지(submit-wins): 인쇄 데이터 전송이 완료된 뒤에는 상태 조회 실패나
 *       USB 이벤트로 false 를 반환하지 않는다. false 를 주면 Dart 재시도가 같은 라벨을
 *       한 장 더 발사한다 (Caysn 745번 2장 사고와 동일 뿌리).</li>
 * </ul>
 *
 * <p>SDK 특성 (V2.1.1 bytecode 검증):
 * <ul>
 *   <li>{@code connect(UsbDevice)} 는 인자를 무시하고 내부에서 VID 0x1504 + printer
 *       class(7/1/2) 를 자체 enumerate 하여 연결한다. 실패 시 null 반환.</li>
 *   <li>{@code getStatus(boolean): byte[]} / {@code endTransactionPrint(): int} 는
 *       동기 API — Handler 이벤트에 의존하지 않는다. Handler 는 연결 상태 로깅 전용.</li>
 *   <li>SDK 는 USB 권한을 요청하지 않는다 → 권한 확보는 이 클래스 책임
 *       (device_filter attach 승계가 1차, requestPermission 폴링이 fallback).</li>
 * </ul>
 *
 * <p>PAUSED_IN_PEELER_UNIT 은 이 기종에서 <b>실제로 동작한다.</b> 2026-07-23 실기기 8장 주문
 * 실증 — 라벨마다 떼기대기에 진입했고 사용자가 떼는 즉시 다음 장이 인쇄됐다(빨리 떼면
 * ≈1.9초, 늦게 떼면 6~8초로 소요시간이 사용자 행동과 정확히 상관). 즉 표준기에도 라벨 회수
 * 센서가 활성이며 Caysn INFO_PAPERNOFETCH 와 동일한 운영 모델(떼야 다음 장)이다.
 * (구현 시점의 "표준기는 필러 미장착" 가정은 이 실측으로 기각됐다. 그 낡은 주석이 비프음
 * 작업의 착수를 한 번 막았다.)
 *
 * <p><b>이 기종에는 버저가 없다 (2026-08-07 실기기 확정).</b> 앞 라벨 미회수 보류 상태를
 * 5회 만들어도 무음이었고, 커버열림·용지없음 같은 <b>진짜 에러에서도 소리가 나지 않는다.</b>
 * SDK 전수 조사(V2.1.1 jar / libcommon / libbxl_common.so / Windows BXLLAPI V3.10)에서도
 * buzzer 제어 API 는 0건이었다. 따라서 Caysn 의 비프음 알림에 대응하는 기능이 이 경로에는
 * <b>존재하지 않는다</b> — 필요하면 앱이 내야 한다.
 *
 * <p>★ 그럼에도 불변식은 유지한다: <b>떼지 않은 상태에서 다음 인쇄 명령이 펌웨어에 도달한다.</b>
 * 비프음은 이 설계의 <b>계기였을 뿐 근거가 아니다.</b> 완료 판정이 내 라벨을 뗄 때까지
 * 기다리면 (1) 다음 제출이 클래스 lock 에 막혀 큐 전체가 사람 손을 기다리고, (2) 그 대기가
 * "인쇄 시작 시 필러가 비어 있다" 를 암묵적으로 보장해 주던 탓에 완료 판정이 레벨 검사로
 * 버텨 왔다 — 대기를 되돌리면 그 레벨 검사도 함께 돌아와야 하고, 그건 배출 전 라벨을 완료로
 * 판정하는 결함으로 되돌아가는 것이다. <b>"비프음이 없으니 대기를 되살려도 된다" 는 추론은
 * 틀렸다.</b> Windows Caysn 이 이 대기를 성공 경로에 두었다가 겪은 사고(4f222b3) 참조.
 */
public class BixolonLabelDriver {
    private static final String TAG = "BixolonLabelDriver";

    /** BIXOLON vendor id (0x1504 = 5380). device_filter.xml 과 동기 유지. */
    public static final int BIXOLON_VENDOR_ID = 0x1504;

    // ── 라벨 미디어: RXLA-561 과 동일 규격 (이미지 490x600 dots ≈ 61x75mm @203dpi, 갭 용지) ──
    private static final int LABEL_WIDTH_DOTS = 490;
    private static final int LABEL_LENGTH_DOTS = 600;
    /** 라벨 간 갭 ≈ 3mm. 실기기 검증(P3)에서 오프셋 밀리면 조정. */
    private static final int LABEL_GAP_DOTS = 24;
    /** drawBitmap level 인자 — 사전 이진화(BINARIZE_THRESHOLD) 후에는 픽셀이 순흑/순백뿐이라 무의미. */
    private static final int DRAW_LEVEL = 50;

    /**
     * 사전 이진화 임계값 (luminance &lt; threshold → 검정).
     *
     * <p>실기기(XD5-40d) 검증: SDK drawBitmap 의 level 이진화는 임계가 낮게 동작해
     * level=50 에서 AA 얇은 글자·1px 구분선(AA 로 회색화)·black26 구분자(흰 배경
     * 합성 시 ≈189)가 소실됐다 (순흑 로고/큰 글자만 선명). SDK 에 맡기지 않고
     * Java 에서 결정론적으로 이진화해 Caysn thresholding 출력과 시각 동등을 맞춘다.
     *
     * <p>값 근거: 라벨 팔레트의 가장 밝은 잉크가 black26(≈189) 이므로 그보다 높게,
     * 흰 배경(255) 과는 여유를 두고 210. 출력이 너무 두꺼우면 낮추고 얇은 요소가
     * 빠지면 올린다.
     */
    private static final int BINARIZE_THRESHOLD = 210;

    /**
     * {@code endTransactionPrint()} 의 성공 반환값 (bytecode 확인 — RC 코드 아님):
     * write 성공 + 응답 수신 = 3, write 실패 또는 응답 없음 = -1 뿐이며
     * RC_SUCCESS(0) 는 반환하지 않는다. != RC_SUCCESS 로 검사하면 성공을 실패로
     * 오판해 Dart 재시도 → 중복 인쇄를 유발한다 (첫 실기기 테스트 사고).
     */
    private static final int END_TRANSACTION_OK = 3;

    /** USB 권한 다이얼로그 대기 (200ms 폴링). */
    private static final long PERMISSION_WAIT_MS = 30_000L;
    /** 회복 불가 에러(커터/과열/센싱/리본)의 짧은 게이트 — 피크타임 큐 막힘 방지. */
    private static final long ERROR_QUICK_GATE_MS = 500L;
    /** 직전 라벨 buffer building/printing 완료 대기. */
    private static final long IDLE_WAIT_MS = 5_000L;
    /** 인쇄 완료 폴링 timeout — Caysn QueryPrintResult 30초와 동일. */
    private static final long PRINT_RESULT_TIMEOUT_MS = 30_000L;
    private static final long STATUS_POLL_INTERVAL_MS = 200L;
    private static final long RECOVERY_HEARTBEAT_MS = 60_000L;

    /**
     * 완료 신호(peel edge / busy 하강)를 하나도 관측하지 못했을 때 idle 레벨만 보고
     * 완료로 받아들이기까지의 최소 체류 시간.
     *
     * <p>두 경우에 쓰인다: ① BASIC variant(1바이트 응답) — byte1 이 0 패딩이라 peel/busy
     * 신호가 아예 없다. ② 인쇄가 폴링 간격보다 빨라 busy 상승을 한 번도 못 본 경우.
     * 이 안전망이 없으면 두 경우 모두 30초를 소진하고 false 를 반환해 Dart 재시도가
     * <b>같은 라벨을 한 장 더 인쇄</b>한다.
     *
     * <p>기준선은 {@code pollStart} 다 — 떼기대기/복구대기에서 리셋되므로, 보류가 풀린
     * 직후(펌웨어가 아직 인쇄를 시작하지 않은 창)에 이 폴백이 먼저 터지지 않는다.
     */
    private static final long MIN_PRINT_DWELL_MS = 1_000L;

    /** 이상 프레임(직전 명령 응답 잔여 추정)을 흘려보내는 재읽기 상한. */
    private static final int STATUS_DRAIN_ATTEMPTS = 3;

    private static MainActivity sActivity = null;
    /** 클래스 lock 으로 보호. 연결마다 재생성 (SDK 내부 상태 초기화 보장). */
    private static BixolonLabelPrinter sSdk = null;
    /** SDK 이벤트 수신용 단일 HandlerThread — 프로세스 생애 동안 재사용. */
    private static HandlerThread sEventThread = null;
    private static boolean sMediaConfigured = false;
    private static final AtomicInteger printCount = new AtomicInteger(0);

    /**
     * USB detach 통지 플래그. onUsbDetached 는 MainActivity 리시버(메인 스레드)에서
     * 호출되는데, printBitmap 이 복구대기 등으로 클래스 lock 을 오래 쥘 수 있어
     * 메인 스레드가 synchronized close() 에 직접 들어가면 ANR 위험이 있다.
     * 플래그만 세워 대기 루프를 깨우고, 실제 close 는 백그라운드 스레드에서 수행한다.
     */
    private static volatile boolean sDetachRequested = false;

    /**
     * PAUSED_IN_PEELER 의 false→true 상승 edge 누적 횟수.
     *
     * <p>"내 라벨이 물리적으로 배출됐는가" 를 판정하는 주 신호다. 레벨이 아니라 edge 여야
     * 하는 이유: 앞 라벨이 안 떼어져 있으면 레벨은 이미 true 라 "내 라벨이 나왔는가" 를
     * 구별할 수 없다. 보류 상황에서도 edge 는 반드시 생긴다 —
     * 앞 라벨 peel(true) → 운영자가 뗌(false) → 붙잡힌 페이지 인쇄(true).
     *
     * <p>★ 어디서도 리셋하지 않는다({@link #closeLocked()} 포함). 판정이 {@code !=} 비교라
     * 리셋이 "변했다" 로 읽혀 <b>인쇄되지 않은 라벨을 완료로 판정</b>한다. Caysn
     * {@code LabelPrinter.paperNoFetchRiseCount} 와 Windows {@code _paperNoFetchRiseCount}
     * 도 같은 이유로 단조 카운터다.
     */
    private static volatile int sPeelRiseCount = 0;

    /**
     * 직전 상태 읽기에서 관측한 peel 레벨 (edge 검출용).
     *
     * <p>이것도 리셋하지 않는다. false 로 되돌리면 재연결 직후 첫 읽기가 <b>없던 edge 를
     * 만들어낸다</b>. 놓친 edge 는 busy 신호로 폴백되지만(안전), 만들어낸 edge 는 곧바로
     * 오검출(false completion)이 된다 — 해악이 비대칭이므로 항상 후자를 피한다.
     */
    private static volatile boolean sLastPeelLevel = false;

    public static void init(MainActivity activity) {
        sActivity = activity;
    }

    /**
     * VID 0x1504 장치 존재 여부 — NativeMethodHandler 의 벤더 라우팅 판정.
     * UsbManager.getDeviceList() 는 binder 1회 수준이라 인쇄마다 재평가해도 저렴하고,
     * attach/detach 후 stale 캐시 버그를 원천 차단한다.
     */
    public static boolean isBixolonAttached(Context ctx) {
        UsbManager usbManager = (UsbManager) ctx.getSystemService(Context.USB_SERVICE);
        if (usbManager == null) return false;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            if (device.getVendorId() == BIXOLON_VENDOR_ID) return true;
        }
        return false;
    }

    /**
     * 라벨 한 장을 인쇄한다. 전 구간 동기 블로킹 — labelPrintExecutor(단일 스레드)에서
     * 호출되므로 라벨 간 직렬화는 executor + synchronized 로 이중 보장된다.
     */
    public static synchronized boolean printBitmap(Bitmap bitmap,
                                                   String orderNo,
                                                   int labelIndex,
                                                   int totalLabels) {
        final int seq = printCount.incrementAndGet();
        final long startTime = System.currentTimeMillis();
        final String orderTag = "[" + orderNo
                + (totalLabels > 1 ? " " + labelIndex + "/" + totalLabels : "") + "]";
        log("#" + seq + " " + orderTag + " 출력시작");

        try {
            // ── 1. lazy 연결 (+ 연결 직후 1회 미디어 설정) ─────────────────────
            if (!ensureConnectedLocked(seq, orderTag)) {
                long elapsed = System.currentTimeMillis() - startTime;
                log("#" + seq + " " + orderTag + " 실패 [연결오류] (" + elapsed + "ms)");
                return false;
            }

            // ── 2. 진입 게이트: 프린터 상태 확인 ─────────────────────────────
            // byte0: 에러 비트 (0x00 = 정상), byte1: 버퍼/필러 상태.
            byte[] status = readStatusLocked();
            if (status == null) {
                // 연결 직후 상태 읽기 실패 = 연결이 사실상 죽음 → 재연결은 다음 시도에.
                closeLocked();
                long elapsed = System.currentTimeMillis() - startTime;
                log("#" + seq + " " + orderTag + " 실패 [상태조회 불가 — 연결오류] ("
                        + elapsed + "ms)");
                return false;
            }

            if (isRecoverableError(status)) {
                // 용지없음/커버열림 → 운영자 개입 신뢰, 무한 복구대기 (Caysn 1-B-① 동일).
                if (!waitOperatorRecoveryLocked(seq, orderTag, status)) {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log("#" + seq + " " + orderTag + " 실패 [복구대기 중단] (" + elapsed + "ms)");
                    return false;
                }
            } else if (isAnyError(status)) {
                // 커터잼/과열/센싱실패/리본 등 → 0.5초 짧은 게이트 후 Dart 재시도 위임.
                sleep(ERROR_QUICK_GATE_MS);
                byte[] recheck = readStatusLocked();
                if (recheck == null || isAnyError(recheck)) {
                    long elapsed = System.currentTimeMillis() - startTime;
                    log("#" + seq + " " + orderTag + " 실패 [프린터 에러 "
                            + statusHex(recheck != null ? recheck : status)
                            + " — 재시도 위임] (" + elapsed + "ms)");
                    return false;
                }
            }

            // 직전 라벨의 buffer building/printing 완료 대기 (최대 5초) — 피크타임 race 게이트.
            waitIdleLocked();

            // ── 3. 인쇄: begin → drawBitmap → print → end (SLCS 트랜잭션 1회 flush) ──
            sSdk.beginTransactionPrint();
            int rcDraw = sSdk.drawBitmap(binarizeForPrint(bitmap), 0, 0,
                    LABEL_WIDTH_DOTS, DRAW_LEVEL, /*dithering=*/false);
            int rcPrint = sSdk.print(1, 1);
            if (rcDraw != BixolonLabelPrinter.RC_SUCCESS
                    || rcPrint != BixolonLabelPrinter.RC_SUCCESS) {
                // 트랜잭션 버퍼링 단계 실패 — 아직 아무것도 전송되지 않았으므로 재시도 안전.
                // endTransactionPrint 로 잔여 버퍼를 밀어내지 않도록 clearBuffer 로 폐기.
                sSdk.clearBuffer();
                sSdk.endTransactionPrint();
                long elapsed = System.currentTimeMillis() - startTime;
                log("#" + seq + " " + orderTag + " 실패 [드로우오류 rcDraw=" + rcDraw
                        + " rcPrint=" + rcPrint + " — 재시도 위임] (" + elapsed + "ms)");
                return false;
            }
            // peel edge 기준선. 이 값이 늘면 "내 라벨이 배출됐다".
            // 반드시 waitIdleLocked() 뒤에서 잡아야 한다 — 앞 라벨의 edge 를 내 것으로
            // 오인하지 않기 위함. 여기부터 endTransactionPrint 까지 상태 읽기는 없다.
            final int riseBefore = sPeelRiseCount;

            int rcEnd = sSdk.endTransactionPrint();
            if (rcEnd != END_TRANSACTION_OK) {
                // -1 은 "write 실패" 와 "제출 후 응답 없음(3초)" 을 구분하지 못한다.
                // 상태조회로 2차 판별: 프린터가 응답하면 인쇄 스트림도 도달했다고 보고
                // ★ submit-wins (false 면 Dart 재시도가 같은 라벨 중복 발사).
                byte[] probe = readStatusLocked();
                if (probe != null) {
                    log("#" + seq + " " + orderTag + " 전송응답없음 rc=" + rcEnd
                            + " — 상태응답 확인, submit-wins 진행");
                } else {
                    // 상태조회도 불가 = 연결 자체가 죽음 — 미전송으로 보고 재시도 위임.
                    closeLocked();
                    long elapsed = System.currentTimeMillis() - startTime;
                    log("#" + seq + " " + orderTag + " 실패 [전송오류 rc=" + rcEnd
                            + " — 재시도 위임] (" + elapsed + "ms)");
                    return false;
                }
            }

            // ── 4. 완료 폴링 (Caysn QueryPrintResult 등가, 최대 30초) ─────────
            // 여기서부터는 submit-wins 구간: 상태 읽기 실패/USB 끊김은 성공 처리.
            String doneVia = waitPrintCompleteLocked(seq, orderTag, riseBefore);
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " " + orderTag
                    + (doneVia != null
                            ? " 출력끝 (" + elapsed + "ms, " + doneVia + ")"
                            : " 실패 (" + elapsed + "ms)"));
            return doneVia != null;

        } catch (Exception e) {
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " " + orderTag + " 실패 [예외: " + e.getMessage() + "] ("
                    + elapsed + "ms)");
            Log.e(TAG, "[ERROR] " + e.getMessage(), e);
            closeLocked();
            return false;
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 연결 관리
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * 앱 시작 시점의 warm-up — 연결(+연결당 1회 미디어 설정)만 수행. 인쇄는 하지 않는다.
     *
     * <p>{@link LabelPrinter#warmup(int)} 의 BIXOLON 대응물이다. 이 경로는 인쇄 안에서
     * 이미 권한 요청과 폴링 대기({@link #ensureConnectedLocked})를 하므로 Caysn 만큼
     * 콜드스타트 실패에 취약하지 않지만, 두 가지 이유로 함께 둔다:
     * ① SDK {@code connect()} 자체의 지연(인스턴스 생성 + enumerate + interface claim)을
     * 첫 주문에서 빼기 위함, ② 벤더 분기를 인쇄 경로와 동일하게 유지해 "warm-up 이
     * 도는 기종과 안 도는 기종" 이라는 비대칭을 만들지 않기 위함.
     *
     * <p>{@code seq=0} / {@code orderTag="[warmup]"} 로 남기므로 {@code printCount} 는
     * 건드리지 않는다 — 첫 인쇄가 계속 {@code #1} 이어야 운영 로그 해석이 유지된다.
     */
    public static synchronized boolean warmup() {
        try {
            return ensureConnectedLocked(0, "[warmup]");
        } catch (Exception e) {
            log("[warmup] 예외: " + e.getMessage());
            return false;
        }
    }

    /** 연결 보장 + 연결 직후 1회 미디어 설정. 실패 시 false. 클래스 lock 하에서만 호출. */
    private static boolean ensureConnectedLocked(int seq, String orderTag) {
        if (sDetachRequested) {
            // detach 통지 후 아직 close 가 못 들어온 상태 — 여기서 정리하고 재시도.
            closeLocked();
        }
        if (sSdk != null && sSdk.isConnected()) {
            return true;
        }
        closeLocked();

        if (sActivity == null) {
            Log.e(TAG, "ensureConnected: not initialized (init() not called)");
            return false;
        }
        UsbManager usbManager =
                (UsbManager) sActivity.getSystemService(Context.USB_SERVICE);
        if (usbManager == null) return false;

        UsbDevice target = null;
        for (UsbDevice device : usbManager.getDeviceList().values()) {
            if (device.getVendorId() == BIXOLON_VENDOR_ID) {
                target = device;
                break;
            }
        }
        if (target == null) {
            log("#" + seq + " " + orderTag + " 연결불가 [BIXOLON 장치 없음]");
            return false;
        }

        // USB 권한: device_filter attach 승계가 1차. 없으면 다이얼로그 요청 후 폴링 대기.
        if (!usbManager.hasPermission(target)) {
            log("#" + seq + " " + orderTag + " USB 권한 요청 "
                    + String.format("VID:0x%04X PID:0x%04X",
                            target.getVendorId(), target.getProductId()));
            requestUsbPermission(usbManager, target);
            long waitStart = System.currentTimeMillis();
            while (!usbManager.hasPermission(target)
                    && (System.currentTimeMillis() - waitStart) < PERMISSION_WAIT_MS) {
                if (sDetachRequested || Thread.currentThread().isInterrupted()) return false;
                sleep(STATUS_POLL_INTERVAL_MS);
            }
            if (!usbManager.hasPermission(target)) {
                log("#" + seq + " " + orderTag + " 연결불가 [USB 권한 거부/시간초과]");
                return false;
            }
        }

        // SDK 인스턴스는 연결마다 재생성 — 내부 connectivity 상태 초기화 보장.
        sSdk = new BixolonLabelPrinter(
                sActivity.getApplicationContext(), obtainEventHandler(), eventLooper());

        // 주의: connect(UsbDevice) 는 인자를 무시하고 SDK 가 VID 0x1504 를 자체 탐색한다.
        String connected = sSdk.connect(target);
        if (!sSdk.isConnected()) {
            log("#" + seq + " " + orderTag + " 연결불가 [connect 실패: " + connected + "]");
            closeLocked();
            return false;
        }
        log("#" + seq + " " + orderTag + " 연결됨 "
                + String.format("VID:0x%04X PID:0x%04X", target.getVendorId(),
                        target.getProductId()));

        // 미디어 설정은 연결당 1회 (SLCS 설정은 프린터가 유지).
        if (!sMediaConfigured) {
            int rcW = sSdk.setWidth(LABEL_WIDTH_DOTS);
            int rcL = sSdk.setLength(LABEL_LENGTH_DOTS, LABEL_GAP_DOTS,
                    BixolonLabelPrinter.MEDIA_TYPE_GAP, 0);
            if (rcW != BixolonLabelPrinter.RC_SUCCESS
                    || rcL != BixolonLabelPrinter.RC_SUCCESS) {
                // 설정 실패는 치명 아님(프린터 자체 보존값 사용) — 기록만 남긴다.
                log("미디어 설정 경고 rcWidth=" + rcW + " rcLength=" + rcL);
            }
            sMediaConfigured = true;
        }
        return true;
    }

    /**
     * 권한 요청은 {@link UsbPermissionHelper} 로 위임한다 — Caysn 경로와 같은 규칙
     * (Android 12+ FLAG_MUTABLE)을 쓰기 위해 공용화했다.
     */
    private static void requestUsbPermission(UsbManager usbManager, UsbDevice device) {
        UsbPermissionHelper.request(sActivity, usbManager, device);
    }

    /** SDK 이벤트 수신용 HandlerThread (프로세스 생애 재사용, lazy 생성). */
    private static android.os.Looper eventLooper() {
        if (sEventThread == null || !sEventThread.isAlive()) {
            sEventThread = new HandlerThread("bixolon-label-events");
            sEventThread.start();
        }
        return sEventThread.getLooper();
    }

    /** 연결 상태 변화만 로깅하는 최소 Handler. 인쇄 판정은 동기 API 가 담당. */
    private static Handler obtainEventHandler() {
        return new Handler(eventLooper()) {
            @Override
            public void handleMessage(@NonNull Message msg) {
                if (msg.what == BixolonLabelPrinter.MESSAGE_STATE_CHANGE) {
                    String state;
                    switch (msg.arg1) {
                        case BixolonLabelPrinter.STATE_CONNECTED:  state = "CONNECTED"; break;
                        case BixolonLabelPrinter.STATE_CONNECTING: state = "CONNECTING"; break;
                        default:                                   state = "NONE"; break;
                    }
                    Log.i(TAG, "[EVENT] state=" + state);
                }
                // MESSAGE_READ/OUTPUT_COMPLETE 등은 동기 API 를 쓰므로 무시.
            }
        };
    }

    /**
     * 인쇄 전 사전 이진화 — luminance &lt; {@link #BINARIZE_THRESHOLD} → 순흑, 그 외 순백.
     * 결과 픽셀이 0/255 뿐이라 SDK level 이진화 의미론에서 완전히 독립된다.
     * 490x600 기준 수 ms (labelPrintExecutor 스레드에서 실행).
     *
     * <p>package-private — {@link BixolonPosDriver}(G30, UPOS SDK)도 같은 근거(SDK 자체
     * 이진화가 저임계로 동작해 얇은 요소가 소실)로 재사용한다. 값 자체는 이 클래스가
     * 진실의 근원이다.
     */
    static Bitmap binarizeForPrint(Bitmap src) {
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

    // ─────────────────────────────────────────────────────────────────────────
    // 상태 게이트
    // ─────────────────────────────────────────────────────────────────────────

    /** 상태 variant 미확정 (연결 직후). */
    private static final int STATUS_VARIANT_UNKNOWN = 0;
    /** getStatus(true) 가 2바이트(에러+버퍼) 응답 — byte1 게이트 사용 가능. */
    private static final int STATUS_VARIANT_EXTENDED = 1;
    /** 1바이트(에러만) 응답 — byte1 은 0 으로 정규화 (busy/필러 게이트는 no-op). */
    private static final int STATUS_VARIANT_BASIC = 2;

    private static int sStatusVariant = STATUS_VARIANT_UNKNOWN;

    /** byte0 에 SDK 가 정의한 에러 비트 전체 (0xFC). 그 밖의 비트가 서면 상태 프레임이 아니다. */
    private static final int STATUS0_DEFINED_BITS =
            (BixolonLabelPrinter.STATUS_1ST_BYTE_PAPER_EMPTY & 0xFF)
                    | (BixolonLabelPrinter.STATUS_1ST_BYTE_COVER_OPEN & 0xFF)
                    | (BixolonLabelPrinter.STATUS_1ST_BYTE_CUTTER_JAMMED & 0xFF)
                    | (BixolonLabelPrinter.STATUS_1ST_BYTE_TPH_OVERHEAT & 0xFF)
                    | (BixolonLabelPrinter.STATUS_1ST_BYTE_AUTO_SENSING_FAILURE & 0xFF)
                    | (BixolonLabelPrinter.STATUS_1ST_BYTE_RIBBON_END_ERROR & 0xFF);

    /** byte1 에 SDK 가 정의한 버퍼/필러 비트 전체 (0xE0). */
    private static final int STATUS1_DEFINED_BITS =
            (BixolonLabelPrinter.STATUS_2ND_BYTE_BUILDING_IN_IMAGE_BUFFER & 0xFF)
                    | (BixolonLabelPrinter.STATUS_2ND_BYTE_PRINTING_IN_IMAGE_BUFFER & 0xFF)
                    | (BixolonLabelPrinter.STATUS_2ND_BYTE_PAUSED_IN_PEELER_UNIT & 0xFF);

    /**
     * 이 바이트쌍이 상태 프레임으로 성립하는가 (정의되지 않은 비트가 없는가).
     *
     * <p>실기기에서 인쇄 직후 폴링이 {@code 0x5630} 을 반복해서 읽었다 — 비트로 풀면
     * "커버열림+헤드과열+리본소진 동시" 인데 프린터는 정상 인쇄 중이었고, <b>두 바이트 모두
     * 미정의 비트</b>(byte0 의 0x02, byte1 의 0x10)를 갖고 있었다. ASCII 로는 {@code "V0"} 라
     * 직전 명령 응답의 잔여 바이트를 상태로 읽은 것으로 본다.
     *
     * <p>이 프레임은 두 가지 피해를 동시에 낸다:
     * <ul>
     *   <li>byte0 의 0x40 → <b>없는 커버열림</b>으로 복구대기 진입 (로그 오염)</li>
     *   <li>byte1 의 0x20 → <b>없던 peel 상승 edge 를 만들어내</b> 인쇄가 끝나기도 전에
     *       완료 판정. 실기기 8장 로그에서 4장이 ~400ms 에 조기 완료됐다.</li>
     * </ul>
     *
     * <p>BASIC variant 는 byte1 을 0 으로 패딩하므로 이 검사를 그대로 통과한다.
     */
    private static boolean isPlausibleStatus(byte[] status) {
        return ((status[0] & 0xFF) & ~STATUS0_DEFINED_BITS) == 0
                && ((status[1] & 0xFF) & ~STATUS1_DEFINED_BITS) == 0;
    }

    private static byte[] readStatusLocked() {
        byte[] status = readValidatedStatusLocked();
        if (status != null) {
            // 모든 상태 읽기(진입 게이트/idle 게이트/완료 폴링/복구 대기)가 이 함수를
            // 지나므로, 레벨 캐시가 호출 사이에 stale 해지지 않는다. Caysn 이 SDK status
            // 콜백에서 하는 edge 검출의 폴링판 등가물이다.
            boolean peel = isPausedInPeeler(status);
            if (!sLastPeelLevel && peel) sPeelRiseCount++;
            sLastPeelLevel = peel;
        }
        return status;
    }

    /**
     * 상태 프레임 검증 래퍼. 미정의 비트가 섞인 프레임({@link #isPlausibleStatus})은 상태가
     * 아니라 <b>직전 명령 응답의 잔여</b>로 보고, 즉시 한 번 더 읽어 버퍼를 흘려보낸다.
     * 재읽기도 이상하면 읽기 실패(null)로 넘겨 기존 재시도 경로가 받게 한다 —
     * ★ 절대 edge 카운터나 에러 판정에 먹이지 않는다.
     */
    private static byte[] readValidatedStatusLocked() {
        byte[] status = readStatusRawLocked();
        if (status == null || isPlausibleStatus(status)) return status;

        // 잔여가 한 프레임보다 길 수 있어 몇 번 더 흘려보낸다 (상한 있음 — 응답이 아예
        // 없으면 getStatus 자체가 최대 3초를 쓰므로 무한히 늘리지 않는다).
        final String first = statusHex(status);
        for (int i = 0; i < STATUS_DRAIN_ATTEMPTS; i++) {
            byte[] retry = readStatusRawLocked();
            if (retry == null) break;
            if (isPlausibleStatus(retry)) {
                log("상태프레임 이상 " + first + " — 상태 아님(응답 잔여 추정), "
                        + (i + 1) + "회 재읽기 후 " + statusHex(retry));
                return retry;
            }
        }
        log("상태프레임 이상 " + first + " — 재읽기 실패, 읽기오류로 처리");
        return null;
    }

    /**
     * 상태 동기 조회 (검증 전 원본). 항상 2바이트 배열(부족분 0 패딩) 또는 실패 시 null.
     *
     * <p>실기기(XD5-40d PID:0x0106) 검증: 상태 응답은 **1바이트일 수 있다** — 샘플도
     * {@code report.length == 2} 일 때만 byte1 을 읽는다. 과거 length&lt;2 를 실패로
     * 처리해 정상 응답을 "상태조회 불가" 로 오판하는 사고가 있었음.
     *
     * <p>연결당 1회 getStatus(true)(확장 상태 요청)를 시도해 variant 를 학습한다:
     * 2바이트 응답이면 extended 유지(byte1 게이트 활성), 아니면 basic 으로 고정.
     * 빈 응답(길이 0)만 실패 — SDK 는 미연결 시 빈 배열을 반환한다.
     *
     * <p>★ 직접 호출 금지. 반드시 {@link #readStatusLocked()} 를 통해 읽는다 — 그래야
     * 프레임 검증과 peel edge 갱신을 거친다.
     */
    private static byte[] readStatusRawLocked() {
        if (sSdk == null) return null;
        try {
            if (sStatusVariant == STATUS_VARIANT_UNKNOWN) {
                byte[] ext = sSdk.getStatus(true);
                if (ext != null && ext.length >= 2) {
                    sStatusVariant = STATUS_VARIANT_EXTENDED;
                    log("상태응답=확장(2바이트) — 라벨회수/버퍼 신호 사용");
                    return ext;
                }
                sStatusVariant = STATUS_VARIANT_BASIC;
                // ⚠️ BASIC 이면 byte1 이 0 패딩이라 떼기대기·busy 게이트가 영구 no-op 이 된다.
                //    이 사실을 로그에 남기지 않으면 "떼기대기 로그가 없다" 를 "필러가 없다"
                //    로 오독하게 된다 — 현장 진단에서 이 둘은 반드시 구분돼야 한다.
                log("상태응답=기본(1바이트) — 라벨회수/버퍼 신호 없음, 체류시간 폴백 사용");
                if (ext != null && ext.length == 1) {
                    return new byte[]{ext[0], 0};
                }
                // 확장 요청 무응답 — 기본 요청으로 fallthrough.
            }
            boolean extended = (sStatusVariant == STATUS_VARIANT_EXTENDED);
            byte[] status = sSdk.getStatus(extended);
            if (status == null || status.length == 0) return null;
            if (status.length == 1) return new byte[]{status[0], 0};
            return status;
        } catch (Exception e) {
            Log.w(TAG, "getStatus failed: " + e.getMessage());
            return null;
        }
    }

    private static boolean hasBit(byte value, byte mask) {
        return ((value & mask) & 0xFF) != 0;
    }

    /** byte0 에 에러 비트가 하나라도 있는가 (STATUS_NORMAL=0x00 이 정상). */
    private static boolean isAnyError(byte[] status) {
        return status[0] != BixolonLabelPrinter.STATUS_NORMAL;
    }

    /** 운영자 개입(용지 교체/커버 닫음)으로 회복 가능한 에러인가. */
    private static boolean isRecoverableError(byte[] status) {
        return hasBit(status[0], BixolonLabelPrinter.STATUS_1ST_BYTE_PAPER_EMPTY)
                || hasBit(status[0], BixolonLabelPrinter.STATUS_1ST_BYTE_COVER_OPEN);
    }

    /** byte1 의 buffer building/printing — 직전 작업 진행 중 표시. */
    private static boolean isBusy(byte[] status) {
        return hasBit(status[1], BixolonLabelPrinter.STATUS_2ND_BYTE_BUILDING_IN_IMAGE_BUFFER)
                || hasBit(status[1], BixolonLabelPrinter.STATUS_2ND_BYTE_PRINTING_IN_IMAGE_BUFFER);
    }

    /**
     * 배출된 라벨을 아직 회수하지 않아 펌웨어가 다음 페이지를 붙잡고 있다.
     * XD5-40d 표준기에서 실제로 동작하는 비트다 (클래스 javadoc 의 2026-07-23 실측 참조).
     * BASIC variant 에서는 byte1 이 0 패딩이라 항상 false — 신호 부재이지 필러 부재가 아니다.
     */
    private static boolean isPausedInPeeler(byte[] status) {
        return hasBit(status[1], BixolonLabelPrinter.STATUS_2ND_BYTE_PAUSED_IN_PEELER_UNIT);
    }

    private static String statusHex(byte[] status) {
        return String.format("0x%02X%02X", status[0] & 0xFF, status[1] & 0xFF);
    }

    /** 사람이 읽는 에러 라벨 — 운영자가 어떤 조치를 해야 하는지 즉시 식별용. */
    private static String describeRecoverable(byte[] status) {
        boolean noPaper = hasBit(status[0], BixolonLabelPrinter.STATUS_1ST_BYTE_PAPER_EMPTY);
        boolean coverOpen = hasBit(status[0], BixolonLabelPrinter.STATUS_1ST_BYTE_COVER_OPEN);
        if (noPaper && coverOpen) return "용지없음+커버열림";
        if (noPaper) return "용지없음";
        if (coverOpen) return "커버열림";
        return "복구대기";
    }

    /**
     * 용지없음/커버열림 무한 복구대기. 회복되면 true.
     * detach 나 상태조회 연속 실패(장치 소멸)면 false — 무한 스핀 방지.
     */
    private static boolean waitOperatorRecoveryLocked(int seq, String orderTag,
                                                      byte[] initialStatus) {
        final String entryPhase = describeRecoverable(initialStatus);
        log("#" + seq + " " + orderTag + " 복구대기 진입 [" + entryPhase + "] status="
                + statusHex(initialStatus));
        long waitStart = System.currentTimeMillis();
        long lastNotice = waitStart;
        int consecutiveReadFailures = 0;
        while (true) {
            if (sDetachRequested || Thread.currentThread().isInterrupted()) return false;
            sleep(STATUS_POLL_INTERVAL_MS);
            byte[] status = readStatusLocked();
            if (status == null) {
                // 복구대기 중 연결 소멸(전원 off/케이블 분리) — 15회(3초) 연속 실패면 포기.
                if (++consecutiveReadFailures >= 15) return false;
                continue;
            }
            consecutiveReadFailures = 0;
            if (!isRecoverableError(status)) {
                long waited = System.currentTimeMillis() - waitStart;
                log("#" + seq + " " + orderTag + " 복구감지 [" + entryPhase
                        + " → OK] wait=" + waited + "ms — 인쇄재개");
                return true;
            }
            long now = System.currentTimeMillis();
            if (now - lastNotice >= RECOVERY_HEARTBEAT_MS) {
                log("#" + seq + " " + orderTag + " 복구대기중 elapsed="
                        + ((now - waitStart) / 1000) + "s");
                lastNotice = now;
            }
        }
    }

    /** 직전 작업의 buffer building/printing 완료 대기 (최대 5초). 정상 흐름 무로그. */
    private static void waitIdleLocked() {
        long waitStart = System.currentTimeMillis();
        while ((System.currentTimeMillis() - waitStart) < IDLE_WAIT_MS) {
            if (sDetachRequested || Thread.currentThread().isInterrupted()) return;
            byte[] status = readStatusLocked();
            if (status == null || !isBusy(status)) return;
            sleep(50);
        }
    }

    /**
     * 인쇄 완료 폴링 — Caysn CP_Pos_QueryPrintResult 등가. 완료 사유 또는 실패 시 null.
     *
     * <p>완료 신호는 셋이며 <b>이 순서로</b> 평가한다. 순서 자체가 정확성의 일부다:
     * <ol>
     *   <li><b>peel 상승 edge</b>({@code 라벨나옴}/{@code 떼기대기}) — 내 라벨이 물리적으로
     *       배출됐다. 주 신호.</li>
     *   <li><b>떼기대기 분기</b> — edge 가 아직인데 peel 레벨이 true 면 앞 라벨이 남아
     *       내 페이지를 펌웨어가 붙잡고 있는 것이다. 무한 대기가 <b>옳다</b>. 아래 3·4 가
     *       이 구간에서 평가되지 않도록 반드시 그 앞에 있어야 한다 — 보류 중에도 이미지
     *       버퍼 빌드로 busy 가 잠깐 섰다가 내려갈 수 있고, 그때 3을 먼저 보면
     *       <b>아직 배출되지 않은 라벨을 완료로 판정</b>한다.</li>
     *   <li><b>busy 상승 후 하강</b>({@code 프린터응답}) — 인쇄 엔진이 한 장을 끝냈다.
     *       상승을 요구하는 이유: 제출 직후 sleep 없이 첫 폴링이 도는데, 펌웨어가 busy 를
     *       세우기 전이면 레벨만 보고 <b>인쇄 시작 전에 완료 판정</b>을 하게 된다.</li>
     *   <li><b>체류시간 폴백</b>({@code 상태정상}) — 위 둘을 모두 관측 못 한 경우
     *       ({@link #MIN_PRINT_DWELL_MS} 참조).</li>
     * </ol>
     *
     * <p>★ <b>내 라벨을 뗄 때까지 기다리지 않는다.</b> edge 를 받으면 peel 이 여전히 true
     * 여도 즉시 반환한다 — 클래스 javadoc 의 불변식(다음 인쇄 명령이 펌웨어에 도달) 참조.
     *
     * <p>★ submit-wins 구간: 인쇄 데이터는 이미 펌웨어에 전달됐다.
     * <ul>
     *   <li>상태조회 실패/USB 끊김 → 성공 (인쇄 직후 detach 하는 펌웨어 대응)</li>
     *   <li>인쇄 중 용지없음/커버열림 → 무한 복구대기 후 성공 — 실패를 주면 Dart
     *       재시도가 중복 인쇄. SLCS 펌웨어의 에러 복구 후 자동 재인쇄를 전제
     *       (P3 실기기 검증 항목 — 재인쇄 안 되면 이 분기만 실패로 조정)</li>
     *   <li>30초 내 신호 없음 → null (wedge — Dart 재시도 위임, Caysn timeout 동일)</li>
     * </ul>
     */
    private static String waitPrintCompleteLocked(int seq, String orderTag, int riseBefore) {
        long pollStart = System.currentTimeMillis();
        int consecutiveReadFailures = 0;
        boolean recoveryLogged = false;
        long fetchNotice = 0L;
        boolean heldInPeeler = false;
        boolean sawBusy = false;
        int busyIdlePolls = 0;
        while ((System.currentTimeMillis() - pollStart) < PRINT_RESULT_TIMEOUT_MS) {
            if (sDetachRequested || Thread.currentThread().isInterrupted()) {
                // 인쇄 제출 후 detach/인터럽트 — 출력 자체는 끝났다고 간주 (submit-wins).
                log("#" + seq + " " + orderTag + " 완료폴링 중단 (detach/interrupt) — submit-wins");
                return "연결끊김";
            }
            byte[] status = readStatusLocked(); // ← peel edge 는 여기서 갱신된다
            if (status == null) {
                if (++consecutiveReadFailures >= 5) {
                    log("#" + seq + " " + orderTag + " 완료폴링 상태조회 실패 — submit-wins");
                    return "상태조회불가";
                }
                sleep(STATUS_POLL_INTERVAL_MS);
                continue;
            }
            consecutiveReadFailures = 0;

            // ── 신호 ①: 내 라벨이 배출됐다. 떼기를 기다리지 않고 즉시 반환. ──────────
            if (sPeelRiseCount != riseBefore) {
                return heldInPeeler ? "떼기대기" : "라벨나옴";
            }

            if (isRecoverableError(status)) {
                // 인쇄 도중 용지소진/커버열림 race — 복구까지 무한 대기 후 성공 처리.
                if (!recoveryLogged) {
                    log("#" + seq + " " + orderTag + " 인쇄중 복구대기 진입 ["
                            + describeRecoverable(status) + "] status=" + statusHex(status));
                    recoveryLogged = true;
                }
                if (!waitOperatorRecoveryDuringPrint(seq, orderTag)) {
                    // 장치 소멸 — 제출은 끝났으므로 submit-wins.
                    return "장치소멸";
                }
                // 복구됨 — 펌웨어 재인쇄 진행을 기다리도록 폴링 타이머 리셋.
                pollStart = System.currentTimeMillis();
                continue;
            }

            // ── 신호 ②: 앞 라벨 미회수로 내 페이지가 펌웨어에 붙잡혀 있다 ───────────
            if (isPausedInPeeler(status)) {
                heldInPeeler = true;
                long now = System.currentTimeMillis();
                if (fetchNotice == 0L) {
                    // 키워드 "떼기대기" 는 Caysn 과 공통(운영 grep 계약). 다만 이 기종은
                    // 버저가 없어 Caysn 의 "비프음 울림" 을 그대로 쓰면 거짓이 된다.
                    log("#" + seq + " " + orderTag + " 떼기대기 (앞 라벨을 안 뗌 — 무음 보류)");
                    fetchNotice = now;
                } else if (now - fetchNotice >= RECOVERY_HEARTBEAT_MS) {
                    log("#" + seq + " " + orderTag + " 떼기대기중");
                    fetchNotice = now;
                }
                // 떼기 대기는 timeout 에 걸리지 않게 타이머 리셋. 체류시간 폴백의 기준선도
                // 함께 밀려, 보류가 풀린 직후 창에서 ④가 먼저 터지지 않는다.
                pollStart = System.currentTimeMillis();
                sleep(STATUS_POLL_INTERVAL_MS);
                continue;
            }

            if (isBusy(status)) {
                sawBusy = true;
                busyIdlePolls = 0;
            } else if (!isAnyError(status)) {
                // ── 신호 ③: busy 가 섰다가 내려감 ───────────────────────────────
                // ★ 한 폴링 더 확인하고 확정한다. peel 비트가 busy 하강보다 반 박자 늦게
                //   설 수 있는데, 여기서 곧바로 반환하면 그 edge 가 아직 세어지지 않은 채
                //   다음 라벨이 riseBefore 를 잡는다 → 앞 라벨의 edge 를 자기 것으로
                //   오인해 인쇄 시작 전에 완료 판정한다(귀속 어긋남이 이후 라벨로 연쇄).
                //   대기 중 edge 가 오면 루프 상단의 ①이 가져가므로 귀속이 바로잡힌다.
                if (sawBusy) {
                    if (++busyIdlePolls >= 2) return "프린터응답";
                } else if ((System.currentTimeMillis() - pollStart) >= MIN_PRINT_DWELL_MS) {
                    // ── 신호 ④: 체류시간 폴백 (BASIC variant / busy 미관측) ──────
                    return "상태정상";
                }
            }
            sleep(STATUS_POLL_INTERVAL_MS);
        }
        log("#" + seq + " " + orderTag + " 완료폴링 timeout status 미해제");
        return null;
    }

    /** 완료폴링 내부의 복구대기 (로그 중복 방지용 축약판). 회복 true / 장치소멸 false. */
    private static boolean waitOperatorRecoveryDuringPrint(int seq, String orderTag) {
        long waitStart = System.currentTimeMillis();
        long lastNotice = waitStart;
        int consecutiveReadFailures = 0;
        while (true) {
            if (sDetachRequested || Thread.currentThread().isInterrupted()) return false;
            sleep(STATUS_POLL_INTERVAL_MS);
            byte[] status = readStatusLocked();
            if (status == null) {
                if (++consecutiveReadFailures >= 15) return false;
                continue;
            }
            consecutiveReadFailures = 0;
            if (!isRecoverableError(status)) {
                long waited = System.currentTimeMillis() - waitStart;
                log("#" + seq + " " + orderTag + " 인쇄중 복구감지 wait=" + waited
                        + "ms — 인쇄재개 대기");
                return true;
            }
            long now = System.currentTimeMillis();
            if (now - lastNotice >= RECOVERY_HEARTBEAT_MS) {
                log("#" + seq + " " + orderTag + " 복구대기중 elapsed="
                        + ((now - waitStart) / 1000) + "s");
                lastNotice = now;
            }
        }
    }

    // ─────────────────────────────────────────────────────────────────────────
    // 해제
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * USB detach 통지 (MainActivity 리시버, 메인 스레드).
     * 블로킹 금지 — 플래그로 대기 루프를 깨우고 close 는 백그라운드로 위임한다.
     */
    public static void onUsbDetached(UsbDevice device) {
        if (device == null || device.getVendorId() != BIXOLON_VENDOR_ID) return;
        Log.i(TAG, "[DETACH] " + device.getDeviceName());
        sDetachRequested = true;
        new Thread(BixolonLabelDriver::close, "bixolon-detach-close").start();
    }

    public static synchronized void close() {
        closeLocked();
    }

    /** 클래스 lock 하에서만 호출. */
    private static void closeLocked() {
        if (sSdk != null) {
            log("[CLOSE] Closing BIXOLON label printer connection");
            try {
                sSdk.disconnect();
            } catch (Exception e) {
                Log.w(TAG, "disconnect failed: " + e.getMessage());
            }
            sSdk = null;
        }
        sMediaConfigured = false;
        sDetachRequested = false;
        sStatusVariant = STATUS_VARIANT_UNKNOWN;
        // ★ sPeelRiseCount / sLastPeelLevel 은 의도적으로 리셋하지 않는다 — 각 필드 주석 참조.
    }

    // ─────────────────────────────────────────────────────────────────────────

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static void log(String message) {
        String logLine = "[BixolonLabel] " + message;
        Log.i(TAG, message);
        if (sActivity != null) {
            sActivity.appendLogToFile(logLine);
        }
    }
}
