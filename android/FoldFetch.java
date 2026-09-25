package org.love2d.android;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.util.Log;

import androidx.annotation.Keep;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import org.libsdl.app.SDLActivity;

/**
 * Downloads and the shared-storage switch for the HOME menu's own
 * emulators (fold3ds/emu.lua), through FoldBridge:
 *
 *   fetch       "<url>|<file>"   download in the background into the file
 *                                (whole, via <file>.part); a failure leaves
 *                                <file>.fail so it is not asked again.
 *                                "started" / "busy" (already on its way)
 *   files.ok                     "1" when the app may use shared storage
 *                                (the emulators' user folder)
 *   files.ask                    Android's all-files switch for this app
 *   external                     the shared storage's root path
 *
 * Only http(s) URLs, only files under the app's own folders or its user
 * folder on shared storage.
 */
@Keep
public final class FoldFetch {
    private static final String TAG = "FoldFetch";
    private static final ExecutorService pool = Executors.newFixedThreadPool(3);
    private static final Set<String> busy = new HashSet<>();

    private FoldFetch() {}

    public static String call(String cmd, String arg) {
        switch (cmd) {
            case "fetch": return fetch(arg);
            case "files.ok": return filesOk() ? "1" : "0";
            case "files.ask": return filesAsk();
            case "external": return Environment.getExternalStorageDirectory().getAbsolutePath();
            default: return "error:unknown " + cmd;
        }
    }

    static boolean filesOk() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) return Environment.isExternalStorageManager();
        return true;
    }

    private static String filesAsk() {
        if (filesOk()) return "ok";
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return "ok";
        Context context = SDLActivity.getContext();
        if (context == null) return "error:no activity";
        Intent i = new Intent(android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:" + context.getPackageName()));
        i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        context.startActivity(i);
        return "asked";
    }

    private static boolean allowedTarget(File f) {
        try {
            String path = f.getCanonicalPath();
            Context context = SDLActivity.getContext();
            if (context != null) {
                if (path.startsWith(context.getFilesDir().getCanonicalPath() + "/")) return true;
                File ext = context.getExternalFilesDir(null);
                if (ext != null && path.startsWith(ext.getCanonicalPath() + "/")) return true;
            }
            String shared = Environment.getExternalStorageDirectory().getCanonicalPath();
            return path.startsWith(shared + "/");
        } catch (Exception e) {
            return false;
        }
    }

    private static String fetch(String arg) {
        int bar = arg.indexOf('|');
        if (bar <= 0) return "error:arg";
        final String url = arg.substring(0, bar);
        final File dest = new File(arg.substring(bar + 1));
        if (!(url.startsWith("https://") || url.startsWith("http://"))) return "error:url";
        if (!allowedTarget(dest)) return "error:target";
        synchronized (busy) {
            if (busy.contains(dest.getPath())) return "busy";
            busy.add(dest.getPath());
        }
        pool.execute(() -> {
            try {
                download(url, dest);
            } finally {
                synchronized (busy) { busy.remove(dest.getPath()); }
            }
        });
        return "started";
    }

    private static void download(String url, File dest) {
        File dir = dest.getParentFile();
        if (dir != null) dir.mkdirs();
        File part = new File(dest.getPath() + ".part");
        File fail = new File(dest.getPath() + ".fail");
        HttpURLConnection conn = null;
        try {
            for (int hop = 0; hop < 5; hop++) {
                conn = (HttpURLConnection) new URL(url).openConnection();
                conn.setConnectTimeout(10000);
                conn.setReadTimeout(30000);
                conn.setInstanceFollowRedirects(true);
                conn.setRequestProperty("User-Agent", "gen1recomp-Fold (3DS HOME menu)");
                int code = conn.getResponseCode();
                if (code >= 300 && code < 400 && conn.getHeaderField("Location") != null) {
                    url = new URL(new URL(url), conn.getHeaderField("Location")).toString();
                    conn.disconnect();
                    continue;
                }
                if (code != 200) throw new Exception("HTTP " + code);
                try (InputStream in = conn.getInputStream(); FileOutputStream out = new FileOutputStream(part)) {
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                }
                if (!part.renameTo(dest)) throw new Exception("rename");
                fail.delete();
                return;
            }
            throw new Exception("too many redirects");
        } catch (Exception e) {
            Log.i(TAG, "no " + url + ": " + e.getMessage());
            part.delete();
            try { new FileOutputStream(fail).close(); } catch (Exception ignored) {}
        } finally {
            if (conn != null) conn.disconnect();
        }
    }
}
