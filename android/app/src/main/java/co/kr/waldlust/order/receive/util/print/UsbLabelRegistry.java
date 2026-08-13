package co.kr.waldlust.order.receive.util.print;

import android.graphics.Bitmap;
import android.hardware.usb.UsbDevice;
import android.util.Log;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import co.kr.waldlust.order.receive.MainActivity;

/**
 * USB Direct 라벨 프린터 <b>여러 대</b>를 타깃(제조 구역)별로 라우팅한다.
 *
 * <h3>왜 레지스트리인가</h3>
 * {@link LabelPrinter} 는 {@code static Pointer hPrinter} 한 개를 전제로 짜여 있어
 * 구조적으로 1대만 다룰 수 있다. Caysn SDK 자체도 동일 기종 2대를 지목할 수단이
 * 없다(포트명 4형식이 두 대에서 전부 같은 문자열 — 2026-08-13 확정).
 * USB Host API 는 {@link UsbDevice} 객체로 지목하므로 그 제약이 없고, 대신
 * "어느 구역이 어느 장치인가" 를 들고 있을 자리가 필요하다. 그게 여기다.
 *
 * <h3>연결을 유지한다</h3>
 * 인쇄마다 열고 닫지 않는다. open 은 커널 {@code usblp} 로부터 force-claim 을
 * 동반하고, 첫 open 은 USB 권한 승인 사이클을 지불할 수도 있다 — 그 비용을 주문
 * 처리 경로에서 치르면 "부팅 후 첫 라벨 연결오류" 가 재발한다. warm-up 에서
 * 미리 열어 두고 계속 들고 있는다.
 *
 * <h3>Caysn 과 혼용하지 않는다</h3>
 * 같은 장치를 Caysn 핸들과 동시에 claim 하면 서로 빼앗아 <b>조용히 인쇄를 잃는다</b>
 * (탈취당한 핸들이 한동안 살아 있는 것처럼 보이는 좀비 현상 실측). 그래서 Direct 로
 * 갈 때는 SDK 포트를 확실히 닫는다. 매장/단말 단위로 통째 전환하고 섞지 않는다.
 */
public final class UsbLabelRegistry {
    private static final String TAG = "UsbLabelRegistry";

    /** 한 장당 완료 대기 상한. 넘어도 peel 에 라벨이 있으면 계속 기다린다. */
    private static final long PRINT_CAP_MS = 30_000L;

    /** 버스 번호 → 열린 드라이버. */
    private static final Map<Integer, UsbLabelDriver> DRIVERS = new HashMap<>();

    /**
     * 버스 번호 → 그 드라이버가 열릴 때의 USB 노드 이름.
     *
     * <p>재열거되면 {@code /dev/bus/usb/003/005} 의 device 번호가 바뀐다(실측
     * 002→003→005). 노드가 달라졌으면 들고 있던 핸들은 이미 죽은 장치를 가리키므로
     * 버리고 다시 열어야 한다 — 이걸 안 보면 detach/attach 후 인쇄가 조용히 실패한다.
     */
    private static final Map<Integer, String> NODES = new HashMap<>();

    private UsbLabelRegistry() {
    }

    // ── 라우팅 ──────────────────────────────────────────────────────────────

    /**
     * 타깃에 배정된 프린터로 라벨 한 장을 인쇄하고 완료까지 판정한다.
     *
     * @param targetId     제조 구역 id. null/미매핑이면 폴백한다.
     * @param targetBusMap {targetId → 버스 번호}. Dart 설정이 매 호출 전달한다 —
     *                     네이티브에 설정 상태를 두지 않아야 설정 변경과 인쇄 사이의
     *                     순서 문제가 생기지 않는다.
     * @return {@link LabelPrinter} 와 <b>같은 3분류 계약</b>.
     */
    public static int printLabel(MainActivity activity,
                                 Bitmap bitmap,
                                 String targetId,
                                 Map<String, Integer> targetBusMap,
                                 String orderNo,
                                 int labelIndex,
                                 int totalLabels) {
        if (bitmap == null) return LabelPrinter.RESULT_RETRYABLE;

        // Direct 로 가는 동안 SDK 가 같은 장치를 물고 있으면 안 된다.
        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            Log.w(TAG, "Caysn close 예외: " + t.getMessage());
        }

        final UsbLabelDriver drv = acquire(activity, targetId, targetBusMap);
        if (drv == null) {
            Log.w(TAG, "[" + orderNo + "] 사용할 수 있는 프린터 없음 → 재시도가능");
            return LabelPrinter.RESULT_RETRYABLE;
        }

        final String tag = "[" + orderNo
                + (totalLabels > 1 ? " " + labelIndex + "/" + totalLabels : "")
                + " bus " + drv.getBusNumber() + "]";
        final int rc = drv.printLabelAwait(bitmap, PRINT_CAP_MS, tag);

        // 전송 실패(=미제출)는 연결이 상했을 가능성이 크다. 캐시를 버려 다음 인쇄가
        // 새로 열게 한다. 제출후무확인은 버리지 않는다 — 연결은 멀쩡한데 확인만
        // 못 한 경우라, 여기서 닫으면 멀쩡한 대기 상태를 깨뜨린다.
        if (rc == LabelPrinter.RESULT_RETRYABLE) {
            evict(drv.getBusNumber());
        }
        return rc;
    }

    /**
     * 타깃에 맞는 드라이버를 돌려준다. 없으면 연다.
     *
     * <p><b>폴백은 "다른 프린터로라도 인쇄" 다.</b> 지정 버스에 장치가 없으면
     * (케이블을 옮겼거나 프린터를 교체했거나) 살아 있는 첫 장치로 보낸다.
     * 근거: <b>안 나오는 비용 &gt; 엉뚱한 프린터에서 나오는 비용.</b> 후자는 운영자가
     * 손으로 분류하면 끝이지만, 전자는 누락 복구 경로를 타야 한다.
     */
    private static synchronized UsbLabelDriver acquire(MainActivity activity,
                                                       String targetId,
                                                       Map<String, Integer> targetBusMap) {
        final List<UsbDevice> devices = UsbLabelDriver.findDevices(activity);
        if (devices.isEmpty()) {
            closeAllLocked();
            return null;
        }

        Integer wanted = (targetId == null || targetBusMap == null)
                ? null : targetBusMap.get(targetId);

        UsbDevice chosen = null;
        if (wanted != null) {
            for (UsbDevice d : devices) {
                if (UsbLabelDriver.busNumberOf(d) == wanted) {
                    chosen = d;
                    break;
                }
            }
        }
        if (chosen == null) {
            chosen = devices.get(0);
            if (wanted != null) {
                Log.w(TAG, "타깃 " + targetId + " 의 bus " + wanted
                        + " 없음 → bus " + UsbLabelDriver.busNumberOf(chosen) + " 로 폴백");
            }
        }
        return openOrReuseLocked(activity, chosen);
    }

    private static UsbLabelDriver openOrReuseLocked(MainActivity activity, UsbDevice device) {
        final int bus = UsbLabelDriver.busNumberOf(device);
        final UsbLabelDriver cached = DRIVERS.get(bus);
        if (cached != null) {
            final boolean sameNode = device.getDeviceName().equals(NODES.get(bus));
            if (cached.isOpen() && sameNode) return cached;
            // 재열거됐거나 닫혔다 — 들고 있던 핸들은 죽은 장치를 가리킨다.
            Log.i(TAG, "bus " + bus + " 재연결 (노드 변경=" + !sameNode + ")");
            evictLocked(bus);
        }
        final UsbLabelDriver drv = new UsbLabelDriver(device);
        if (!drv.open(activity)) return null;
        DRIVERS.put(bus, drv);
        NODES.put(bus, device.getDeviceName());
        return drv;
    }

    // ── 수명 ────────────────────────────────────────────────────────────────

    /**
     * 배정된 프린터를 미리 열어 둔다.
     *
     * <p>USB 권한 승인 사이클을 시작 창에서 지불하기 위한 것이다 — 이걸 첫 주문이
     * 지불하면 "부팅 후 첫 라벨 연결오류" 가 그대로 재발한다.
     *
     * @return 연 장치 수
     */
    public static synchronized int warmup(MainActivity activity) {
        try {
            LabelPrinter.close();
        } catch (Throwable t) {
            Log.w(TAG, "Caysn close 예외: " + t.getMessage());
        }
        int opened = 0;
        for (UsbDevice d : UsbLabelDriver.findDevices(activity)) {
            if (openOrReuseLocked(activity, d) != null) opened++;
        }
        Log.i(TAG, "warmup — " + opened + "대 준비");
        return opened;
    }

    /** 연결된 라벨 프린터의 버스 번호 목록 (설정 UI 용, 오름차순). */
    public static List<Integer> connectedBuses(MainActivity activity) {
        final List<Integer> buses = new ArrayList<>();
        for (UsbDevice d : UsbLabelDriver.findDevices(activity)) {
            buses.add(UsbLabelDriver.busNumberOf(d));
        }
        return buses;
    }

    /** 지정 버스에 테스트 라벨 1장. 설정 화면의 물리 대조용. */
    public static int testPrint(MainActivity activity, int bus, Bitmap bitmap) {
        if (bitmap == null) return LabelPrinter.RESULT_RETRYABLE;
        try {
            LabelPrinter.close();
        } catch (Throwable ignored) {
        }
        UsbLabelDriver drv = null;
        synchronized (UsbLabelRegistry.class) {
            for (UsbDevice d : UsbLabelDriver.findDevices(activity)) {
                if (UsbLabelDriver.busNumberOf(d) == bus) {
                    drv = openOrReuseLocked(activity, d);
                    break;
                }
            }
        }
        if (drv == null) return LabelPrinter.RESULT_RETRYABLE;
        return drv.printLabelAwait(bitmap, PRINT_CAP_MS, "[테스트 bus " + bus + "]");
    }

    public static synchronized void closeAll() {
        closeAllLocked();
    }

    private static void closeAllLocked() {
        for (UsbLabelDriver d : DRIVERS.values()) {
            try {
                d.close();
            } catch (Throwable ignored) {
            }
        }
        DRIVERS.clear();
        NODES.clear();
    }

    private static synchronized void evict(int bus) {
        evictLocked(bus);
    }

    private static void evictLocked(int bus) {
        final UsbLabelDriver d = DRIVERS.remove(bus);
        NODES.remove(bus);
        if (d != null) {
            try {
                d.close();
            } catch (Throwable ignored) {
            }
        }
    }
}
