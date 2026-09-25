package org.love2d.android;

import android.Manifest;
import android.annotation.TargetApi;
import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Context;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.Image;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.media.MediaRecorder;
import android.media.MediaScannerConnection;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;
import android.util.Log;

import androidx.annotation.Keep;
import androidx.core.content.ContextCompat;

import java.io.File;
import java.io.FileInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;

import org.libsdl.app.SDLActivity;

/**
 * The Camera applet's video recorder (fold3ds/camera.lua): the frames the
 * app draws (the viewfinder, filters and all) arrive as planar YUV 4:2:0
 * through love.system.foldCamera("recFrame", imageData) and are encoded
 * to H.264; the microphone, when Android allows it, to AAC; both go into
 * one MP4.  stop() can also copy the video into the phone's gallery
 * (Movies/Gen1Recomp) and returns its content URI.
 *
 * States: 0 idle, 1 recording, -1 failed.
 */
@Keep
@TargetApi(21)
public final class FoldRecorder {
    private static final String TAG = "FoldRecorder";
    private static final int RATE = 44100;

    private static final Object muxLock = new Object();
    private static volatile int state = 0;
    private static volatile boolean recording = false;

    private static MediaCodec video, audio;
    private static MediaMuxer muxer;
    private static int videoTrack = -1, audioTrack = -1;
    private static boolean muxing = false;
    private static final List<Sample> pending = new ArrayList<Sample>();
    private static final MediaCodec.BufferInfo videoInfo = new MediaCodec.BufferInfo();

    private static AudioRecord mic;
    private static Thread audioThread;
    private static long startNs;
    private static int width, height;
    private static String path;
    private static long lastVideoUs = -1;

    private static final class Sample {
        final boolean isVideo;
        final byte[] data;
        final MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();

        Sample(boolean isVideo, ByteBuffer buf, MediaCodec.BufferInfo from) {
            this.isVideo = isVideo;
            data = new byte[from.size];
            buf.position(from.offset);
            buf.get(data, 0, from.size);
            info.set(0, from.size, from.presentationTimeUs, from.flags);
        }
    }

    private FoldRecorder() {}

    private static Activity activity() {
        Context c = SDLActivity.getContext();
        return (c instanceof Activity) ? (Activity) c : null;
    }

    @Keep
    public static int state() {
        return state;
    }

    /** Start recording a w x h video (even sizes) into the file at `file`. */
    @Keep
    public static int start(String file, int w, int h, int fps) {
        if (Build.VERSION.SDK_INT < 21 || recording) return state = -1;
        width = w & ~1;
        height = h & ~1;
        path = file;
        videoTrack = audioTrack = -1;
        muxing = false;
        pending.clear();
        lastVideoUs = -1;
        try {
            new File(file).getParentFile().mkdirs();
            MediaFormat vf = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height);
            vf.setInteger(MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible);
            vf.setInteger(MediaFormat.KEY_BIT_RATE, Math.max(1000000, width * height * 5));
            vf.setInteger(MediaFormat.KEY_FRAME_RATE, Math.max(10, fps));
            vf.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1);
            video = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC);
            video.configure(vf, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            video.start();

            Activity a = activity();
            boolean withSound = a != null && ContextCompat.checkSelfPermission(a,
                Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
            if (withSound) {
                try {
                    int min = AudioRecord.getMinBufferSize(RATE, AudioFormat.CHANNEL_IN_MONO,
                        AudioFormat.ENCODING_PCM_16BIT);
                    mic = new AudioRecord(MediaRecorder.AudioSource.CAMCORDER, RATE,
                        AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT,
                        Math.max(min, 8192) * 2);
                    if (mic.getState() != AudioRecord.STATE_INITIALIZED) throw new IllegalStateException("mic");
                    MediaFormat af = MediaFormat.createAudioFormat(MediaFormat.MIMETYPE_AUDIO_AAC, RATE, 1);
                    af.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC);
                    af.setInteger(MediaFormat.KEY_BIT_RATE, 96000);
                    af.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384);
                    audio = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_AUDIO_AAC);
                    audio.configure(af, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
                    audio.start();
                } catch (Exception e) {
                    Log.d(TAG, "no sound: " + e);
                    releaseAudio();
                }
            }
            muxer = new MediaMuxer(file, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            startNs = System.nanoTime();
            recording = true;
            state = 1;
            if (audio != null) {
                audioThread = new Thread(new Runnable() {
                    @Override
                    public void run() { audioLoop(); }
                }, "FoldRecorderAudio");
                audioThread.start();
            }
        } catch (Exception e) {
            Log.d(TAG, "start: " + e);
            cleanup();
            new File(file).delete();
            return state = -1;
        }
        return state;
    }

    /** One frame, planar Y then U then V (4:2:0), width x height. */
    @Keep
    public static boolean frame(byte[] yuv) {
        if (!recording || video == null || yuv == null) return false;
        try {
            long us = (System.nanoTime() - startNs) / 1000;
            if (us <= lastVideoUs) us = lastVideoUs + 1;
            int index = video.dequeueInputBuffer(5000);
            if (index < 0) {
                drain(video, videoInfo, true, false);
                return false;
            }
            Image img = video.getInputImage(index);
            if (img == null) {
                video.queueInputBuffer(index, 0, 0, us, 0);
                return false;
            }
            fill(img, yuv);
            video.queueInputBuffer(index, 0, width * height * 3 / 2, us, 0);
            lastVideoUs = us;
            drain(video, videoInfo, true, false);
            return true;
        } catch (Exception e) {
            Log.d(TAG, "frame: " + e);
            return false;
        }
    }

    /**
     * Finish the file; with `toGallery` also copy it to the phone's gallery.
     * Returns the gallery copy's content URI, "" when there is none, or null
     * when nothing was recorded.
     */
    @Keep
    public static String stop(boolean toGallery) {
        if (!recording) return null;
        recording = false;
        boolean ok = false;
        try {
            if (audioThread != null) audioThread.join(3000);
        } catch (InterruptedException e) {
            // go on without it
        }
        try {
            int index = video.dequeueInputBuffer(20000);
            if (index >= 0) {
                long us = Math.max(lastVideoUs + 1, (System.nanoTime() - startNs) / 1000);
                video.queueInputBuffer(index, 0, 0, us, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                drain(video, videoInfo, true, true);
            }
        } catch (Exception e) {
            Log.d(TAG, "stop: " + e);
        }
        synchronized (muxLock) {
            try {
                if (muxing) {
                    muxer.stop();
                    ok = true;
                }
            } catch (Exception e) {
                Log.d(TAG, "muxer stop: " + e);
            }
        }
        cleanup();
        state = 0;
        if (!ok) {
            new File(path).delete();
            return null;
        }
        return toGallery ? copyToGallery(new File(path)) : "";
    }

    // ------------------------------------------------------------ the parts

    private static void fill(Image img, byte[] yuv) {
        Image.Plane[] p = img.getPlanes();
        int cw = width / 2, ch = height / 2;
        put(p[0], yuv, 0, width, height);
        put(p[1], yuv, width * height, cw, ch);
        put(p[2], yuv, width * height + cw * ch, cw, ch);
    }

    private static void put(Image.Plane plane, byte[] src, int off, int w, int h) {
        ByteBuffer b = plane.getBuffer();
        int rs = plane.getRowStride(), ps = plane.getPixelStride();
        for (int y = 0; y < h; y++) {
            int row = y * rs;
            if (ps == 1) {
                b.position(row);
                b.put(src, off + y * w, w);
            } else {
                for (int x = 0; x < w; x++) {
                    int at = row + x * ps;
                    if (at < b.limit()) b.put(at, src[off + y * w + x]);
                }
            }
        }
    }

    private static void audioLoop() {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        long samples = 0;
        long firstUs = -1;
        try {
            mic.startRecording();
            while (recording) {
                int index = audio.dequeueInputBuffer(10000);
                if (index >= 0) {
                    ByteBuffer b = audio.getInputBuffer(index);
                    b.clear();
                    int n = mic.read(b, Math.min(b.capacity(), 4096));
                    if (firstUs < 0) firstUs = (System.nanoTime() - startNs) / 1000;
                    long us = firstUs + samples * 1000000L / RATE;
                    if (n > 0) samples += n / 2;
                    audio.queueInputBuffer(index, 0, Math.max(0, n), us, 0);
                }
                drain(audio, info, false, false);
            }
            int index = audio.dequeueInputBuffer(20000);
            if (index >= 0) {
                long us = (firstUs < 0 ? 0 : firstUs) + samples * 1000000L / RATE;
                audio.queueInputBuffer(index, 0, 0, us, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                drain(audio, info, false, true);
            }
        } catch (Exception e) {
            Log.d(TAG, "audio: " + e);
        }
    }

    // the encoder's output into the muxer (held back until both tracks exist)
    private static void drain(MediaCodec codec, MediaCodec.BufferInfo info, boolean isVideo, boolean toEnd) {
        long giveUp = System.nanoTime() + 2000000000L;
        while (true) {
            int out = codec.dequeueOutputBuffer(info, toEnd ? 10000 : 0);
            if (out == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!toEnd || System.nanoTime() > giveUp) return;
                continue;
            }
            if (out == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                synchronized (muxLock) {
                    if (isVideo) videoTrack = muxer.addTrack(codec.getOutputFormat());
                    else audioTrack = muxer.addTrack(codec.getOutputFormat());
                    if (videoTrack >= 0 && (audio == null || audioTrack >= 0) && !muxing) {
                        muxer.start();
                        muxing = true;
                        for (Sample s : pending) {
                            muxer.writeSampleData(s.isVideo ? videoTrack : audioTrack,
                                ByteBuffer.wrap(s.data), s.info);
                        }
                        pending.clear();
                    }
                }
                continue;
            }
            if (out < 0) continue;
            ByteBuffer buf = codec.getOutputBuffer(out);
            boolean config = (info.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0;
            if (buf != null && info.size > 0 && !config) {
                synchronized (muxLock) {
                    if (muxing) {
                        buf.position(info.offset);
                        buf.limit(info.offset + info.size);
                        muxer.writeSampleData(isVideo ? videoTrack : audioTrack, buf, info);
                    } else if (pending.size() < 600) {
                        pending.add(new Sample(isVideo, buf, info));
                    }
                }
            }
            codec.releaseOutputBuffer(out, false);
            if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) return;
        }
    }

    private static void releaseAudio() {
        try { if (mic != null) { mic.stop(); } } catch (Exception e) { /* closing */ }
        try { if (mic != null) mic.release(); } catch (Exception e) { /* closing */ }
        try { if (audio != null) { audio.stop(); } } catch (Exception e) { /* closing */ }
        try { if (audio != null) audio.release(); } catch (Exception e) { /* closing */ }
        mic = null;
        audio = null;
    }

    private static void cleanup() {
        recording = false;
        releaseAudio();
        audioThread = null;
        try { if (video != null) video.stop(); } catch (Exception e) { /* closing */ }
        try { if (video != null) video.release(); } catch (Exception e) { /* closing */ }
        video = null;
        try { if (muxer != null) muxer.release(); } catch (Exception e) { /* closing */ }
        muxer = null;
        muxing = false;
        pending.clear();
    }

    private static String copyToGallery(File source) {
        Activity a = activity();
        if (a == null) return "";
        try {
            if (Build.VERSION.SDK_INT >= 29) {
                ContentResolver resolver = a.getContentResolver();
                ContentValues values = new ContentValues();
                values.put(MediaStore.MediaColumns.DISPLAY_NAME, source.getName());
                values.put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4");
                values.put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/Gen1Recomp");
                values.put(MediaStore.MediaColumns.IS_PENDING, 1);
                Uri uri = resolver.insert(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values);
                if (uri == null) return "";
                OutputStream out = resolver.openOutputStream(uri);
                InputStream in = new FileInputStream(source);
                try {
                    byte[] buf = new byte[65536];
                    int n;
                    while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
                } finally {
                    in.close();
                    if (out != null) out.close();
                }
                values.clear();
                values.put(MediaStore.MediaColumns.IS_PENDING, 0);
                resolver.update(uri, values, null, null);
                return uri.toString();
            }
            MediaScannerConnection.scanFile(a, new String[]{ source.getAbsolutePath() },
                new String[]{ "video/mp4" }, null);
        } catch (Exception e) {
            Log.d(TAG, "gallery: " + e);
        }
        return "";
    }
}
