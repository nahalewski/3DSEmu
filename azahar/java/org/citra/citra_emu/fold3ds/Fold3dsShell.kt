// A 3DS game played INSIDE the 3DS shell (fold3ds/emuplay.lua): Azahar's core
// runs in this process with no activity of its own, drawing into an
// ImageReader instead of a window.  Each frame is copied into one of two
// direct buffers; the shell reads the newest through LuaJIT's FFI (its
// address comes from addressOf, fold3ds_frames.cpp in Azahar's library) and
// draws the top screen on the shell's top panel and the touch screen below.
//
// The frame: Azahar's custom layout on a surface of 400s x 480s -- the top
// screen at (0, 0, 400s, 240s), the touch screen at (0, 240s, 320s, 240s),
// s = SCALE.  Buttons and the touch screen go straight into Azahar's input
// (the same path its on-screen buttons take).
//
// Reached from Lua through FoldBridge.call("3ds.<cmd>", arg): start, frame,
// key, stick, touch, pause, resume, save, load, stop, state.
package org.citra.citra_emu.fold3ds

import android.graphics.PixelFormat
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import java.nio.ByteBuffer
import org.citra.citra_emu.CitraApplication
import org.citra.citra_emu.NativeLibrary
import org.citra.citra_emu.NativeLibrary.ButtonType
import org.citra.citra_emu.display.PortraitScreenLayout
import org.citra.citra_emu.display.ScreenLayout
import org.citra.citra_emu.features.settings.model.IntSetting
import org.citra.citra_emu.features.settings.utils.SettingsFile
import org.citra.citra_emu.model.Game

object Fold3dsShell {
    private const val TAG = "fold3ds"
    const val SCALE = 2

    @JvmStatic
    external fun addressOf(buffer: ByteBuffer): Long

    private val lock = Any()

    @Volatile
    private var game: Game? = null

    @Volatile
    private var running = false

    @Volatile
    private var paused = false

    private var reader: ImageReader? = null
    private var readerThread: HandlerThread? = null
    private var emuThread: Thread? = null

    private val buffers = arrayOfNulls<ByteBuffer>(2)
    private val addresses = LongArray(2)

    @Volatile
    private var front = 0

    @Volatile
    private var serial = 0L

    private const val W = 400 * SCALE
    private const val H = 480 * SCALE

    @JvmStatic
    fun call(cmd: String, arg: String): String = try {
        when (cmd) {
            "start" -> start(arg)
            "frame" -> frame()
            "key" -> key(arg)
            "stick" -> stick(arg)
            "touch" -> touch(arg)
            "pause" -> pause(true)
            "resume" -> pause(false)
            "save" -> {
                NativeLibrary.saveState(arg.toIntOrNull() ?: 1)
                "ok"
            }
            "load" -> {
                NativeLibrary.loadState(arg.toIntOrNull() ?: 1)
                "ok"
            }
            "stop" -> stop()
            "state" -> if (running) (if (paused) "paused" else "running") else "stopped"
            else -> "error:unknown $cmd"
        }
    } catch (e: Throwable) {
        Log.e(TAG, "3ds.$cmd", e)
        "error:" + e.message
    }

    // ---------------------------------------------------------------- run

    private fun start(key: String): String {
        val context = CitraApplication.appContext
        if (running) return "error:running"
        if (!Fold3dsBridge.ready(context)) return "error:setup"
        val g = Fold3dsBridge.find(context, key) ?: return "error:nogame"
        synchronized(lock) {
            layoutForShell()
            for (i in 0..1) {
                val b = ByteBuffer.allocateDirect(W * H * 4)
                buffers[i] = b
                addresses[i] = addressOf(b)
            }
            serial = 0
            val t = HandlerThread("fold3ds-frames").also { it.start() }
            readerThread = t
            val r = ImageReader.newInstance(
                W,
                H,
                PixelFormat.RGBA_8888,
                3,
                HardwareBuffer.USAGE_GPU_COLOR_OUTPUT or HardwareBuffer.USAGE_CPU_READ_OFTEN
            )
            r.setOnImageAvailableListener({ onFrame(it) }, Handler(t.looper))
            reader = r
            game = g
            running = true
            paused = false
            NativeLibrary.surfaceChanged(r.surface)
            emuThread = Thread({
                try {
                    NativeLibrary.run(g.path)
                } catch (e: Throwable) {
                    Log.e(TAG, "3DS core stopped", e)
                }
                running = false
            }, "fold3ds-3ds").also { it.start() }
        }
        return "ok"
    }

    // the shell's frame: both screens stacked on one surface, top-left aligned
    private fun layoutForShell() {
        fun set(s: IntSetting, v: Int) {
            s.int = v
            SettingsFile.saveFile(SettingsFile.FILE_NAME_CONFIG, s)
        }
        val top = 240 * SCALE
        set(IntSetting.SCREEN_LAYOUT, ScreenLayout.CUSTOM_LAYOUT.int)
        set(IntSetting.LANDSCAPE_TOP_X, 0)
        set(IntSetting.LANDSCAPE_TOP_Y, 0)
        set(IntSetting.LANDSCAPE_TOP_WIDTH, 400 * SCALE)
        set(IntSetting.LANDSCAPE_TOP_HEIGHT, top)
        set(IntSetting.LANDSCAPE_BOTTOM_X, 0)
        set(IntSetting.LANDSCAPE_BOTTOM_Y, top)
        set(IntSetting.LANDSCAPE_BOTTOM_WIDTH, 320 * SCALE)
        set(IntSetting.LANDSCAPE_BOTTOM_HEIGHT, top)
        // the surface is taller than wide: Azahar may take the portrait
        // layout for it, so that one gets the same rects
        set(IntSetting.PORTRAIT_SCREEN_LAYOUT, PortraitScreenLayout.CUSTOM_PORTRAIT_LAYOUT.int)
        set(IntSetting.PORTRAIT_TOP_X, 0)
        set(IntSetting.PORTRAIT_TOP_Y, 0)
        set(IntSetting.PORTRAIT_TOP_WIDTH, 400 * SCALE)
        set(IntSetting.PORTRAIT_TOP_HEIGHT, top)
        set(IntSetting.PORTRAIT_BOTTOM_X, 0)
        set(IntSetting.PORTRAIT_BOTTOM_Y, top)
        set(IntSetting.PORTRAIT_BOTTOM_WIDTH, 320 * SCALE)
        set(IntSetting.PORTRAIT_BOTTOM_HEIGHT, top)
        // a later full-screen launch sets its own layout again
        Fold3dsEmulation.forgetApplied(CitraApplication.appContext)
    }

    private fun onFrame(r: ImageReader) {
        val image = try {
            r.acquireLatestImage()
        } catch (e: Exception) {
            null
        } ?: return
        try {
            val plane = image.planes[0]
            val src = plane.buffer
            val stride = plane.rowStride
            val back = 1 - front
            val dst = buffers[back] ?: return
            dst.clear()
            val row = W * 4
            if (stride == row) {
                src.limit(minOf(src.capacity(), row * H))
                dst.put(src)
            } else {
                for (y in 0 until H) {
                    src.limit(y * stride + row)
                    src.position(y * stride)
                    dst.put(src)
                }
            }
            front = back
            serial++
        } catch (e: Exception) {
            Log.w(TAG, "frame copy", e)
        } finally {
            image.close()
        }
    }

    // "hi:lo:width:height:serial:scale" -- the newest frame's address in two
    // 32-bit halves (a 64-bit pointer does not fit a Lua number)
    private fun frame(): String {
        if (!running && serial == 0L) return "none"
        val a = addresses[front]
        return "${(a ushr 32) and 0xffffffffL}:${a and 0xffffffffL}:$W:$H:$serial:$SCALE"
    }

    private fun pause(on: Boolean): String {
        if (!running) return "stopped"
        if (on && !paused) NativeLibrary.pauseEmulation()
        if (!on && paused) NativeLibrary.unPauseEmulation()
        paused = on
        return "ok"
    }

    fun stop(): String {
        synchronized(lock) {
            if (running) NativeLibrary.stopEmulation()
            try {
                emuThread?.join(5000)
            } catch (e: InterruptedException) {
            }
            emuThread = null
            running = false
            paused = false
            try {
                NativeLibrary.surfaceDestroyed()
            } catch (e: Throwable) {
            }
            reader?.close()
            reader = null
            readerThread?.quitSafely()
            readerThread = null
            game = null
        }
        return "ok"
    }

    // the HOME menu left the front (the phone's home button, a call): the
    // game waits; back in front it goes on unless its pause menu is open
    fun onShellPaused() {
        if (running && !paused) NativeLibrary.pauseEmulation()
    }

    fun onShellResumed() {
        if (running && !paused) NativeLibrary.unPauseEmulation()
    }

    // ---------------------------------------------------------------- input

    private val BUTTONS = mapOf(
        "a" to ButtonType.BUTTON_A, "b" to ButtonType.BUTTON_B,
        "x" to ButtonType.BUTTON_X, "y" to ButtonType.BUTTON_Y,
        "l" to ButtonType.TRIGGER_L, "r" to ButtonType.TRIGGER_R,
        "zl" to ButtonType.BUTTON_ZL, "zr" to ButtonType.BUTTON_ZR,
        "start" to ButtonType.BUTTON_START, "select" to ButtonType.BUTTON_SELECT,
        "up" to ButtonType.DPAD_UP, "down" to ButtonType.DPAD_DOWN,
        "left" to ButtonType.DPAD_LEFT, "right" to ButtonType.DPAD_RIGHT
    )

    // "name|1" pressed, "name|0" released
    private fun key(arg: String): String {
        if (!running) return "stopped"
        val name = arg.substringBefore('|')
        val down = arg.substringAfter('|', "1") == "1"
        val b = BUTTONS[name] ?: return "error:button $name"
        NativeLibrary.onGamePadEvent(
            NativeLibrary.TOUCHSCREEN_DEVICE,
            b,
            if (down) NativeLibrary.ButtonState.PRESSED else NativeLibrary.ButtonState.RELEASED
        )
        return "ok"
    }

    // the circle pad: "x|y", each -1..1
    private fun stick(arg: String): String {
        if (!running) return "stopped"
        val x = arg.substringBefore('|').toFloatOrNull() ?: 0f
        val y = arg.substringAfter('|', "0").toFloatOrNull() ?: 0f
        NativeLibrary.onGamePadMoveEvent(NativeLibrary.TOUCHSCREEN_DEVICE, ButtonType.STICK_LEFT, x, y)
        return "ok"
    }

    // "phase|u|v": pressed / moved / released at u, v (0..1) on the touch screen
    private fun touch(arg: String): String {
        if (!running) return "stopped"
        val p = arg.split('|')
        val phase = p.getOrNull(0) ?: return "error:touch"
        val u = p.getOrNull(1)?.toFloatOrNull() ?: 0f
        val v = p.getOrNull(2)?.toFloatOrNull() ?: 0f
        val x = u.coerceIn(0f, 1f) * 320 * SCALE
        val y = 240 * SCALE + v.coerceIn(0f, 1f) * 240 * SCALE
        when (phase) {
            "pressed" -> NativeLibrary.onTouchEvent(x, y, true)
            "moved" -> NativeLibrary.onTouchMoved(x, y)
            else -> NativeLibrary.onTouchEvent(x, y, false)
        }
        return "ok"
    }
}
