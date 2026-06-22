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
import java.io.RandomAccessFile;
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

    // ── ELF header constants for architecture validation ──────────
    // EI_CLASS offset = 4 in the ELF identification array
    private static final int EI_CLASS_OFFSET = 4;
    private static final byte ELFCLASS32 = 1; // 32-bit
    private static final byte ELFCLASS64 = 2; // 64-bit

    private TspNativeLoader() {}

    public static String getTspagentDiskPath() {
        return tspagentPathForIntegrity;
    }

    /**
     * Checks whether the ELF at the given path has the correct bitness (32/64)
     * for the current process ABI.
     *
     * @param elfPath absolute path to the .so file
     * @return true if the ELF class matches the process ABI, false if mismatch or unreadable
     */
    private static boolean checkElfArchitecture(File elfPath) {
        if (!elfPath.isFile() || !elfPath.canRead()) {
            Log.w(TAG, "ELF check: file not readable: " + elfPath);
            return false;
        }
        // Determine expected ELF class from the primary supported ABI
        String primaryAbi = (Build.SUPPORTED_ABIS != null && Build.SUPPORTED_ABIS.length > 0)
                ? Build.SUPPORTED_ABIS[0]
                : "";
        boolean is32BitProcess;
        if (primaryAbi.contains("armeabi") || primaryAbi.contains("x86")) {
            is32BitProcess = true;
        } else if (primaryAbi.contains("arm64") || primaryAbi.contains("x86_64")) {
            is32BitProcess = false;
        } else {
            // Unknown ABI — skip check
            return true;
        }
        byte expectedClass = is32BitProcess ? ELFCLASS32 : ELFCLASS64;

        // Read just the first 5 bytes of the ELF header
        byte[] header = new byte[5];
        try (RandomAccessFile raf = new RandomAccessFile(elfPath, "r")) {
            if (raf.length() < 5) {
                Log.w(TAG, "ELF check: file too small: " + elfPath);
                return false;
            }
            raf.readFully(header);
        } catch (IOException e) {
            Log.w(TAG, "ELF check: read error: " + elfPath, e);
            return false;
        }

        // Verify ELF magic: 0x7f 'E' 'L' 'F'
        if (header[0] != 0x7f || header[1] != 'E' || header[2] != 'L' || header[3] != 'F') {
            Log.w(TAG, "ELF check: bad magic in " + elfPath);
            return false;
        }

        byte actualClass = header[EI_CLASS_OFFSET];
        if (actualClass == expectedClass) {
            return true;
        }

        String expectedStr = is32BitProcess ? "32-bit" : "64-bit";
        String actualStr = (actualClass == ELFCLASS32) ? "32-bit" : (actualClass == ELFCLASS64) ? "64-bit" : "unknown";
        Log.e(TAG, "ELF ARCHITECTURE MISMATCH! " + elfPath
                + ": expected " + expectedStr + " for ABI " + primaryAbi
                + ", actual is " + actualStr
                + ". Loading a " + actualStr + " library on a " + expectedStr + " process"
                + " will cause SIGABRT in the dynamic linker.");
        return false;
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

        // ── ELF architecture guard ─────────────────────────────────
        // Before calling System.loadLibrary (which can SIGABRT on 32-bit
        // devices if the .so is actually a 64-bit ELF), read the ELF
        // header and verify the bitness matches the current process ABI.
        String nativeLibDir = context.getApplicationInfo().nativeLibraryDir;
        File tspagentFile = new File(nativeLibDir, "libtspagent.so");
        if (!tspagentFile.exists()) {
            Log.w(TAG, "libtspagent.so not found in " + nativeLibDir + " — skipping");
            return;
        }
        if (!checkElfArchitecture(tspagentFile)) {
            Log.w(TAG, "libtspagent.so architecture mismatch detected — "
                    + "skipping load to prevent SIGABRT. "
                    + "The TSP agent will be unavailable on this device.");
            return;
        }

        System.loadLibrary("tspagent");
        tspagentPathForIntegrity = tspagentFile.getAbsolutePath();
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

        // ── ELF architecture check on the decrypted .so as well ──
        if (!checkElfArchitecture(out)) {
            Log.w(TAG, "Decrypted libtspagent.so from assets has wrong architecture —"
                    + " skipping load to prevent SIGABRT");
            //noinspection ResultOfMethodCallIgnored
            out.delete();
            return false;
        }

        String abs = out.getAbsolutePath();
        System.load(abs);
        tspagentPathForIntegrity = abs;
        return true;
    }
}
