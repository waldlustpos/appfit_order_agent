package co.kr.waldlust.order.receive.util.print;

import android.app.PendingIntent;
import android.content.Context;
import android.content.Intent;
import android.graphics.Bitmap;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.os.Build;
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
 * <p>XD5-40d 표준기는 필러(peeler) 미장착 — Caysn 의 PAPERNOFETCH(떼기대기+buzzer)
 * 등가물이 없고 라벨이 연속 배출된다. PAUSED_IN_PEELER_UNIT 비트는 필러 장착기 방어용.
 */
public class BixolonLabelDriver {
    private static final String TAG = "BixolonLabelDriver";

    /** BIXOLON vendor id (0x1504 = 5380). device_filter.xml 과 동기 유지. */
    public static final int BIXOLON_VENDOR_ID = 0x1504;

    private static final String ACTION_USB_PERMISSION =
            "co.kr.waldlust.order.receive.BIXOLON_USB_PERMISSION";

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
            boolean printed = waitPrintCompleteLocked(seq, orderTag);
            long elapsed = System.currentTimeMillis() - startTime;
            log("#" + seq + " " + orderTag + " " + (printed ? "출력끝" : "실패")
                    + " (" + elapsed + "ms)");
            return printed;

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

    private static void requestUsbPermission(UsbManager usbManager, UsbDevice device) {
        int flags;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12+ 는 권한 승인 extra 를 시스템이 채워 넣기 위해 FLAG_MUTABLE 필요.
            flags = PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT;
        } else {
            flags = PendingIntent.FLAG_UPDATE_CURRENT;
        }
        PendingIntent permissionIntent = PendingIntent.getBroadcast(
                sActivity.getApplicationContext(), 0,
                new Intent(ACTION_USB_PERMISSION), flags);
        usbManager.requestPermission(device, permissionIntent);
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

    /**
     * 상태 동기 조회. 항상 2바이트 배열(부족분 0 패딩) 또는 실패 시 null 을 반환한다.
     *
     * <p>실기기(XD5-40d PID:0x0106) 검증: 상태 응답은 **1바이트일 수 있다** — 샘플도
     * {@code report.length == 2} 일 때만 byte1 을 읽는다. 과거 length<2 를 실패로
     * 처리해 정상 응답을 "상태조회 불가" 로 오판하는 사고가 있었음.
     *
     * <p>연결당 1회 getStatus(true)(확장 상태 요청)를 시도해 variant 를 학습한다:
     * 2바이트 응답이면 extended 유지(byte1 게이트 활성), 아니면 basic 으로 고정.
     * 빈 응답(길이 0)만 실패 — SDK 는 미연결 시 빈 배열을 반환한다.
     */
    private static byte[] readStatusLocked() {
        if (sSdk == null) return null;
        try {
            if (sStatusVariant == STATUS_VARIANT_UNKNOWN) {
                byte[] ext = sSdk.getStatus(true);
                if (ext != null && ext.length >= 2) {
                    sStatusVariant = STATUS_VARIANT_EXTENDED;
                    return ext;
                }
                sStatusVariant = STATUS_VARIANT_BASIC;
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

    /** 필러 유닛에 라벨 대기 중 (필러 장착기 한정 — 표준 XD5-40d 는 뜨지 않음). */
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
     * 인쇄 완료 폴링 — Caysn CP_Pos_QueryPrintResult 등가.
     *
     * <p>★ submit-wins 구간: 인쇄 데이터는 이미 펌웨어에 전달됐다.
     * <ul>
     *   <li>상태조회 실패/USB 끊김 → true (인쇄 직후 detach 하는 펌웨어 대응)</li>
     *   <li>인쇄 중 용지없음/커버열림 → 무한 복구대기 후 true — false 를 주면 Dart
     *       재시도가 중복 인쇄. SLCS 펌웨어의 에러 복구 후 자동 재인쇄를 전제
     *       (P3 실기기 검증 항목 — 재인쇄 안 되면 이 분기만 false 로 조정)</li>
     *   <li>필러 대기(PAUSED_IN_PEELER) → 떼기까지 무한 대기 후 true</li>
     *   <li>30초 내 busy 미해제 → false (wedge — Dart 재시도 위임, Caysn timeout 동일)</li>
     * </ul>
     */
    private static boolean waitPrintCompleteLocked(int seq, String orderTag) {
        long pollStart = System.currentTimeMillis();
        int consecutiveReadFailures = 0;
        boolean recoveryLogged = false;
        long fetchNotice = 0L;
        while ((System.currentTimeMillis() - pollStart) < PRINT_RESULT_TIMEOUT_MS) {
            if (sDetachRequested || Thread.currentThread().isInterrupted()) {
                // 인쇄 제출 후 detach/인터럽트 — 출력 자체는 끝났다고 간주 (submit-wins).
                log("#" + seq + " " + orderTag + " 완료폴링 중단 (detach/interrupt) — submit-wins");
                return true;
            }
            byte[] status = readStatusLocked();
            if (status == null) {
                if (++consecutiveReadFailures >= 5) {
                    log("#" + seq + " " + orderTag + " 완료폴링 상태조회 실패 — submit-wins");
                    return true;
                }
                sleep(STATUS_POLL_INTERVAL_MS);
                continue;
            }
            consecutiveReadFailures = 0;

            if (isRecoverableError(status)) {
                // 인쇄 도중 용지소진/커버열림 race — 복구까지 무한 대기 후 성공 처리.
                if (!recoveryLogged) {
                    log("#" + seq + " " + orderTag + " 인쇄중 복구대기 진입 ["
                            + describeRecoverable(status) + "] status=" + statusHex(status));
                    recoveryLogged = true;
                }
                if (!waitOperatorRecoveryDuringPrint(seq, orderTag)) {
                    // 장치 소멸 — 제출은 끝났으므로 submit-wins.
                    return true;
                }
                // 복구됨 — 펌웨어 재인쇄 진행을 기다리도록 폴링 타이머 리셋.
                pollStart = System.currentTimeMillis();
                continue;
            }

            if (isPausedInPeeler(status)) {
                long now = System.currentTimeMillis();
                if (fetchNotice == 0L) {
                    log("#" + seq + " " + orderTag + " 떼기대기 (PAUSED_IN_PEELER)");
                    fetchNotice = now;
                } else if (now - fetchNotice >= RECOVERY_HEARTBEAT_MS) {
                    log("#" + seq + " " + orderTag + " 떼기대기중");
                    fetchNotice = now;
                }
                // 떼기 대기는 timeout 에 걸리지 않게 타이머 리셋.
                pollStart = System.currentTimeMillis();
                sleep(STATUS_POLL_INTERVAL_MS);
                continue;
            }

            if (!isAnyError(status) && !isBusy(status)) {
                return true; // byte0 정상 + 버퍼 idle = 인쇄 완료.
            }
            sleep(STATUS_POLL_INTERVAL_MS);
        }
        log("#" + seq + " " + orderTag + " 완료폴링 timeout status 미해제");
        return false;
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
