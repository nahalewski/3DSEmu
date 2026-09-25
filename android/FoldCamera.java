package org.love2d.android;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.ImageFormat;
import android.hardware.camera2.CameraAccessException;
import android.hardware.camera2.CameraCaptureSession;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraDevice;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.hardware.camera2.params.StreamConfigurationMap;
import android.media.Image;
import android.media.ImageReader;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.util.Log;
import android.util.Size;
import android.view.Surface;

import androidx.annotation.Keep;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import java.nio.ByteBuffer;
import java.util.Arrays;

import org.libsdl.app.SDLActivity;

/**
 * The foldable layer's camera (fold3ds/camera.lua, the 3DS Camera applet):
 * a Camera2 preview stream from the rear or the front camera, handed to Lua
 * one frame at a time as planar YUV 4:2:0 (liblove converts it to RGBA
 * straight into an ImageData; see love.system.foldCamera).
 *
 * States: 0 off, 1 waiting for the CAMERA permission, 2 opening, 3 running,
 * -1 failed, -2 no camera facing that way, -3 permission refused.
 */
@Keep
@TargetApi(21)
public final class FoldCamera {
    private static final String TAG = "FoldCamera";
    private static final int PERMISSION_REQUEST = 7301;

    private static final Object lock = new Object();
    private static volatile int state = 0;
    private static int generation = 0;          // drops callbacks of a closed camera
    private static int wantFacing = 0, wantWidth = 960;
    private static long askedAt = 0;

    private static HandlerThread thread;
    private static Handler handler;
    private static CameraDevice device;
    private static CameraCaptureSession session;
    private static ImageReader reader;

    // the newest frame (written on the camera thread), and the copy handed out
    private static byte[] latest, out;
    private static int frameW, frameH, serial, handed;
    private static int sensorOrientation;
    private static boolean frontFacing;

    private FoldCamera() {}

    private static Activity activity() {
        Context c = SDLActivity.getContext();
        return (c instanceof Activity) ? (Activity) c : null;
    }

    private static boolean permitted(Activity a) {
        return ContextCompat.checkSelfPermission(a, Manifest.permission.CAMERA)
            == PackageManager.PERMISSION_GRANTED;
    }

    /** Which cameras there are: bit 0 rear, bit 1 front. */
    @Keep
    public static int available() {
        if (Build.VERSION.SDK_INT < 21) return 0;
        Activity a = activity();
        if (a == null) return 0;
        int mask = 0;
        try {
            CameraManager m = (CameraManager) a.getSystemService(Context.CAMERA_SERVICE);
            for (String id : m.getCameraIdList()) {
                Integer f = m.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING);
                if (f == null) continue;
                if (f == CameraCharacteristics.LENS_FACING_BACK) mask |= 1;
                if (f == CameraCharacteristics.LENS_FACING_FRONT) mask |= 2;
            }
        } catch (Exception e) {
            Log.d(TAG, "available: " + e);
        }
        return mask;
    }

    /** Start (or switch to) the camera facing `facing` (0 rear, 1 front). */
    @Keep
    public static int start(int facing, int width) {
        if (Build.VERSION.SDK_INT < 21) return state = -1;
        final Activity a = activity();
        if (a == null) return state = -1;
        wantFacing = facing;
        wantWidth = Math.max(320, Math.min(1920, width));
        closeCamera();
        if (!permitted(a)) {
            state = 1;
            askedAt = System.currentTimeMillis();
            a.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    // the microphone too, for the sound of videos (FoldRecorder)
                    ActivityCompat.requestPermissions(a,
                        new String[]{ Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO },
                        PERMISSION_REQUEST);
                }
            });
            return state;
        }
        openCamera(a);
        return state;
    }

    /** The state; once the permission prompt is answered, opens the camera. */
    @Keep
    public static int state() {
        if (state == 1) {
            Activity a = activity();
            if (a != null && permitted(a)) {
                openCamera(a);
            } else if (a != null && System.currentTimeMillis() - askedAt > 1500
                    && a.hasWindowFocus()) {
                // the prompt has gone and the answer was no
                state = -3;
            }
        }
        return state;
    }

    @Keep
    public static void stop() {
        closeCamera();
        state = 0;
    }

    /**
     * The newest frame's facts, {width, height, rotation, mirror, serial}:
     * rotate the picture clockwise by `rotation` degrees (then mirror it
     * sideways when `mirror` is 1, the front camera) to see it upright.
     */
    @Keep
    public static int[] info() {
        synchronized (lock) {
            int rotation = 0;
            Activity a = activity();
            if (a != null) {
                int r = a.getWindowManager().getDefaultDisplay().getRotation();
                int degrees = r == Surface.ROTATION_90 ? 90 : r == Surface.ROTATION_180 ? 180
                    : r == Surface.ROTATION_270 ? 270 : 0;
                rotation = frontFacing ? (sensorOrientation + degrees) % 360
                    : (sensorOrientation - degrees + 360) % 360;
            }
            return new int[]{ frameW, frameH, rotation, frontFacing ? 1 : 0, serial };
        }
    }

    /** The newest frame as planar Y, U, V (4:2:0), or null if none is new. */
    @Keep
    public static byte[] frame() {
        synchronized (lock) {
            if (latest == null || handed == serial) return null;
            if (out == null || out.length != latest.length) out = new byte[latest.length];
            System.arraycopy(latest, 0, out, 0, latest.length);
            handed = serial;
            return out;
        }
    }

    // ------------------------------------------------------------ Camera2

    private static void openCamera(Activity a) {
        final CameraManager m = (CameraManager) a.getSystemService(Context.CAMERA_SERVICE);
        final int gen;
        synchronized (lock) { gen = ++generation; }
        try {
            String chosen = null;
            CameraCharacteristics chars = null;
            int facing = wantFacing == 1 ? CameraCharacteristics.LENS_FACING_FRONT
                : CameraCharacteristics.LENS_FACING_BACK;
            for (String id : m.getCameraIdList()) {
                CameraCharacteristics c = m.getCameraCharacteristics(id);
                Integer f = c.get(CameraCharacteristics.LENS_FACING);
                if (f != null && f == facing) { chosen = id; chars = c; break; }
            }
            if (chosen == null) { state = -2; return; }
            StreamConfigurationMap map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP);
            Size size = pickSize(map == null ? null : map.getOutputSizes(ImageFormat.YUV_420_888));
            Integer so = chars.get(CameraCharacteristics.SENSOR_ORIENTATION);
            synchronized (lock) {
                sensorOrientation = so == null ? 0 : so;
                frontFacing = wantFacing == 1;
                latest = null;
            }
            if (thread == null) {
                thread = new HandlerThread("FoldCamera");
                thread.start();
                handler = new Handler(thread.getLooper());
            }
            state = 2;
            final ImageReader r = ImageReader.newInstance(size.getWidth(), size.getHeight(),
                ImageFormat.YUV_420_888, 3);
            r.setOnImageAvailableListener(new ImageReader.OnImageAvailableListener() {
                @Override
                public void onImageAvailable(ImageReader ir) {
                    Image img = null;
                    try {
                        img = ir.acquireLatestImage();
                        if (img != null) store(img, gen);
                    } catch (Exception e) {
                        Log.d(TAG, "frame: " + e);
                    } finally {
                        if (img != null) img.close();
                    }
                }
            }, handler);
            reader = r;
            m.openCamera(chosen, new CameraDevice.StateCallback() {
                @Override
                public void onOpened(CameraDevice cam) {
                    if (gen != generation) { cam.close(); return; }
                    device = cam;
                    try {
                        final CaptureRequest.Builder b = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW);
                        b.addTarget(r.getSurface());
                        b.set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO);
                        b.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE);
                        cam.createCaptureSession(Arrays.asList(r.getSurface()),
                            new CameraCaptureSession.StateCallback() {
                                @Override
                                public void onConfigured(CameraCaptureSession s) {
                                    if (gen != generation) { s.close(); return; }
                                    session = s;
                                    try {
                                        s.setRepeatingRequest(b.build(), null, handler);
                                        state = 3;
                                    } catch (Exception e) {
                                        Log.d(TAG, "repeat: " + e);
                                        state = -1;
                                    }
                                }

                                @Override
                                public void onConfigureFailed(CameraCaptureSession s) {
                                    Log.d(TAG, "session configure failed");
                                    if (gen == generation) state = -1;
                                }
                            }, handler);
                    } catch (Exception e) {
                        Log.d(TAG, "session: " + e);
                        state = -1;
                    }
                }

                @Override
                public void onDisconnected(CameraDevice cam) {
                    cam.close();
                    if (gen == generation) { device = null; state = 0; }
                }

                @Override
                public void onError(CameraDevice cam, int error) {
                    Log.d(TAG, "camera error " + error);
                    cam.close();
                    if (gen == generation) { device = null; state = -1; }
                }
            }, handler);
        } catch (SecurityException e) {
            state = 1;
        } catch (Exception e) {
            Log.d(TAG, "open: " + e);
            state = -1;
        }
    }

    // the biggest preview size no wider than asked (4:3 preferred)
    private static Size pickSize(Size[] sizes) {
        Size best = null;
        if (sizes != null) {
            for (int pass = 0; pass < 2 && best == null; pass++) {
                for (Size s : sizes) {
                    if (s.getWidth() > wantWidth) continue;
                    if (pass == 0 && s.getWidth() * 3 != s.getHeight() * 4) continue;
                    if (best == null || s.getWidth() * s.getHeight() > best.getWidth() * best.getHeight()) best = s;
                }
            }
        }
        return best != null ? best : new Size(640, 480);
    }

    private static void store(Image img, int gen) {
        int w = img.getWidth() & ~1, h = img.getHeight() & ~1;
        int cw = w / 2, ch = h / 2;
        int need = w * h + 2 * cw * ch;
        synchronized (lock) {
            if (gen != generation) return;
        }
        // the writer fills a buffer of its own, swapped in under the lock
        byte[] mine = new byte[need];
        Image.Plane[] p = img.getPlanes();
        copyPlane(p[0], w, h, mine, 0);
        copyPlane(p[1], cw, ch, mine, w * h);
        copyPlane(p[2], cw, ch, mine, w * h + cw * ch);
        synchronized (lock) {
            if (gen != generation) return;
            latest = mine;
            frameW = w;
            frameH = h;
            serial++;
        }
    }

    private static byte[] row;

    private static void copyPlane(Image.Plane plane, int w, int h, byte[] dst, int off) {
        ByteBuffer src = plane.getBuffer();
        int rs = plane.getRowStride(), ps = plane.getPixelStride();
        if (ps == 1 && rs == w) {
            src.position(0);
            src.get(dst, off, Math.min(w * h, src.remaining()));
            return;
        }
        if (row == null || row.length < rs) row = new byte[rs];
        for (int y = 0; y < h; y++) {
            int start = y * rs;
            int len = Math.min(rs, src.capacity() - start);
            if (len <= 0) break;
            src.position(start);
            src.get(row, 0, len);
            int o = off + y * w;
            if (ps == 1) {
                System.arraycopy(row, 0, dst, o, Math.min(w, len));
            } else {
                for (int x = 0, i = 0; x < w && i < len; x++, i += ps) dst[o + x] = row[i];
            }
        }
    }

    private static void closeCamera() {
        synchronized (lock) {
            generation++;
            latest = null;
        }
        try { if (session != null) session.close(); } catch (Exception e) { /* closing anyway */ }
        try { if (device != null) device.close(); } catch (Exception e) { /* closing anyway */ }
        try { if (reader != null) reader.close(); } catch (Exception e) { /* closing anyway */ }
        session = null;
        device = null;
        reader = null;
    }
}
