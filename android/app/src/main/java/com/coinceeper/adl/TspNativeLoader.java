package com.coinceeper.adl;

import android.content.Context;
import android.os.Build;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.Arrays;

/**
 * لود <code>libtspagent.so</code> از فایل رمزشده در assets (TSPF1 + XOR) یا از
 * <code>jniLibs</code> (حالت توسعه). باید قبل از <code>System.loadLibrary("tspagent_jni")</code> اجرا شود.
 * <p>
 * بستهٔ assets: <code>tspn/&lt;abi&gt;/libtspagent.dat</code> (همان خروجی
 * <code>scripts/encrypt_jni_tspagent.sh</code>).
 */
public final class TspNativeLoader {
    private static final String TAG = "TspNativeLoader";
    private static final int MIN_XOR_KEY_HEX = 32; /* min chars — bash script uses 32+ */

    private static boolean tspagentBaseLoaded;
    private static String tspagentPathForIntegrity;

    private TspNativeLoader() {}

    public static String getTspagentDiskPath() {
        return tspagentPathForIntegrity;
    }

    /**
     * لود DSO اصلی Go. اگر {@link BuildConfig#TSP_LIB_XOR_KEY} مقدار داشته و asset موجود باشد،
     * decrypt به فایل داخلی و {@link System#load}؛ وگرا {@link System#loadLibrary}("tspagent").
     */
    public static synchronized void loadTspagentBase(Context context) {
        if (tspagentBaseLoaded) {
            return;
        }
        if (context == null) {
            System.loadLibrary("tspagent");
            tspagentBaseLoaded = true;
            return;
        }
        String keyHex = BuildConfig.TSP_LIB_XOR_KEY;
        if (keyHex != null && !keyHex.isEmpty() && keyHex.length() >= MIN_XOR_KEY_HEX) {
            try {
                if (loadFromAssetXor(context, keyHex.trim())) {
                    tspagentBaseLoaded = true;
                    return;
                }
            } catch (IOException e) {
                throw new UnsatisfiedLinkError("TspNativeLoader asset decrypt: " + e.getMessage());
            }
        }
        System.loadLibrary("tspagent");
        File f = new File(context.getApplicationInfo().nativeLibraryDir, "libtspagent.so");
        tspagentPathForIntegrity = f.getAbsolutePath();
        tspagentBaseLoaded = true;
    }

    private static boolean loadFromAssetXor(Context context, String keyHex) throws IOException {
        if ((keyHex.length() & 1) != 0) {
            Log.w(TAG, "TSP_LIB_XOR_KEY: odd hex length");
            return false;
        }
        byte[] key;
        try {
            int n = keyHex.length() / 2;
            key = new byte[n];
            for (int i = 0; i < n; i++) {
                key[i] = (byte) Integer.parseInt(keyHex.substring(i * 2, i * 2 + 2), 16);
            }
        } catch (NumberFormatException e) {
            Log.w(TAG, "TSP_LIB_XOR_KEY: not hex", e);
            return false;
        }
        if (key.length < 16) {
            return false;
        }

        String[] abis = Build.SUPPORTED_ABIS;
        if (abis == null || abis.length == 0) {
            return false;
        }
        String abi0 = abis[0];
        String assetName = "tspn/" + abi0 + "/libtspagent.dat";
        byte[] raw;
        try (InputStream in = context.getAssets().open(assetName);
                ByteArrayOutputStream bos = new ByteArrayOutputStream()) {
            byte[] buf = new byte[1 << 16];
            int r;
            while ((r = in.read(buf)) > 0) {
                bos.write(buf, 0, r);
            }
            raw = bos.toByteArray();
        } catch (IOException e) {
            if (keyHex.length() > 0) {
                Log.d(TAG, "no asset " + assetName + " — fallback to jniLib");
            }
            return false;
        }

        if (raw.length < 6) {
            return false;
        }
        if (raw[0] != (byte) 'T'
                || raw[1] != (byte) 'S'
                || raw[2] != (byte) 'P'
                || raw[3] != (byte) 'F'
                || raw[4] != (byte) '1') {
            Log.e(TAG, "asset missing TSPF1 magic");
            return false;
        }
        int payloadLen = raw.length - 5;
        byte[] payload = Arrays.copyOfRange(raw, 5, raw.length);
        byte[] kb = new byte[payloadLen];
        for (int i = 0; i < payloadLen; i++) {
            kb[i] = key[i % key.length];
        }
        for (int i = 0; i < payloadLen; i++) {
            payload[i] ^= kb[i];
        }

        File dir = new File(context.getFilesDir(), "tspn_load");
        if (!dir.isDirectory() && !dir.mkdirs()) {
            throw new IOException("mkdir tspn_load");
        }
        File out = new File(dir, "libtspagent.so");
        File tmp = new File(dir, "libtspagent.so.tmp");
        try (FileOutputStream fo = new FileOutputStream(tmp)) {
            fo.write(payload);
        }
        if (out.exists() && !out.delete()) {
            throw new IOException("remove old libtspagent");
        }
        if (!tmp.renameTo(out)) {
            try (FileInputStream in = new FileInputStream(tmp);
                    FileOutputStream o = new FileOutputStream(out)) {
                byte[] buf = new byte[1 << 15];
                int n;
                while ((n = in.read(buf)) > 0) {
                    o.write(buf, 0, n);
                }
            }
            //noinspection ResultOfMethodCallIgnored
            tmp.delete();
        }
        String abs = out.getAbsolutePath();
        System.load(abs);
        tspagentPathForIntegrity = abs;
        return true;
    }
}
