// Azahar's settings for the 3DS HOME menu (Audio Dev).
//
// The 3DS UI draws every Azahar setting itself (fold3ds/azahar_settings.lua); Azahar's own settings
// screens are never shown.  Values live where Azahar keeps them, written the way Azahar writes them,
// so no Azahar source changes:
//
//   S/<ini section>/<key>   Azahar's config.ini, through its own SettingsFile + ini4j Wini (the same
//                           put/store as SettingsFile.saveFile), then NativeLibrary.reloadSettings()
//   Y/<field>               the emulated 3DS's system save (user name, birthday, language, country,
//                           sound output, play coins), through Azahar's own SystemSaveGame JNI
//   !<action> \t <args>     reset_to_default, console_id, mac_address: what Azahar's own buttons do;
//                           the System Files / GPU driver / Multiplayer ones are Fold3dsTools'.
//                           Actions run in order and are never merged; args are split on \u001F
//
// On/off values are "1"/"0" on the shell's side; keys Azahar keeps as BooleanSetting are written
// "true"/"false", because that is what Azahar's settings code reads back ("1".toBoolean() is false).
//
// The shell and this side talk through three files in the LÖVE save folder's fold3ds_azahar/:
//
//   settings.tsv          key \t value, every known value (written here; the shell reads it)
//   settings_pending.tsv  key \t value, changes the shell made (appended there; applied here)
//   settings_result.tsv   key \t reason, for each change that could NOT be applied, and
//                         !<action> \t ok | reason, for each action run
//
// Pending changes are applied as soon as the shell writes them (a FileObserver on each folder: the
// HOME menu runs in this process), and again whenever the HOME menu comes back to the front and
// before a game starts.  A running game gets config changes through reloadSettings, as Azahar's own
// in-game settings do; the system save is left alone while a game runs.
package org.citra.citra_emu.fold3ds

import android.content.Context
import android.net.Uri
import android.os.FileObserver
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import androidx.preference.PreferenceManager
import org.citra.citra_emu.CitraApplication
import org.citra.citra_emu.NativeLibrary
import org.citra.citra_emu.features.settings.model.BooleanSetting
import org.citra.citra_emu.features.settings.model.FloatSetting
import org.citra.citra_emu.features.settings.model.IntSetting
import org.citra.citra_emu.features.settings.model.ScaledFloatSetting
import org.citra.citra_emu.features.settings.model.Settings
import org.citra.citra_emu.features.settings.model.StringSetting
import org.citra.citra_emu.features.settings.utils.SettingsFile
import org.citra.citra_emu.utils.DirectoryInitialization
import org.citra.citra_emu.utils.SystemSaveGame
import org.ini4j.Wini

object Fold3dsSettings {
    private const val TAG = "Fold3dsSettings"
    private const val DIR = "fold3ds_azahar"
    private const val SNAP = "settings.tsv"
    private const val PENDING = "settings_pending.tsv"
    private const val RESULT = "settings_result.tsv"
    private val lock = Any()
    private val executor = Executors.newSingleThreadExecutor()
    private val queued = AtomicBoolean(false)
    private val watchers = HashMap<String, FileObserver>()   // folder -> its watcher (kept, or it stops)
    const val ARG = '\u001F'

    // config.ini sections the shell may write (Azahar's own names); anything else is refused
    private val SECTIONS = setOf(
        Settings.SECTION_CORE, Settings.SECTION_SYSTEM, Settings.SECTION_CAMERA, Settings.SECTION_CONTROLS,
        Settings.SECTION_RENDERER, Settings.SECTION_LAYOUT, Settings.SECTION_UTILITY, Settings.SECTION_NETWORK,
        Settings.SECTION_AUDIO, Settings.SECTION_DEBUG, Settings.SECTION_CUSTOM_LANDSCAPE,
        Settings.SECTION_CUSTOM_PORTRAIT, Settings.SECTION_PERFORMANCE_OVERLAY, Settings.SECTION_STORAGE,
        Settings.SECTION_MISC, "Data Storage"   // use_virtual_sd: no Settings constant, raw name
    )

    /** Apply every pending change, then publish a fresh snapshot. Safe to call from any thread. */
    fun sync(context: Context) {
        if (!Fold3dsBridge.ready(context)) return   // Azahar's folder isn't set up yet: nothing to read or write
        synchronized(lock) {
            try {
                Fold3dsTools.install(context)
                val folders = dirs(context)
                folders.forEach { watch(context, it) }
                for (dir in folders) apply(context, dir)
                publish(context)
            } catch (e: Throwable) {
                Log.e(TAG, "settings sync failed", e)
            }
        }
    }

    /** sync() on our own thread, once however often it is asked for meanwhile */
    fun syncSoon(context: Context) {
        if (!queued.compareAndSet(false, true)) return
        val app = context.applicationContext
        executor.execute {
            queued.set(false)
            sync(app)
        }
    }

    // the shell appends to settings_pending.tsv: apply it now, not at the next resume
    @Suppress("DEPRECATION")   // FileObserver(File, Int) is API 29+
    private fun watch(context: Context, dir: File) {
        val path = dir.absolutePath
        if (watchers.containsKey(path)) return
        val app = context.applicationContext
        val observer = object : FileObserver(path, CLOSE_WRITE or MOVED_TO) {
            override fun onEvent(event: Int, name: String?) {
                if (name == PENDING) syncSoon(app)
            }
        }
        observer.startWatching()
        watchers[path] = observer
    }

    // ---- applying --------------------------------------------------------------------------------

    private fun apply(context: Context, dir: File) {
        val pending = File(dir, PENDING)
        if (!pending.isFile) return
        // Take the file first: a change the shell makes while we apply lands in a fresh one.
        val taken = File(dir, "$PENDING.applying")
        if (!pending.renameTo(taken)) return
        val lines = taken.readLines().mapNotNull { line ->
            val i = line.indexOf('\t')
            if (i > 0) line.substring(0, i) to line.substring(i + 1) else null
        }
        // a reset throws away every setting change queued before it
        val reset = lines.indexOfLast { it.first == "!reset_to_default" }
        val failed = LinkedHashMap<String, String>()
        val changes = LinkedHashMap<String, String>()   // last write per key wins
        lines.forEachIndexed { i, (key, value) ->
            if (key.startsWith("!")) {
                failed[key] = runAction(context, key.substring(1), value)   // in order, every one
            } else if (i > reset) {
                changes[key] = value
            }
        }
        val ini = changes.filterKeys { it.startsWith("S/") }
        val sys = changes.filterKeys { it.startsWith("Y/") }
        changes.keys.filter { !it.startsWith("S/") && !it.startsWith("Y/") }
            .forEach { failed[it] = "Unknown setting" }
        if (ini.isNotEmpty()) writeIni(ini, failed)
        if (sys.isNotEmpty()) writeSystem(sys, failed)
        writeAtomic(File(dir, RESULT), failed.entries.joinToString("") { "${it.key}\t${it.value}\n" })
        taken.delete()
    }

    private fun writeIni(changes: Map<String, String>, failed: MutableMap<String, String>) {
        try {
            val ctx = CitraApplication.appContext
            val file = SettingsFile.getSettingsFile(SettingsFile.FILE_NAME_CONFIG)
            val ini = ctx.contentResolver.openInputStream(file.uri)!!.use { Wini(it) }
            for ((key, value) in changes) {
                val parts = key.split("/", limit = 3)
                if (parts.size != 3 || parts[1] !in SECTIONS || parts[2].isEmpty()) {
                    failed[key] = "Not an Azahar setting"
                    continue
                }
                ini.put(parts[1], parts[2], toIni(parts[2], value))
            }
            ctx.contentResolver.openOutputStream(file.uri, "wt")!!.use { ini.store(it); it.flush() }
        } catch (e: Exception) {
            changes.keys.forEach { failed.putIfAbsent(it, "Couldn't write Azahar's config.ini: ${e.message}") }
            return
        }
        try {
            NativeLibrary.reloadSettings()                      // a running Azahar picks the values up
        } catch (e: Throwable) {
            Log.w(TAG, "reloadSettings failed; values apply when the next game starts", e)
        }
    }

    private fun writeSystem(changes: Map<String, String>, failed: MutableMap<String, String>) {
        if (NativeLibrary.isRunning()) {
            changes.keys.forEach { failed[it] = "Close the game first" }
            return
        }
        try {
            SystemSaveGame.load()
            val birthday = SystemSaveGame.getBirthday()
            var month = birthday[0]
            var day = birthday[1]
            for ((key, value) in changes) {
                val n = value.trim().toIntOrNull()
                when (key.removePrefix("Y/")) {
                    "username" -> if (value.length in 1..10) SystemSaveGame.setUsername(value)
                                  else failed[key] = "Use 1 to 10 characters"
                    "birthday_month" -> if (n != null && n in 1..12) month = n.toShort() else failed[key] = "Month must be 1-12"
                    "birthday_day" -> if (n != null && n in 1..31) day = n.toShort() else failed[key] = "Day must be 1-31"
                    "language" -> if (n != null && n in 0..11) SystemSaveGame.setSystemLanguage(n) else failed[key] = "Unknown language"
                    "sound_output" -> if (n != null && n in 0..2) SystemSaveGame.setSoundOutputMode(n) else failed[key] = "Unknown sound mode"
                    "country" -> if (n != null && n in 0..255) SystemSaveGame.setCountryCode(n.toShort()) else failed[key] = "Unknown country"
                    "system_setup_needed" -> if (n == 0 || n == 1) SystemSaveGame.setSystemSetupNeeded(n == 1)
                                             else failed[key] = "On or Off only"
                    "play_coins" -> if (n != null && n in 0..300) SystemSaveGame.setPlayCoins(n) else failed[key] = "Play Coins must be 0-300"
                    else -> failed[key] = "Not a 3DS system setting"
                }
            }
            SystemSaveGame.setBirthday(month, day)
            SystemSaveGame.save()
        } catch (e: Throwable) {
            changes.keys.forEach { failed.putIfAbsent(it, "Couldn't write the 3DS system save: ${e.message}") }
        }
    }

    // "1"/"0" -> "true"/"false" for the keys Azahar's settings code reads as booleans
    private fun toIni(key: String, value: String): String =
        if (BooleanSetting.from(key) != null && (value == "1" || value == "0")) (value == "1").toString() else value

    private fun runAction(context: Context, id: String, value: String): String = try {
        when (id) {
            "reset_to_default" -> { resetToDefault(); "ok" }
            "console_id" -> { SystemSaveGame.load(); SystemSaveGame.regenerateConsoleId(); SystemSaveGame.save(); "ok" }
            "mac_address" -> { SystemSaveGame.load(); SystemSaveGame.regenerateMac(); SystemSaveGame.save(); "ok" }
            else -> Fold3dsTools.run(context, id, value.split(ARG)) ?: "Not available here"
        }
    } catch (e: Throwable) {
        Log.e(TAG, "action $id failed", e)
        "Failed: ${e.message}"
    }

    // SettingsActivity.onSettingsReset, step for step, without its screen
    private fun resetToDefault() {
        val ctx = CitraApplication.appContext
        val controllerKeys = Settings.buttonKeys + Settings.circlePadKeys + Settings.cStickKeys +
            Settings.dPadAxisKeys + Settings.dPadButtonKeys + Settings.triggerKeys
        val editor = PreferenceManager.getDefaultSharedPreferences(ctx).edit()
        controllerKeys.forEach { editor.remove(it) }
        editor.apply()
        BooleanSetting.clear()
        FloatSetting.clear()
        ScaledFloatSetting.clear()
        IntSetting.clear()
        StringSetting.clear()
        val settingsFile = SettingsFile.getSettingsFile(SettingsFile.FILE_NAME_CONFIG)
        check(settingsFile.delete()) { "Couldn't delete config.ini" }
        check(DirectoryInitialization.setCitraUserDirectory()) { "Azahar's folder is unavailable" }
        CitraApplication.documentsTree.setRoot(Uri.parse(DirectoryInitialization.userPath))
        NativeLibrary.createConfigFile()
        SystemSaveGame.load()
        SystemSaveGame.apply {
            setUsername("AZAHAR")
            setBirthday(11, 7)
            setSystemLanguage(1)
            setSoundOutputMode(1)
            setCountryCode(49)
            setPlayCoins(42)
        }
        SystemSaveGame.save()
        try {
            NativeLibrary.reloadSettings()
        } catch (e: Throwable) {
            Log.w(TAG, "reloadSettings failed", e)
        }
    }

    // ---- publishing ------------------------------------------------------------------------------

    private fun publish(context: Context) {
        val out = StringBuilder()
        try {
            val ctx = CitraApplication.appContext
            val file = SettingsFile.getSettingsFile(SettingsFile.FILE_NAME_CONFIG)
            val ini = ctx.contentResolver.openInputStream(file.uri)!!.use { Wini(it) }
            for (section in ini.values) {
                for ((key, value) in section) out.append("S/").append(section.name).append('/').append(key)
                    .append('\t').append(fromIni(value)).append('\n')
            }
        } catch (e: Exception) {
            Log.w(TAG, "couldn't read config.ini", e)
        }
        try {
            SystemSaveGame.load()
            val b = SystemSaveGame.getBirthday()
            out.append("Y/username\t").append(clean(SystemSaveGame.getUsername())).append('\n')
                .append("Y/birthday_month\t").append(b[0]).append('\n')
                .append("Y/birthday_day\t").append(b[1]).append('\n')
                .append("Y/language\t").append(SystemSaveGame.getSystemLanguage()).append('\n')
                .append("Y/sound_output\t").append(SystemSaveGame.getSoundOutputMode()).append('\n')
                .append("Y/country\t").append(SystemSaveGame.getCountryCode()).append('\n')
                .append("Y/play_coins\t").append(SystemSaveGame.getPlayCoins()).append('\n')
                .append("Y/console_id\t0x").append(java.lang.Long.toHexString(SystemSaveGame.getConsoleId()).uppercase())
                .append('\n')
                .append("Y/mac_address\t").append(clean(SystemSaveGame.getMac())).append('\n')
                .append("Y/system_setup_needed\t").append(if (SystemSaveGame.getIsSystemSetupNeeded()) 1 else 0)
                .append('\n')
        } catch (e: Throwable) {
            Log.w(TAG, "couldn't read the 3DS system save", e)
        }
        Fold3dsTools.snapshot(out)
        val folders = dirs(context)
        for (dir in folders) writeAtomic(File(dir, SNAP), out.toString())
        Fold3dsTools.publish(folders)
    }

    // the shell's side sees on/off as "1"/"0" whichever way Azahar wrote it
    private fun fromIni(v: String?): String = when (v?.trim()) {
        "true" -> "1"
        "false" -> "0"
        else -> clean(v?.trim())
    }

    fun clean(v: String?) = (v ?: "").replace('\t', ' ').replace('\n', ' ').replace('\r', ' ')

    // every LÖVE identity folder's fold3ds_azahar/, as Fold3dsBridge publishes the library there
    fun dirs(context: Context): List<File> {
        val out = ArrayList<File>()
        for (root in listOfNotNull(context.getExternalFilesDir(null), context.filesDir)) {
            File(root, "save").listFiles()?.forEach { if (it.isDirectory) out.add(File(it, DIR).apply { mkdirs() }) }
        }
        return out
    }

    // whole file or nothing, so the shell never reads half of it
    fun writeAtomic(f: File, text: String) {
        val tmp = File(f.parentFile, f.name + ".part")
        FileOutputStream(tmp).use { it.write(text.toByteArray(Charsets.UTF_8)) }
        tmp.renameTo(f)
    }
}
