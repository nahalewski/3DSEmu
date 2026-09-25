// A 3DS game started from the HOME menu, set up the way the fold plays every
// emulator's games:
//
//   * screens: "full" (the default) fills the Fold's top half with the top
//     screen and its bottom half with the touch screen -- Azahar's custom
//     layout, sized from this phone's display; "native" is Azahar's own
//     stacked layout at the 3DS's proportions.  Applied only when the mode or
//     the display changes, so a layout set by hand in Azahar's settings stays.
//   * a gamepad: mapped the first time one is connected (Azahar's own
//     auto-map, without its "press A" dialog), unless something is mapped
//     already.  Its HOME / guide button closes the game, back to the HOME
//     menu (EmulationActivity's hook, azahar-fold3ds.patch).
package org.citra.citra_emu.fold3ds

import android.app.Activity
import android.content.Context
import android.os.Build
import android.util.DisplayMetrics
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import androidx.preference.PreferenceManager
import org.citra.citra_emu.display.ScreenLayout
import org.citra.citra_emu.features.settings.model.IntSetting
import org.citra.citra_emu.features.settings.model.view.InputBindingSetting
import org.citra.citra_emu.features.settings.utils.SettingsFile
import org.citra.citra_emu.utils.EmulationLifecycleUtil

object Fold3dsEmulation {
    const val FULL = "full"
    const val NATIVE = "native"

    private const val PREF_SCREENS = "fold3ds_screens"
    private const val PREF_APPLIED = "fold3ds_screens_applied"
    private const val PREF_PAD = "fold3ds_pad_mapped"

    private fun prefs(context: Context) =
        PreferenceManager.getDefaultSharedPreferences(context.applicationContext)

    fun screens(context: Context): String =
        if (prefs(context).getString(PREF_SCREENS, FULL) == NATIVE) NATIVE else FULL

    fun setScreens(context: Context, mode: String) {
        prefs(context).edit().putString(PREF_SCREENS, if (mode == NATIVE) NATIVE else FULL).apply()
    }

    // Fold3dsLinkActivity, just before a game starts
    fun beforeLaunch(activity: Activity) {
        try {
            applyScreens(activity)
        } catch (e: Exception) {
            android.util.Log.w("fold3ds", "screen layout not applied", e)
        }
        try {
            mapGamepad(activity)
        } catch (e: Exception) {
            android.util.Log.w("fold3ds", "gamepad not mapped", e)
        }
    }

    // ---------------------------------------------------------------- screens

    private fun applyScreens(activity: Activity) {
        val (w, h) = landscapeSize(activity)
        val mode = screens(activity)
        val stamp = "$mode:${w}x$h"
        val p = prefs(activity)
        if (p.getString(PREF_APPLIED, "") == stamp) return
        if (mode == FULL) {
            val half = h / 2
            set(IntSetting.SCREEN_LAYOUT, ScreenLayout.CUSTOM_LAYOUT.int)
            set(IntSetting.LANDSCAPE_TOP_X, 0)
            set(IntSetting.LANDSCAPE_TOP_Y, 0)
            set(IntSetting.LANDSCAPE_TOP_WIDTH, w)
            set(IntSetting.LANDSCAPE_TOP_HEIGHT, half)
            set(IntSetting.LANDSCAPE_BOTTOM_X, 0)
            set(IntSetting.LANDSCAPE_BOTTOM_Y, half)
            set(IntSetting.LANDSCAPE_BOTTOM_WIDTH, w)
            set(IntSetting.LANDSCAPE_BOTTOM_HEIGHT, h - half)
        } else {
            set(IntSetting.SCREEN_LAYOUT, ScreenLayout.ORIGINAL.int)
        }
        p.edit().putString(PREF_APPLIED, stamp).apply()
    }

    private fun set(setting: IntSetting, value: Int) {
        setting.int = value
        SettingsFile.saveFile(SettingsFile.FILE_NAME_CONFIG, setting)
    }

    // the whole display, held landscape (the fold's hinge across the middle)
    private fun landscapeSize(activity: Activity): Pair<Int, Int> {
        val w: Int
        val h: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val b = activity.windowManager.maximumWindowMetrics.bounds
            w = b.width()
            h = b.height()
        } else {
            val m = DisplayMetrics()
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay.getRealMetrics(m)
            w = m.widthPixels
            h = m.heightPixels
        }
        return Pair(maxOf(w, h), minOf(w, h))
    }

    // ---------------------------------------------------------------- gamepad

    private fun mapGamepad(context: Context) {
        val p = prefs(context)
        if (p.getBoolean(PREF_PAD, false)) return
        val pad = InputDevice.getDeviceIds().asSequence()
            .mapNotNull { InputDevice.getDevice(it) }
            .firstOrNull {
                it.sources and InputDevice.SOURCE_GAMEPAD == InputDevice.SOURCE_GAMEPAD ||
                    it.sources and InputDevice.SOURCE_JOYSTICK == InputDevice.SOURCE_JOYSTICK
            } ?: return
        // something mapped already (by hand or an earlier auto-map): keep it
        val mapped = p.all.keys.any { it.startsWith("InputMapping") }
        if (!mapped) {
            if (InputBindingSetting.isJoyCon(pad)) {
                InputBindingSetting.applyJoyConBindings()
            } else {
                val name = pad.name.lowercase()
                val nintendo = "nintendo" in name || "switch" in name || "8bitdo" in name
                val axisDpad = pad.motionRanges.any { it.axis == MotionEvent.AXIS_HAT_X }
                InputBindingSetting.applyAutoMapBindings(nintendo, axisDpad)
            }
        }
        p.edit().putBoolean(PREF_PAD, true).apply()
    }

    // EmulationActivity.dispatchKeyEvent: HOME / guide on a gamepad closes the
    // game, back to the HOME menu
    fun onKey(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_BUTTON_MODE) return false
        if (event.action == KeyEvent.ACTION_UP) EmulationLifecycleUtil.closeGame()
        return true
    }
}
