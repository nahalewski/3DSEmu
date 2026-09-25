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
//   fold3ds_azahar/icons/<key>_cart.png  a photo of its game card, from
//                                 GameTDB (art.gametdb.com/3ds/cart), by the
//                                 product code in the game's NCCH header
//
// games.tsv:
//   state<TAB>ready | setup          (setup: Azahar's folder is not chosen yet)
//   game<TAB>key<TAB>title<TAB>company<TAB>regions<TAB>icon 0|1<TAB>installed 0|1<TAB>system 0|1
//       <TAB>GameTDB id (e.g. ECLP, or empty)<TAB>cart 0|1
//       <TAB>the game file's path (a cartridge dump; empty when installed)
//       <TAB>title id (16 hex digits)
//   userdir<TAB>Azahar's folder, gamesdir<TAB>the 3DS games folder (paths, for
//   Download Play: a game goes to the same place on the other phone)
//
// The other direction (the shell opening a game, a settings page, a tool)
// is Fold3dsLinkActivity.
package org.citra.citra_emu.fold3ds

import android.app.Activity
import android.app.Application
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.util.Log
import androidx.lifecycle.Observer
import androidx.preference.PreferenceManager
import androidx.work.WorkInfo
import androidx.work.WorkManager
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.IntBuffer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.serialization.json.Json
import org.citra.citra_emu.NativeLibrary
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
            Fold3dsSettings.sync(context)   // apply the HOME menu's setting changes, publish the snapshot
            try {
                scan(context)
            } catch (e: Throwable) {
                Log.e(TAG, "library scan failed", e)
            }
        }
    }

    // after a CIA install (CiaInstallWorker, unique work "installCiaWork"):
    // scan again once every queued install has finished
    fun refreshAfterInstall(context: Context) {
        val app = context.applicationContext
        val live = WorkManager.getInstance(app).getWorkInfosForUniqueWorkLiveData("installCiaWork")
        live.observeForever(object : Observer<List<WorkInfo>> {
            // the list can first show the last install, already finished:
            // wait until this one has been seen running
            var running = false

            override fun onChanged(value: List<WorkInfo>) {
                if (value.any { !it.state.isFinished }) running = true
                if (running && value.all { it.state.isFinished }) {
                    live.removeObserver(this)
                    refresh(app)
                }
            }
        })
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

    private class Entry(val key: String, val game: Game, val icon: Bitmap?, val tdb: String?)

    private fun scan(context: Context) {
        val entries = ArrayList<Entry>()
        val ok = ready(context)
        if (ok) {
            // no games folder chosen: the Azahar folder is it (Download Play
            // puts cartridge dumps in its games/), no picker needed
            val prefs = PreferenceManager.getDefaultSharedPreferences(context)
            if (prefs.getString(GameHelper.KEY_GAME_PATH, "").isNullOrEmpty()) {
                prefs.edit()
                    .putString(GameHelper.KEY_GAME_PATH, PermissionsHandler.citraDirectory.toString())
                    .apply()
            }
            val games = GameHelper.getGames()
                .filter { it.valid && (!it.isSystemTitle || it.isVisibleSystemTitle) }
                .sortedBy { it.title.lowercase() }
            val map = LinkedHashMap<String, Game>()
            for (g in games) {
                val k = key(g)
                if (map.containsKey(k)) continue
                map[k] = g
                entries.add(Entry(k, g, icon(g), gameTdbId(context, g)))
            }
            byKey = map
        }
        publish(context, ok, entries)
        // the game cards' photos not fetched yet: fetch them, then say so
        var fetched = false
        for (e in entries) {
            val id = e.tdb ?: continue
            if (cartFile(context, id).exists() || id in failed) continue
            if (fetchCart(context, id)) fetched = true else failed.add(id)
        }
        if (fetched) publish(context, ok, entries)
    }

    private fun publish(context: Context, ready: Boolean, entries: List<Entry>) {
        val out = StringBuilder()
        val icons = HashMap<String, Bitmap>()
        val carts = HashMap<String, File>()
        out.append(if (ready) "state\tready\n" else "state\tsetup\n")
        if (ready) {
            val user = nativeOrEmpty { NativeLibrary.getUserDirectory() }
            out.append("userdir\t").append(user).append('\n')
            out.append("gamesdir\t").append(gamesDir(context, user)).append('\n')
        }
        for (e in entries) {
            if (e.icon != null) icons[e.key] = e.icon
            val cart = e.tdb?.let { cartFile(context, it) }?.takeIf { it.exists() }
            if (cart != null) carts[e.key] = cart
            val g = e.game
            out.append("game\t").append(e.key)
                .append('\t').append(clean(g.title))
                .append('\t').append(clean(g.company))
                .append('\t').append(clean(g.regions))
                .append('\t').append(if (e.icon != null) "1" else "0")
                .append('\t').append(if (g.isInstalled) "1" else "0")
                .append('\t').append(if (g.isSystemTitle) "1" else "0")
                .append('\t').append(e.tdb ?: "")
                .append('\t').append(if (cart != null) "1" else "0")
                .append('\t').append(if (g.isInstalled) "" else clean(gameFile(g)))
                .append('\t').append("%016x".format(g.titleId))
                .append('\n')
        }
        val text = out.toString().toByteArray(Charsets.UTF_8)
        for (save in saveFolders(context)) {
            try {
                write(File(save, DIR), text, icons, carts)
            } catch (e: Exception) {
                Log.w(TAG, "could not write the library into $save", e)
            }
        }
    }

    private fun nativeOrEmpty(f: () -> String): String = try {
        f()
    } catch (e: Exception) {
        ""
    }

    // the 3DS games folder as a path: the one chosen, or games/ in Azahar's
    // folder when that folder is the Azahar folder itself
    private fun gamesDir(context: Context, user: String): String {
        val prefs = PreferenceManager.getDefaultSharedPreferences(context)
        val chosen = prefs.getString(GameHelper.KEY_GAME_PATH, "") ?: ""
        if (chosen.isEmpty() || chosen == PermissionsHandler.citraDirectory.toString()) {
            return if (user.isEmpty()) "" else "$user/games"
        }
        return nativeOrEmpty { NativeLibrary.getNativePath(Uri.parse(chosen)) }
    }

    // a cartridge dump's path (the document Azahar found it as)
    private fun gameFile(game: Game): String {
        val raw = game.description
        return when {
            raw.startsWith("!") -> raw.substring(1)
            raw.startsWith("/") -> raw
            raw.startsWith("content://") -> nativeOrEmpty { NativeLibrary.getNativePath(Uri.parse(raw)) }
            else -> ""
        }
    }

    // ---------------------------------------------------------------- game cards

    // GameTDB ids whose card photo could not be fetched this run
    private val failed = HashSet<String>()

    private fun cartFile(context: Context, id: String) =
        File(File(context.filesDir, "fold3ds_carts"), "$id.png")

    // The game's GameTDB id: the last part of the product code in its NCCH
    // header (CTR-P-ECLE -> ECLE), read straight from the file -- a cartridge
    // dump (.3ds / .cci: the NCSD's first partition) or a single NCCH (.cxi,
    // an installed title's .app).  The header is never encrypted.
    private fun gameTdbId(context: Context, game: Game): String? {
        // a game in the games folder: the document it was found as (path is
        // Azahar's own "!native" form); an installed title: its .app
        val raw = if (game.isInstalled) null else game.description
        val uri = try {
            when {
                raw.isNullOrEmpty() -> game.launchIntent.data
                raw.startsWith("!") -> Uri.fromFile(File(raw.substring(1)))
                raw.startsWith("/") -> Uri.fromFile(File(raw))
                else -> Uri.parse(raw)
            }
        } catch (e: Exception) {
            null
        } ?: return null
        return try {
            context.contentResolver.openInputStream(uri)?.use { input ->
                val head = readBytes(input, 0x200) ?: return@use null
                val ncch = when (ascii(head, 0x100, 4)) {
                    "NCCH" -> head
                    "NCSD" -> {
                        val offset = u32(head, 0x120) * 0x200L
                        if (offset < 0x200 || !skipFully(input, offset - 0x200)) return@use null
                        readBytes(input, 0x200)
                    }
                    else -> null
                } ?: return@use null
                if (ascii(ncch, 0x100, 4) != "NCCH") return@use null
                val code = ascii(ncch, 0x150, 0x10).trimEnd('\u0000', ' ')
                code.substringAfterLast('-').takeIf { it.matches(Regex("[A-Z0-9]{4}")) }
            }
        } catch (e: Exception) {
            null
        }
    }

    private fun readBytes(input: InputStream, n: Int): ByteArray? {
        val buf = ByteArray(n)
        var got = 0
        while (got < n) {
            val r = input.read(buf, got, n - got)
            if (r < 0) return null
            got += r
        }
        return buf
    }

    private fun skipFully(input: InputStream, n: Long): Boolean {
        var left = n
        while (left > 0) {
            val k = input.skip(left)
            if (k <= 0) {
                if (input.read() < 0) return false
                left -= 1
            } else {
                left -= k
            }
        }
        return true
    }

    private fun ascii(b: ByteArray, at: Int, n: Int): String =
        String(b, at, n, Charsets.US_ASCII)

    private fun u32(b: ByteArray, at: Int): Long =
        (b[at].toLong() and 0xff) or ((b[at + 1].toLong() and 0xff) shl 8) or
            ((b[at + 2].toLong() and 0xff) shl 16) or ((b[at + 3].toLong() and 0xff) shl 24)

    // GameTDB's photo of the game card, in the game's own region's language
    // first (E USA, P Europe, J Japan, K Korea ...)
    private fun fetchCart(context: Context, id: String): Boolean {
        val first = when (id.last()) {
            'E' -> "US"
            'J' -> "JA"
            'K' -> "KO"
            'D' -> "DE"
            'F' -> "FR"
            'S' -> "ES"
            'I' -> "IT"
            'H' -> "NL"
            else -> "EN"
        }
        val langs = LinkedHashSet(listOf(first, "EN", "US", "JA", "DE", "FR", "ES", "IT", "NL", "KO"))
        for (lang in langs) {
            try {
                val conn = URL("https://art.gametdb.com/3ds/cart/$lang/$id.png")
                    .openConnection() as HttpURLConnection
                conn.connectTimeout = 8000
                conn.readTimeout = 15000
                conn.setRequestProperty("User-Agent", "gen1recomp-Fold (3DS HOME menu)")
                try {
                    if (conn.responseCode != 200) continue
                    val bytes = conn.inputStream.use { it.readBytes() }
                    // only a real picture is kept
                    BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: continue
                    val f = cartFile(context, id)
                    f.parentFile?.mkdirs()
                    val tmp = File(f.parentFile, "$id.part")
                    tmp.writeBytes(bytes)
                    return tmp.renameTo(f)
                } finally {
                    conn.disconnect()
                }
            } catch (e: Exception) {
                Log.i(TAG, "no card photo for $id in $lang: ${e.message}")
            }
        }
        return false
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

    private fun write(dir: File, list: ByteArray, icons: Map<String, Bitmap>, carts: Map<String, File>) {
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
        for ((k, src) in carts) {
            val name = "${k}_cart.png"
            keep.add(name)
            val f = File(iconDir, name)
            if (f.exists() && f.length() == src.length()) continue
            val tmp = File(iconDir, "$name.part")
            src.copyTo(tmp, overwrite = true)
            tmp.renameTo(f)
        }
        iconDir.listFiles()?.forEach { if (it.name !in keep) it.delete() }
        // the list last, whole, so the shell never reads half of it
        val tmp = File(dir, "games.tsv.part")
        FileOutputStream(tmp).use { it.write(list) }
        tmp.renameTo(File(dir, "games.tsv"))
    }
}
