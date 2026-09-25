// Azahar's System Files, GPU Drivers and Multiplayer, driven from the 3DS HOME menu (Audio Dev).
//
// Azahar's own screens for these (SystemFilesFragment, DriverManagerFragment, NetPlayDialog) are
// never shown.  What their buttons call is public in Azahar's Android layer, so it is called from
// here, the same way and in the same order - no Azahar source changes.
//
// Actions come through Fold3dsSettings' queue ("!<id>\t<arg>\u001F<arg>..."), and the result of
// each is written to settings_result.tsv ("ok", or why not).  What the shell reads back:
//
//   settings.tsv   Y/console_linked, Y/system_files_o3ds, Y/system_files_n3ds, Y/home_menu_<0-6>
//                  (the last three once "system_files_check" has run: it is slow), Y/gpu_driver
//                  (installed driver's name, "" = the phone's own), Y/gpu_custom_drivers (0/1),
//                  Y/netplay_joined, Y/netplay_moderator, Y/netplay_room ("<name>|<max players>"),
//                  Y/netplay_username_ok
//   drivers.tsv    one installed-but-maybe-unselected driver per line:
//                  uri \t name \t version \t vendor \t description
//   rooms.tsv      the public rooms, after "netplay_rooms":
//                  name \t has_password \t max \t ip \t port \t description \t owner \t game \t members
//   netplay.tsv    the room's life as it happens (appended live):  time \t type \t text
//                  type is Azahar's NetPlayStatus number (27 = chat "nick: text", 22-25 members come
//                  and go, 1-19 errors and states)
//   netplay_members.tsv  one member per line, while in a room
//
// Actions:   unlink_console · system_files_check · gpu_driver <uri|""> · gpu_driver_delete <uri>
//            netplay_rooms · netplay_join <ip> <port> <nickname> <password>
//            netplay_create <port> <nickname> <password> <room name> <max players>
//            netplay_leave · netplay_chat <text> · netplay_kick <nickname> · netplay_ban <nickname>
// What needs a screen of Android's (a file picker) or starts a game goes through
// Fold3dsLinkActivity instead: gpu_driver_add, system_files, home_menu.
package org.citra.citra_emu.fold3ds

import android.content.Context
import android.net.Uri
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import org.citra.citra_emu.NativeLibrary
import org.citra.citra_emu.utils.FileUtil.asDocumentFile
import org.citra.citra_emu.utils.FileUtil.inputStream
import org.citra.citra_emu.utils.GpuDriverHelper
import org.citra.citra_emu.utils.NetPlayManager

object Fold3dsTools {
    private const val TAG = "Fold3dsTools"
    private const val DRIVERS = "drivers.tsv"
    private const val ROOMS = "rooms.tsv"
    private const val NETPLAY = "netplay.tsv"
    private const val MEMBERS = "netplay_members.tsv"
    private const val REGIONS = 7                     // Japan, USA, Europe, Australia, China, Korea, Taiwan

    @Volatile private var installed = false
    @Volatile private var folders: List<File> = emptyList()
    private var systemFiles: BooleanArray? = null     // areSystemTitlesInstalled(), once asked for
    private var homeMenus: BooleanArray? = null
    private var rooms: String? = null                 // rooms.tsv's text, once asked for

    /** Once: follow the room (Azahar calls this listener for every multiplayer event). */
    fun install(context: Context) {
        if (installed) return
        installed = true
        val app = context.applicationContext
        NetPlayManager.setOnMessageReceivedListener { type, msg ->
            val line = "${SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())}\t$type\t" +
                Fold3dsSettings.clean(msg) + "\n"
            for (dir in folders) {
                try {
                    FileOutputStream(File(dir, NETPLAY), true).use { it.write(line.toByteArray(Charsets.UTF_8)) }
                } catch (e: Exception) {
                    Log.w(TAG, "couldn't log a multiplayer event", e)
                }
            }
            Fold3dsSettings.syncSoon(app)   // joined / members / moderator may have changed
        }
    }

    /** One action; null if it isn't one of ours. */
    fun run(context: Context, id: String, args: List<String>): String? = when (id) {
        "unlink_console" -> { NativeLibrary.unlinkConsole(); "ok" }
        "system_files_check" -> { checkSystemFiles(); "ok" }
        "gpu_driver" -> selectDriver(args.getOrElse(0) { "" })
        "gpu_driver_delete" -> deleteDriver(args.getOrElse(0) { "" })
        "netplay_rooms" -> { rooms = roomsText(); "ok" }
        "netplay_join" -> join(args)
        "netplay_create" -> create(context, args)
        "netplay_leave" -> { NetPlayManager.netPlayLeaveRoom(); NetPlayManager.clearChat(); "ok" }
        "netplay_chat" -> chat(args.getOrElse(0) { "" })
        "netplay_kick" -> moderate(args.getOrElse(0) { "" }) { NetPlayManager.netPlayKickUser(it) }
        "netplay_ban" -> moderate(args.getOrElse(0) { "" }) { NetPlayManager.netPlayBanUser(it) }
        else -> null
    }

    // ---- System Files (SystemFilesFragment) --------------------------------------------------------

    fun checkSystemFiles() {
        systemFiles = NativeLibrary.areSystemTitlesInstalled()
        homeMenus = BooleanArray(REGIONS) { NativeLibrary.getHomeMenuPath(it).isNotEmpty() }
    }

    // ---- GPU drivers (DriverManagerFragment + DriverViewModel) -------------------------------------

    private fun selectDriver(uri: String): String {
        if (!GpuDriverHelper.supportsCustomDriverLoading()) return "This phone can't load custom GPU drivers"
        if (uri.isEmpty()) {
            GpuDriverHelper.installDefaultDriver()
            return "ok"
        }
        val file = Uri.parse(uri).asDocumentFile()
        if (file == null || !file.exists()) {
            GpuDriverHelper.installDefaultDriver()
            return "That driver is gone; using the phone's own"
        }
        return if (GpuDriverHelper.installCustomDriverPartial(file.uri)) "ok" else "That driver didn't install"
    }

    private fun deleteDriver(uri: String): String {
        val file = Uri.parse(uri).asDocumentFile() ?: return "No such driver"
        val wasInUse = GpuDriverHelper.customDriverData == GpuDriverHelper.getMetadataFromZip(file.inputStream())
        if (!file.delete()) return "Couldn't delete it"
        if (wasInUse) GpuDriverHelper.installDefaultDriver()
        return "ok"
    }

    /** as DriverManagerFragment's picker: copy in, validate, refuse a duplicate. null = ok */
    fun addDriver(picked: Uri): String? {
        val copied = try {
            GpuDriverHelper.copyDriverToExternalStorage(picked)
        } catch (e: Exception) {
            null
        } ?: return "That isn't a GPU driver this phone can use"
        val meta = GpuDriverHelper.getMetadataFromZip(copied.inputStream())
        val same = GpuDriverHelper.getDrivers().count { it.second == meta }
        if (same > 1) {
            copied.delete()
            return "That driver is already installed"
        }
        return null
    }

    // ---- Multiplayer (NetPlayDialog) ---------------------------------------------------------------

    private fun roomsText(): String = NetPlayManager.getPublicRooms().joinToString("") { r ->
        listOf(
            r.name, if (r.hasPassword) "1" else "0", r.maxPlayers.toString(), r.ip, r.port.toString(),
            r.description, r.owner, r.preferredGameName, r.members.joinToString(", ") { it.nickname }
        ).joinToString("\t") { Fold3dsSettings.clean(it) } + "\n"
    }

    private fun nicknameProblem(nick: String): String? =
        if (!nick.matches(Regex("^[a-zA-Z0-9._\\- ]{4,20}$"))) "Nickname: 4-20 letters, numbers, . _ - or space" else null

    private fun join(a: List<String>): String {
        if (a.size < 3) return "Needs an address, a port and a nickname"
        val port = a[1].toIntOrNull() ?: return "The port is a number"
        nicknameProblem(a[2])?.let { return it }
        val result = NetPlayManager.netPlayJoinRoom(a[0], port, a[2], a.getOrElse(3) { "" })
        return if (result == 0) "ok" else "Couldn't join (error $result)"
    }

    private fun create(context: Context, a: List<String>): String {
        if (a.size < 5) return "Needs a port, a nickname, a password (may be empty), a room name and a size"
        val port = a[0].toIntOrNull() ?: return "The port is a number"
        nicknameProblem(a[1])?.let { return it }
        val max = a[4].toIntOrNull()?.takeIf { it in 2..16 } ?: return "2 to 16 players"
        if (a[3].isBlank()) return "The room needs a name"
        // NetPlayDialog hosts on the Wi-Fi address; no preferred game (the HOME menu has none picked).
        // It calls join/create on the main thread; they block on the network, so ours run on the
        // settings thread instead (Azahar's events still reach the listener through its Handler).
        val ip = wifiAddress(context) ?: return "Connect to Wi-Fi first"
        val result = NetPlayManager.netPlayCreateRoom(ip, port, a[1], "", 0L, a[2], a[3], max)
        return if (result == 0) "ok" else "Couldn't make the room (error $result)"
    }

    private fun chat(text: String): String {
        if (!NetPlayManager.netPlayIsJoined()) return "Not in a room"
        if (text.isBlank()) return "Nothing to send"
        NetPlayManager.netPlaySendMessage(text)
        return "ok"
    }

    private fun moderate(nick: String, what: (String) -> Unit): String {
        if (!NetPlayManager.netPlayIsModerator()) return "Only the room's host can do that"
        what(nick)
        return "ok"
    }

    @Suppress("DEPRECATION")
    private fun wifiAddress(context: Context): String? {
        val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? android.net.wifi.WifiManager
        val ip = wifi?.connectionInfo?.ipAddress ?: 0
        if (ip == 0) return null
        return "${ip and 0xff}.${ip shr 8 and 0xff}.${ip shr 16 and 0xff}.${ip shr 24 and 0xff}"
    }

    // ---- publishing --------------------------------------------------------------------------------

    fun snapshot(out: StringBuilder) {
        fun put(key: String, value: Any) = out.append("Y/").append(key).append('\t')
            .append(Fold3dsSettings.clean(value.toString())).append('\n')
        fun bit(b: Boolean) = if (b) 1 else 0
        try {
            put("console_linked", bit(NativeLibrary.isFullConsoleLinked()))
            systemFiles?.let {
                put("system_files_o3ds", bit(it.getOrElse(0) { false }))
                put("system_files_n3ds", bit(it.getOrElse(1) { false }))
            }
            homeMenus?.forEachIndexed { region, has -> put("home_menu_$region", bit(has)) }
        } catch (e: Throwable) {
            Log.w(TAG, "couldn't read the system files' state", e)
        }
        try {
            put("gpu_custom_drivers", bit(GpuDriverHelper.supportsCustomDriverLoading()))
            put("gpu_driver", GpuDriverHelper.customDriverData.name ?: "")
        } catch (e: Throwable) {
            Log.w(TAG, "couldn't read the GPU driver", e)
        }
        try {
            val joined = NetPlayManager.netPlayIsJoined()
            put("netplay_joined", bit(joined))
            put("netplay_moderator", bit(joined && NetPlayManager.netPlayIsModerator()))
            put("netplay_room", if (joined) NetPlayManager.netPlayRoomInfo().firstOrNull() ?: "" else "")
            put("netplay_username_ok", bit(NetPlayManager.isUsernameValid()))
        } catch (e: Throwable) {
            Log.w(TAG, "couldn't read the multiplayer state", e)
        }
    }

    fun publish(dirs: List<File>) {
        folders = dirs
        val drivers = try {
            GpuDriverHelper.getDrivers().drop(1).joinToString("") { (uri, m) ->   // [0] is the phone's own
                listOf(uri.toString(), m.name, m.version, m.vendor, m.description)
                    .joinToString("\t") { Fold3dsSettings.clean(it) } + "\n"
            }
        } catch (e: Throwable) {
            Log.w(TAG, "couldn't list GPU drivers", e)
            null
        }
        val members = try {
            if (NetPlayManager.netPlayIsJoined()) {
                NetPlayManager.netPlayRoomInfo().drop(1).joinToString("") { Fold3dsSettings.clean(it) + "\n" }
            } else ""
        } catch (e: Throwable) {
            ""
        }
        for (dir in dirs) {
            drivers?.let { Fold3dsSettings.writeAtomic(File(dir, DRIVERS), it) }
            rooms?.let { Fold3dsSettings.writeAtomic(File(dir, ROOMS), it) }
            Fold3dsSettings.writeAtomic(File(dir, MEMBERS), members)
        }
    }
}
