package org.love2d.android;

import android.util.Log;
import android.view.KeyEvent;

import androidx.annotation.Keep;

import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

/**
 * The foldable layer's odds and ends, reached from Lua as
 * love.system.foldCamera("call", command, argument) -> string:
 *
 *   vol.capture  "1" / "0"   the volume keys move the drawn 3DS volume
 *                            slider instead of Android's volume (no popup)
 *   vol.take                 the volume key presses since last asked ("+2")
 *   zip          "<root>|<out.zip>|<rel>;<rel>..."   zip files / folders
 *   unzip        "<zip>|<root>|<backup dir>"  unpack (saves and mods only),
 *                            moving any file it replaces into the backup
 *   dp.*                     Download Play (FoldPlay)
 */
@Keep
public final class FoldBridge {
    private static final String TAG = "FoldBridge";
    private static volatile boolean captureVolume = false;
    private static int volumeSteps = 0;

    private FoldBridge() {}

    /** From GameActivity.dispatchKeyEvent: true when the key was taken. */
    public static boolean volumeKey(KeyEvent event) {
        int code = event.getKeyCode();
        if (!captureVolume || (code != KeyEvent.KEYCODE_VOLUME_UP && code != KeyEvent.KEYCODE_VOLUME_DOWN)) {
            return false;
        }
        if (event.getAction() == KeyEvent.ACTION_DOWN) {
            synchronized (FoldBridge.class) {
                volumeSteps += code == KeyEvent.KEYCODE_VOLUME_UP ? 1 : -1;
            }
        }
        return true;
    }

    @Keep
    public static String call(String cmd, String arg) {
        try {
            if (cmd == null) return "";
            if (arg == null) arg = "";
            if (cmd.equals("ping")) return "ok";
            if (cmd.equals("vol.capture")) {
                captureVolume = arg.equals("1");
                return "ok";
            }
            if (cmd.equals("vol.take")) {
                synchronized (FoldBridge.class) {
                    int n = volumeSteps;
                    volumeSteps = 0;
                    return Integer.toString(n);
                }
            }
            if (cmd.equals("zip")) return zip(arg);
            if (cmd.equals("unzip")) return unzip(arg);
            if (cmd.startsWith("dp.")) return FoldPlay.call(cmd.substring(3), arg);
        } catch (Throwable e) {
            Log.d(TAG, cmd + ": " + e);
            return "error:" + e.getMessage();
        }
        return "error:unknown " + cmd;
    }

    // ------------------------------------------------------------ zip

    private static String zip(String arg) throws IOException {
        String[] p = arg.split("\\|", 3);
        if (p.length < 3) return "error:bad arguments";
        File root = new File(p[0]);
        File out = new File(p[1]);
        out.getParentFile().mkdirs();
        int count = 0;
        ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(out));
        try {
            for (String rel : p[2].split(";")) {
                if (rel.length() == 0 || rel.contains("..")) continue;
                count += add(zos, root, new File(root, rel), rel);
            }
        } finally {
            zos.close();
        }
        return "ok:" + count + ":" + out.length();
    }

    private static int add(ZipOutputStream zos, File root, File f, String rel) throws IOException {
        if (f.isDirectory()) {
            int n = 0;
            File[] kids = f.listFiles();
            if (kids == null) return 0;
            for (File k : kids) n += add(zos, root, k, rel + "/" + k.getName());
            return n;
        }
        if (!f.isFile()) return 0;
        zos.putNextEntry(new ZipEntry(rel));
        InputStream in = new FileInputStream(f);
        try {
            copy(in, zos);
        } finally {
            in.close();
        }
        zos.closeEntry();
        return 1;
    }

    // only what Download Play carries: saves and mods, nothing else
    private static boolean allowed(String name) {
        if (name.contains("..") || name.startsWith("/") || name.contains("\\")) return false;
        if (name.startsWith("saves/") || name.startsWith("mods/")) return true;
        return name.matches("save(_[a-z0-9_]+)?\\.lua(\\.bak)?");
    }

    private static String unzip(String arg) throws IOException {
        String[] p = arg.split("\\|", 3);
        if (p.length < 3) return "error:bad arguments";
        File root = new File(p[1]);
        File backup = new File(p[2]);
        int count = 0, skipped = 0;
        ZipInputStream zis = new ZipInputStream(new FileInputStream(p[0]));
        try {
            ZipEntry e;
            while ((e = zis.getNextEntry()) != null) {
                String name = e.getName();
                if (e.isDirectory()) continue;
                if (!allowed(name)) { skipped++; continue; }
                File dest = new File(root, name);
                if (!dest.getCanonicalPath().startsWith(root.getCanonicalPath() + File.separator)) {
                    skipped++;
                    continue;
                }
                if (dest.isFile()) {
                    File keep = new File(backup, name);
                    keep.getParentFile().mkdirs();
                    if (!dest.renameTo(keep)) dest.delete();
                }
                dest.getParentFile().mkdirs();
                OutputStream out = new FileOutputStream(dest);
                try {
                    copy(zis, out);
                } finally {
                    out.close();
                }
                count++;
            }
        } finally {
            zis.close();
        }
        return "ok:" + count + ":" + skipped;
    }

    static void copy(InputStream in, OutputStream out) throws IOException {
        byte[] buf = new byte[65536];
        int n;
        while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
    }
}
