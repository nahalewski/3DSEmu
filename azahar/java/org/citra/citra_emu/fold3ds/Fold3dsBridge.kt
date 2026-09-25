// The 3DS HOME menu (the LÖVE shell, org.love2d.android.GameActivity) and
// Azahar in one app.
//
// Azahar's side of the bridge: whenever the shell comes to the front, the
// 3DS library is scanned (GameHelper.getGames(), the same scan Azahar's own
// games list runs) and written where the shell can read it -- into every
// LÖVE save folder (<external or internal files>/save/<identity>/):
//
//   fold3ds_azahar/games.tsv      one line per game, tab separated
//   fold3ds_azahar/icons/<key>.png  the game's 48x48 icon
//
// games.tsv:
//   state<TAB>ready | setup          (setup: Azahar's folder is not chosen yet)
//   game<TAB>key<TAB>title<TAB>company<TAB>regions<TAB>icon 0|1<TAB>installed 0|1<TAB>system 0|1
//
// The other direction (the shell opening a game, a settings page, a tool)
// is Fold3dsLinkActivity.
package org.citra.citra_emu.fold3ds

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.os.Bundle
import android.util.Log
import androidx.preference.PreferenceManager
import java.io.File
import java.io.FileOutputStream
import java.nio.IntBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.serialization.json.Json
import org.citra.citra_emu.features.settings.model.Settings
import org.citra.citra_emu.model.Game
import org.citra.citra_emu.utils.CitraDirectoryUtils
import org.citra.citra_emu.utils.DirectoryInitialization
import org.citra.citra_emu.utils.GameHelper
import org.citra.citra_emu.utils.PermissionsHandler

object Fold3dsBridge {
    private const val TAG = "fold3ds"
    const val SHELL = "org.love2d.android.GameActivity"
    private const val DIR = "fold3ds_azahar"

    private val executor = Executors.newSingleThreadExecutor()
    private val queued = AtomicBoolean(false)

    // the last scan, by key (what the shell's tiles are named after)
    @Volatile
    private var byKey: Map<String, Game> = emptyMap()

    fun install(app: Application) {
        app.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                if (activity.javaClass.name == SHELL) refresh(activity.applicationContext)
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
            override fun onActivityStarted(activity: Activity) {}
            override fun onActivityPaused(activity: Activity) {}
            override fun onActivityStopped(activity: Activity) {}
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
            override fun onActivityDestroyed(activity: Activity) {}
        })
    }

    // Azahar's folder is chosen and set up (the scan needs it)
    fun ready(context: Context): Boolean {
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        if (prefs.getBoolean(Settings.PREF_FIRST_APP_LAUNCH, true)) return false
        if (!PermissionsHandler.hasWriteAccess(context)) return false
        if (CitraDirectoryUtils.needToUpdateManually()) return false
        if (!DirectoryInitialization.areCitraDirectoriesReady()) DirectoryInitialization.start()
        return DirectoryInitialization.areCitraDirectoriesReady()
    }

    // a tile's name: the title id (unique per game) and the file (the same
    // game as a cartridge dump and installed are two tiles)
    fun key(game: Game): String =
        "%016x_%08x".format(game.titleId, game.path.hashCode())

    fun refresh(context: Context) {
        if (!queued.compareAndSet(false, true)) return
        executor.execute {
            queued.set(false)
            try {
                scan(context)
            } catch (e: Throwable) {
                Log.e(TAG, "library scan failed", e)
            }
        }
    }

    // the game behind a tile; after a restart (no scan yet) Azahar's own
    // cached list answers
    fun find(context: Context, key: String): Game? {
        byKey[key]?.let { return it }
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        val cached = prefs.getStringSet(GameHelper.KEY_GAMES, emptySet()) ?: emptySet()
        val json = Json { ignoreUnknownKeys = true }
        for (s in cached) {
            val game = try {
                json.decodeFromString(Game.serializer(), s)
            } catch (e: Exception) {
                continue
            }
            if (key(game) == key) return game
        }
        return null
    }

    private fun scan(context: Context) {
        val out = StringBuilder()
        val icons = HashMap<String, Bitmap>()
        if (!ready(context)) {
            out.append("state\tsetup\n")
        } else {
            val games = GameHelper.getGames()
                .filter { it.valid && (!it.isSystemTitle || it.isVisibleSystemTitle) }
                .sortedBy { it.title.lowercase() }
            val map = LinkedHashMap<String, Game>()
            out.append("state\tready\n")
            for (g in games) {
                val k = key(g)
                if (map.containsKey(k)) continue
                map[k] = g
                val bmp = icon(g)
                if (bmp != null) icons[k] = bmp
                out.append("game\t").append(k)
                    .append('\t').append(clean(g.title))
                    .append('\t').append(clean(g.company))
                    .append('\t').append(clean(g.regions))
                    .append('\t').append(if (bmp != null) "1" else "0")
                    .append('\t').append(if (g.isInstalled) "1" else "0")
                    .append('\t').append(if (g.isSystemTitle) "1" else "0")
                    .append('\n')
            }
            byKey = map
        }
        val text = out.toString().toByteArray(Charsets.UTF_8)
        for (save in saveFolders(context)) {
            try {
                write(File(save, DIR), text, icons)
            } catch (e: Exception) {
                Log.w(TAG, "could not write the library into $save", e)
            }
        }
    }

    private fun clean(s: String): String = s.replace(Regex("[\\t\\r\\n]+"), " ").trim()

    // the SMDH icon as Azahar's own list draws it (48x48, RGB565 packed two
    // pixels to an int)
    private fun icon(game: Game): Bitmap? {
        val data = game.icon ?: return null
        return try {
            val bmp = Bitmap.createBitmap(48, 48, Bitmap.Config.RGB_565)
            bmp.copyPixelsFromBuffer(IntBuffer.wrap(data))
            bmp
        } catch (e: Exception) {
            null
        }
    }

    // every LÖVE identity folder, on external (the shell's choice on
    // Android) and internal storage
    private fun saveFolders(context: Context): List<File> {
        val roots = listOfNotNull(context.getExternalFilesDir(null), context.filesDir)
        val out = ArrayList<File>()
        for (root in roots) {
            val save = File(root, "save")
            save.listFiles()?.forEach { if (it.isDirectory) out.add(it) }
        }
        return out
    }

    private fun write(dir: File, list: ByteArray, icons: Map<String, Bitmap>) {
        val iconDir = File(dir, "icons")
        iconDir.mkdirs()
        val keep = HashSet<String>()
        for ((k, bmp) in icons) {
            val name = "$k.png"
            keep.add(name)
            val f = File(iconDir, name)
            if (f.exists()) continue
            val tmp = File(iconDir, "$name.part")
            FileOutputStream(tmp).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
            tmp.renameTo(f)
        }
        iconDir.listFiles()?.forEach { if (it.name !in keep) it.delete() }
        // the list last, whole, so the shell never reads half of it
        val tmp = File(dir, "games.tsv.part")
        FileOutputStream(tmp).use { it.write(list) }
        tmp.renameTo(File(dir, "games.tsv"))
    }
}
