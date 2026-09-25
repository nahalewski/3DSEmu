package org.citra.citra_emu.fold3ds

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Rect
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureResult
import android.hardware.camera2.TotalCaptureResult
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Where the viewer's head is, from the front camera, for the stereoscopic top screen.
 *
 * Uses camera2's own hardware face detection -- `STATISTICS_FACE_DETECT_MODE` --
 * rather than ML Kit: it is free, runs in the camera pipeline rather than on the
 * CPU, and adds no dependency to an APK that is already large. Ben's instruction,
 * relayed 2026-09-25: "camera2 STATISTICS_FACE_DETECT_MODE first (free,
 * hardware), checked per device." Checked it is -- a device that reports only
 * `STATISTICS_FACE_DETECT_MODE_OFF` gets [available] == false and the caller
 * falls back to a centred head, which is plain 2D-with-stereo-settings rather
 * than a broken screen.
 *
 * This deliberately does NOT reuse `org.love2d.android.FoldCamera`, which is in
 * the same APK. That class is owned by the launcher's camera app and holds the
 * device in static fields; camera access is exclusive, and two owners with
 * different lifecycles racing to open the front camera is a hang waiting to
 * happen. Emulation opens and closes its own, around its own lifecycle.
 *
 * Coordinates out of [headX] / [headY] are -1..1 with 0 centred, already
 * corrected for sensor orientation and for the front camera's mirroring, so a
 * viewer moving to their right always raises [headX].
 */
object Fold3dsHeadTracker {
    private const val TAG = "Fold3dsHead"

    // Face detection needs a target to drive the session but nothing reads the
    // pixels, so this is as small as the pipeline will politely accept.
    private const val W = 640
    private const val H = 480

    // One-pole smoothing. Raw face rectangles jitter by several pixels frame to
    // frame, and jitter fed into convergence is genuinely unpleasant to look at
    // -- it reads as the whole screen shivering. 0.15 settles in ~150 ms at
    // 30 fps while still feeling immediate.
    private const val SMOOTH = 0.15f

    // With no face, drift back to centre instead of freezing at the last
    // position: a frozen offset looks like a bug, a slow return looks intended.
    private const val DECAY = 0.04f

    @Volatile var available = false; private set
    @Volatile var tracking = false; private set

    /** -1..1, positive when the viewer moves to their own right. */
    @Volatile var headX = 0f; private set

    /** -1..1, positive when the viewer moves down. */
    @Volatile var headY = 0f; private set

    /**
     * Face width as a fraction of the frame, ~0.1 far to ~0.5 close, 0 when no
     * face. Proximity, not distance in any unit -- it is not calibrated and
     * should only drive relative depth.
     */
    @Volatile var headScale = 0f; private set

    private var manager: CameraManager? = null
    private var device: CameraDevice? = null
    private var session: CameraCaptureSession? = null
    private var reader: ImageReader? = null
    private var thread: HandlerThread? = null
    private var handler: Handler? = null
    private var faceMode = CameraMetadata.STATISTICS_FACE_DETECT_MODE_OFF
    private var activeArray: Rect? = null
    private var sensorOrientation = 0
    private var mirrored = true

    @Synchronized
    fun start(context: Context) {
        if (tracking) return
        if (context.checkSelfPermission(Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) {
            // Not an error worth shouting about: head tracking is an extra, and
            // the caller renders a centred head. The setting UI asks for the
            // permission; emulation does not interrupt a game to beg for it.
            Log.i(TAG, "no camera permission; head tracking stays off")
            available = false
            return
        }
        val mgr = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
        manager = mgr
        val id = frontCamera(mgr) ?: run {
            Log.i(TAG, "no front camera")
            available = false
            return
        }
        val chars = mgr.getCameraCharacteristics(id)
        val modes = chars.get(CameraCharacteristics.STATISTICS_INFO_AVAILABLE_FACE_DETECT_MODES)
            ?: intArrayOf()
        // SIMPLE is enough -- we want a rectangle, not landmarks. Prefer it over
        // FULL even when both exist, because FULL costs more in the pipeline for
        // data we throw away.
        faceMode = when {
            modes.contains(CameraMetadata.STATISTICS_FACE_DETECT_MODE_SIMPLE) ->
                CameraMetadata.STATISTICS_FACE_DETECT_MODE_SIMPLE
            modes.contains(CameraMetadata.STATISTICS_FACE_DETECT_MODE_FULL) ->
                CameraMetadata.STATISTICS_FACE_DETECT_MODE_FULL
            else -> CameraMetadata.STATISTICS_FACE_DETECT_MODE_OFF
        }
        if (faceMode == CameraMetadata.STATISTICS_FACE_DETECT_MODE_OFF) {
            Log.i(TAG, "device has no hardware face detection; head tracking unavailable")
            available = false
            return
        }
        activeArray = chars.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
        sensorOrientation = chars.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        mirrored = chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_FRONT

        thread = HandlerThread("fold3ds-head").also { it.start() }
        handler = Handler(thread!!.looper)
        try {
            open(mgr, id)
            available = true
            tracking = true
        } catch (e: Throwable) {
            Log.w(TAG, "could not start head tracking: $e")
            available = false
            stop()
        }
    }

    @Synchronized
    fun stop() {
        tracking = false
        try { session?.close() } catch (_: Throwable) {}
        try { device?.close() } catch (_: Throwable) {}
        try { reader?.close() } catch (_: Throwable) {}
        session = null; device = null; reader = null
        thread?.quitSafely()
        thread = null; handler = null
        headX = 0f; headY = 0f; headScale = 0f
    }

    private fun frontCamera(mgr: CameraManager): String? {
        for (id in mgr.cameraIdList) {
            val facing = mgr.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING)
            if (facing == CameraCharacteristics.LENS_FACING_FRONT) return id
        }
        return null
    }

    @Throws(CameraAccessException::class, SecurityException::class)
    private fun open(mgr: CameraManager, id: String) {
        val r = ImageReader.newInstance(W, H, ImageFormat.YUV_420_888, 2)
        // Nothing wants the pixels, but an unconsumed reader stalls the pipeline
        // and face results stop arriving, so every frame is acquired and dropped.
        r.setOnImageAvailableListener({ ir ->
            try { ir.acquireLatestImage()?.close() } catch (_: Throwable) {}
        }, handler)
        reader = r
        mgr.openCamera(id, object : CameraDevice.StateCallback() {
            override fun onOpened(cam: CameraDevice) {
                device = cam
                try {
                    val req = cam.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)
                    req.addTarget(r.surface)
                    req.set(CaptureRequest.STATISTICS_FACE_DETECT_MODE, faceMode)
                    cam.createCaptureSession(listOf(r.surface), object : CameraCaptureSession.StateCallback() {
                        override fun onConfigured(s: CameraCaptureSession) {
                            session = s
                            try {
                                s.setRepeatingRequest(req.build(), captureCallback, handler)
                            } catch (e: Throwable) {
                                Log.w(TAG, "repeating request failed: $e")
                            }
                        }
                        override fun onConfigureFailed(s: CameraCaptureSession) {
                            Log.w(TAG, "capture session configuration failed")
                            available = false
                        }
                    }, handler)
                } catch (e: Throwable) {
                    Log.w(TAG, "session setup failed: $e")
                    available = false
                }
            }
            override fun onDisconnected(cam: CameraDevice) { stop() }
            override fun onError(cam: CameraDevice, error: Int) {
                Log.w(TAG, "camera error $error")
                stop()
            }
        }, handler)
    }

    private val captureCallback = object : CameraCaptureSession.CaptureCallback() {
        override fun onCaptureCompleted(s: CameraCaptureSession, rq: CaptureRequest, result: TotalCaptureResult) {
            val faces = result.get(CaptureResult.STATISTICS_FACES)
            if (faces == null || faces.isEmpty()) {
                headX -= headX * DECAY
                headY -= headY * DECAY
                headScale -= headScale * DECAY
                return
            }
            // The largest face is the viewer. Someone behind them is smaller, and
            // picking "first" instead makes the screen lurch when a second face
            // enters and the driver reorders the list.
            var best = faces[0]
            var bestArea = area(best.bounds)
            for (f in faces) {
                val a = area(f.bounds)
                if (a > bestArea) { best = f; bestArea = a }
            }
            val array = activeArray ?: return
            val aw = array.width().toFloat()
            val ah = array.height().toFloat()
            if (aw <= 0f || ah <= 0f) return

            // Centre of the face in 0..1 of the sensor's active array.
            var nx = (best.bounds.exactCenterX() - array.left) / aw
            var ny = (best.bounds.exactCenterY() - array.top) / ah
            var scale = best.bounds.width() / aw

            // Sensor coordinates are not screen coordinates. A 270-degree front
            // sensor reports a head moving left as moving DOWN, which shows up as
            // the image sliding the wrong way along the wrong axis -- the kind of
            // thing that looks like a maths bug in the compositor when it is
            // really an unrotated rectangle.
            when (((sensorOrientation % 360) + 360) % 360) {
                90 -> { val t = nx; nx = ny; ny = 1f - t; scale = best.bounds.height() / ah }
                180 -> { nx = 1f - nx; ny = 1f - ny }
                270 -> { val t = nx; nx = 1f - ny; ny = t; scale = best.bounds.height() / ah }
            }
            // The front camera is a mirror: the viewer moving right moves the
            // face left in the frame. Undo it so headX follows the viewer.
            if (mirrored) nx = 1f - nx

            val targetX = (nx * 2f - 1f).coerceIn(-1f, 1f)
            val targetY = (ny * 2f - 1f).coerceIn(-1f, 1f)
            val targetS = scale.coerceIn(0f, 1f)
            headX += (targetX - headX) * SMOOTH
            headY += (targetY - headY) * SMOOTH
            headScale += (targetS - headScale) * SMOOTH
        }
    }

    private fun area(r: Rect): Int = max(0, r.width()) * max(0, r.height())

    /** Whether a head is currently being followed, for the settings screen to show. */
    fun hasHead(): Boolean = tracking && headScale > 0.02f

    /** One line for the settings screen and for `adb logcat` when Ben asks why it is flat. */
    fun status(): String = when {
        !available && !tracking -> "unavailable on this device"
        !tracking -> "off"
        hasHead() -> "tracking (x=%.2f y=%.2f size=%.2f)".format(headX, headY, headScale)
        else -> "no head in view"
    }
}
