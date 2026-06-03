package com.coinceeper.adl;

/**
 * JNI: ترتیب لود: {@code System.loadLibrary("tspagent")} سپس {@code System.loadLibrary("tspagent_jni")} —
 * <code>libtspagent_jni.so</code> فقط {@code JNI_OnLoad} export می‌شود (version script + strip).
 * برای lib رمزشده در assets: ابتدا decrypt و {@link System#load} با مسیر مطلق، سپس همان‌طور.
 * <p>
 * سورس Go: <strong>github.com/tsp-platform/agent/cmd/mobilehost</strong>
 */
public final class TspAgentBridge {
    private static boolean librariesLoaded;
    private static UnsatisfiedLinkError loadError;

    private TspAgentBridge() {}

    /** @deprecated ترجیحاً از {@link #ensureLoaded(android.content.Context)} استفاده کنید تا لود از assets ممکن شود. */
    @Deprecated
    public static synchronized void ensureLoaded() {
        ensureLoaded(null);
    }

    /**
     * <code>context</code> برای لود DSO رمزشده از assets (در صورت تنظیم {@code TSP_LIB_XOR_KEY} در Gradle).
     */
    public static synchronized void ensureLoaded(android.content.Context context) {
        if (librariesLoaded) {
            return;
        }
        if (loadError != null) {
            throw loadError;
        }
        try {
            TspNativeLoader.loadTspagentBase(context);
            System.loadLibrary("tspagent_jni");
            librariesLoaded = true;
        } catch (UnsatisfiedLinkError e) {
            loadError = e;
            throw e;
        }
    }

    public static native String versionString();

    public static native String healthJson();

    public static native String fingerprint();

    /** مسیر مطلق libtspagent.so روی دیسک (پادمان opsec.lib_integrity_sha256) */
    public static native void setNativeLibPath(String absolutePath);

    /** 0=ok, -1=path, -2=running, -3=config, -4=RASP, -5=TEE, -6=attestation, -7=tamper. state null → default. */
    public static native int startWithPaths(String configPath, String statePath);
    /** 0=ok — same as AGENT_STRICT_MODE; call before version/start in hardened. */
    public static native int setStrictMode(int enabled);
    /** 0=ok, -1=parse; JSON: {"p":"play_integrity","t":"..."} */
    public static native int setAttestationJSON(String json);
    /** 0=ok, -1=invalid hex(64) */
    public static native int setPayloadKeyHex(String hexKey);

    public static native void stopRuntime();

    public static native boolean isRuntimeRunning();
}
