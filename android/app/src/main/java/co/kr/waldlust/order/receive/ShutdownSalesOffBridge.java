package co.kr.waldlust.order.receive;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.Build;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.URI;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicReference;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

/**
 * Closes the shop (sales OFF) when the device is powered off normally.
 *
 * <p>The work itself happens in Dart: the endpoint
 * (PUT /v0/shop/{code}/operating-status) needs the JWT held in secure storage
 * plus the Dio auth/refresh interceptors, so this class only detects the
 * shutdown, hands it to Dart over a dedicated channel, and holds the ordered
 * broadcast open until Dart answers.
 *
 * <p>Measured on 2026-09-04 with the instrumented predecessor of this class,
 * on both target devices, during a real framework shutdown sequence:
 *
 * <pre>
 * T2mini_s sdk=25  net=wifi/internet=true,validated=true dns=14ms tcp=12ms dart=3ms total=39ms
 * D3 MINI  sdk=33  net=wifi/internet=true,validated=true dns=40ms tcp=12ms dart=1ms total=58ms
 * </pre>
 *
 * <p>So the network is alive and validated at ACTION_SHUTDOWN on both, which
 * matches AOSP: ShutdownThread only tears the radios down after the broadcast
 * completes. The older "the network is already gone on Android 13" reading came
 * from the deprecated getActiveNetworkInfo()/isConnectedOrConnecting() pair,
 * which is unreliable on modern releases and is deliberately not used here.
 *
 * <p>onDestroy was NOT observed on either device during shutdown, so this class
 * only logs a marker there; the app-exit case is covered on the Dart side by
 * the lifecycle detached listener.
 *
 * <p>Every API used exists on SDK 24, so both devices run the same path. Do not
 * add Build.MODEL or SDK_INT branches here - a branch would mean the design is
 * wrong.
 */
public final class ShutdownSalesOffBridge implements MethodChannel.MethodCallHandler {

    /**
     * Dedicated channel. It must not be the shared app channel: MembershipScreen
     * installs its own setMethodCallHandler there and a channel keeps only one,
     * so a native -> Dart call on the shared channel would be swallowed once
     * that screen has been opened.
     */
    public static final String CHANNEL =
            "co.kr.waldlust.order.receive.appfit_order_agent/shutdown";

    private static final String TAG = "ShutdownSalesOff";
    private static final String LOG_BCAST = "[SHUTDOWN_BCAST]";
    private static final String LOG_DESTROY = "[ON_DESTROY]";

    private static final String PREFS_NAME = "KOKONUT_AGENT";
    private static final String KEY_PROBE_HOST = "KEY_SHUTDOWN_PROBE_HOST";

    /**
     * ShutdownThread gives the ordered ACTION_SHUTDOWN broadcast 10s
     * (MAX_BROADCAST_TIME) before giving up. Half of that keeps a hung request
     * from ever becoming a visible power-off delay. The measured happy path is
     * under 100ms.
     */
    private static final long TOTAL_BUDGET_MS = 5000L;
    private static final long SALES_OFF_TIMEOUT_MS = 3000L;
    private static final int TCP_CONNECT_TIMEOUT_MS = 1500;

    /**
     * ACTION_SHUTDOWN is an ordered broadcast, so a higher priority receiver runs
     * first and - because goAsync() holds it open - the receivers behind us do
     * not run until we finish. Measurements say the network survives anyway, but
     * running first costs nothing and removes the ordering from the equation.
     * 999 is the maximum an app may claim; 1000 is reserved.
     */
    private static final int RECEIVER_PRIORITY = 999;

    private final MainActivity activity;
    private final MethodChannel channel;
    private final ExecutorService worker =
            Executors.newSingleThreadExecutor(r -> {
                Thread t = new Thread(r, "shutdown-sales-off");
                t.setDaemon(true);
                return t;
            });

    @Nullable
    private BroadcastReceiver receiver;
    private volatile boolean registered;

    public ShutdownSalesOffBridge(@NonNull MainActivity activity, @NonNull BinaryMessenger messenger) {
        this.activity = activity;
        this.channel = new MethodChannel(messenger, CHANNEL);
        this.channel.setMethodCallHandler(this);
    }

    // ---------------------------------------------------------------- lifecycle

    /** Registers the ACTION_SHUTDOWN receiver. Safe to call more than once. */
    public void register() {
        if (registered) {
            return;
        }
        receiver = new BroadcastReceiver() {
            @Override
            public void onReceive(Context context, Intent intent) {
                if (!Intent.ACTION_SHUTDOWN.equals(intent.getAction())) {
                    return;
                }
                PendingResult pending = goAsync();
                runSalesOff(pending);
            }
        };
        IntentFilter filter = new IntentFilter(Intent.ACTION_SHUTDOWN);
        filter.setPriority(RECEIVER_PRIORITY);
        // No RECEIVER_EXPORTED/RECEIVER_NOT_EXPORTED flag on purpose: a filter
        // holding only protected system broadcasts is exempt from the targetSdk
        // 34+ requirement, and NOT_EXPORTED would drag the system's own sender
        // UID into an export check we do not need.
        activity.registerReceiver(receiver, filter);
        registered = true;
        Log.i(TAG, "ACTION_SHUTDOWN receiver registered (priority=" + RECEIVER_PRIORITY + ")");
    }

    /**
     * Called from MainActivity.onDestroy. Marker only - no network, no Dart round
     * trip. This path also runs on an ordinary in-app exit, where blocking for
     * seconds would be a regression, and the shutdown measurements showed
     * onDestroy is not called during a power off anyway. The app-exit case is
     * handled on the Dart side (lifecycle detached).
     */
    public void onActivityDestroy() {
        StringBuilder sb = new StringBuilder(LOG_DESTROY);
        sb.append(" model=").append(Build.MODEL).append(" sdk=").append(Build.VERSION.SDK_INT);
        appendNetworkState(sb);
        writeLog(sb.toString());
        unregister();
    }

    /** Unregisters the receiver and stops the worker. */
    public void unregister() {
        if (registered && receiver != null) {
            try {
                activity.unregisterReceiver(receiver);
            } catch (IllegalArgumentException ignored) {
                // Already unregistered.
            }
        }
        registered = false;
        receiver = null;
        channel.setMethodCallHandler(null);
        worker.shutdownNow();
    }

    // ------------------------------------------------------------- Dart -> native

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        if ("setProbeHost".equals(call.method)) {
            String host = extractHost(call.argument("baseUrl"));
            activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit().putString(KEY_PROBE_HOST, host).apply();
            Log.i(TAG, "diagnostic host set: " + host);
            result.success(host);
            return;
        }
        result.notImplemented();
    }

    // -------------------------------------------------------------------- work

    private void runSalesOff(@Nullable final BroadcastReceiver.PendingResult pending) {
        final long startedAt = System.currentTimeMillis();
        final AtomicBoolean finished = new AtomicBoolean(false);

        // Whatever happens below, the broadcast is released inside the budget.
        Thread watchdog = new Thread(() -> {
            try {
                Thread.sleep(TOTAL_BUDGET_MS);
            } catch (InterruptedException ignored) {
                return;
            }
            if (finished.compareAndSet(false, true)) {
                writeLog(LOG_BCAST + " budgetExceeded ms=" + (System.currentTimeMillis() - startedAt));
                finishQuietly(pending);
            }
        }, "shutdown-sales-off-watchdog");
        watchdog.setDaemon(true);
        watchdog.start();

        try {
            worker.execute(() -> {
                StringBuilder sb = new StringBuilder(LOG_BCAST);
                sb.append(" model=").append(Build.MODEL).append(" sdk=").append(Build.VERSION.SDK_INT);
                boolean ok = false;
                try {
                    appendNetworkState(sb);
                    ok = requestSalesOffFromDart(sb);
                    if (!ok) {
                        // Post mortem only. Runs after the real request, never
                        // before it - the request is what we are racing to send.
                        appendFailureForensics(sb);
                    }
                } catch (Throwable t) {
                    sb.append(" fatal=").append(t.getClass().getSimpleName())
                            .append(':').append(t.getMessage());
                } finally {
                    sb.append(" totalMs=").append(System.currentTimeMillis() - startedAt);
                    writeLog(sb.toString());
                    if (finished.compareAndSet(false, true)) {
                        watchdog.interrupt();
                        finishQuietly(pending);
                    }
                }
            });
        } catch (Throwable t) {
            // Executor already shut down (activity tearing down).
            writeLog(LOG_BCAST + " notRun=" + t.getClass().getSimpleName());
            if (finished.compareAndSet(false, true)) {
                watchdog.interrupt();
                finishQuietly(pending);
            }
        }
    }

    /**
     * Asks Dart to send the sales-OFF request and blocks (on the worker, never on
     * the main thread - the channel result is delivered on the main thread, so
     * blocking it here would deadlock) until it answers or the timeout expires.
     *
     * @return true when Dart reports the shop was closed (or that it correctly
     *         skipped, e.g. a KDS terminal).
     */
    private boolean requestSalesOffFromDart(StringBuilder sb) {
        final CountDownLatch latch = new CountDownLatch(1);
        final AtomicReference<String> outcome = new AtomicReference<>("timeout");
        final AtomicBoolean ok = new AtomicBoolean(false);
        final long t0 = System.currentTimeMillis();

        Map<String, Object> args = new HashMap<>();
        args.put("reason", "shutdown");

        try {
            activity.runOnUiThread(() -> {
                try {
                    channel.invokeMethod("requestSalesOff", args, new MethodChannel.Result() {
                        @Override
                        public void success(@Nullable Object result) {
                            boolean value = Boolean.TRUE.equals(result);
                            ok.set(value);
                            outcome.set(value ? "ok" : "refused");
                            latch.countDown();
                        }

                        @Override
                        public void error(@NonNull String code, @Nullable String message,
                                @Nullable Object details) {
                            outcome.set("error:" + code);
                            latch.countDown();
                        }

                        @Override
                        public void notImplemented() {
                            outcome.set("notImplemented");
                            latch.countDown();
                        }
                    });
                } catch (Throwable t) {
                    outcome.set("throw:" + t.getClass().getSimpleName());
                    latch.countDown();
                }
            });
            latch.await(SALES_OFF_TIMEOUT_MS, TimeUnit.MILLISECONDS);
        } catch (Throwable t) {
            outcome.set("throw:" + t.getClass().getSimpleName());
        }
        sb.append(" salesOff=").append(outcome.get())
                .append('(').append(System.currentTimeMillis() - t0).append("ms)");
        return ok.get();
    }

    /**
     * Runs only when the request failed, to say whether the link itself was gone
     * or the failure was higher up. Without this a failed shutdown close leaves
     * nothing to diagnose after the device is off.
     */
    private void appendFailureForensics(StringBuilder sb) {
        String host = resolveDiagnosticHost();
        if (host == null) {
            sb.append(" forensics=noHost");
            return;
        }
        long t0 = System.currentTimeMillis();
        String literal = null;
        try {
            literal = InetAddress.getByName(host).getHostAddress();
            sb.append(" dns=ok:").append(literal)
                    .append('(').append(System.currentTimeMillis() - t0).append("ms)");
        } catch (Throwable t) {
            sb.append(" dns=").append(t.getClass().getSimpleName())
                    .append('(').append(System.currentTimeMillis() - t0).append("ms)");
        }
        long t1 = System.currentTimeMillis();
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(literal != null ? literal : host, 443),
                    TCP_CONNECT_TIMEOUT_MS);
            sb.append(" tcp=ok(").append(System.currentTimeMillis() - t1).append("ms)");
        } catch (Throwable t) {
            sb.append(" tcp=").append(t.getClass().getSimpleName())
                    .append('(').append(System.currentTimeMillis() - t1).append("ms)");
        }
    }

    private void appendNetworkState(StringBuilder sb) {
        sb.append(" net=");
        try {
            ConnectivityManager cm = (ConnectivityManager) activity.getApplicationContext()
                    .getSystemService(Context.CONNECTIVITY_SERVICE);
            if (cm == null) {
                sb.append("noService");
                return;
            }
            Network network = cm.getActiveNetwork();
            if (network == null) {
                sb.append("none");
                return;
            }
            NetworkCapabilities caps = cm.getNetworkCapabilities(network);
            if (caps == null) {
                sb.append("noCaps");
                return;
            }
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                sb.append("wifi/");
            }
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) {
                sb.append("eth/");
            }
            if (caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) {
                sb.append("cell/");
            }
            sb.append("internet=")
                    .append(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET))
                    .append(",validated=")
                    .append(caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
        } catch (Throwable t) {
            sb.append("err:").append(t.getClass().getSimpleName());
        }
    }

    // ------------------------------------------------------------------ helpers

    @Nullable
    private String resolveDiagnosticHost() {
        try {
            String host = activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .getString(KEY_PROBE_HOST, null);
            return (host == null || host.isEmpty()) ? null : host;
        } catch (Throwable t) {
            return null;
        }
    }

    @Nullable
    private static String extractHost(@Nullable String baseUrl) {
        if (baseUrl == null || baseUrl.isEmpty()) {
            return null;
        }
        try {
            String host = URI.create(baseUrl.trim()).getHost();
            if (host != null && !host.isEmpty()) {
                return host;
            }
        } catch (Throwable ignored) {
            // Fall through to the manual parse below.
        }
        String stripped = baseUrl.trim();
        int scheme = stripped.indexOf("://");
        if (scheme >= 0) {
            stripped = stripped.substring(scheme + 3);
        }
        int slash = stripped.indexOf('/');
        if (slash >= 0) {
            stripped = stripped.substring(0, slash);
        }
        int colon = stripped.indexOf(':');
        if (colon >= 0) {
            stripped = stripped.substring(0, colon);
        }
        return stripped.isEmpty() ? null : stripped;
    }

    private void writeLog(String text) {
        Log.i(TAG, text);
        try {
            // fsync'd write: the whole point of this line is to survive the power
            // off that produced it.
            activity.appendLogToFileSynced(text);
        } catch (Throwable t) {
            Log.w(TAG, "log write failed: " + t.getMessage());
        }
    }

    private static void finishQuietly(@Nullable BroadcastReceiver.PendingResult pending) {
        if (pending == null) {
            return;
        }
        try {
            pending.finish();
        } catch (Throwable ignored) {
            // Already finished, or the broadcast was reclaimed.
        }
    }
}
