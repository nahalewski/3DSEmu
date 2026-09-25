// The 3DS HOME menu opening Azahar: the shell (LÖVE) calls
// love.system.openURL("fold3ds-azahar://<what>?<args>") and this invisible
// activity does it, then goes away, so whatever it opened sits right on top
// of the HOME menu and Back returns there.
//
//   play?key=K               start the 3DS game K (a key from games.tsv)
//   manual?key=K             the game's options (Azahar's About sheet)
//   settings?menu=M          an Azahar settings page (config = all of them)
//   add_games                add 3DS games: install CIA files or choose the games folder
//   install                  install CIA files
//   games_folder             choose the 3DS games folder
//   share_log                share Azahar's log
//   artic                    connect to an Artic Base server
//   azahar?open=X            Azahar's own screens (Fold3dsMain)
//   setup                    set Azahar up (below), then nothing else
//   refresh                  scan the library again
//
// Anything that needs Azahar's folder sets it up first, without Azahar's
// setup screens: all-files access (a switch in Android's settings, once),
// then the folder Azahar/ -- made beforehand, the picker opened inside it,
// so it is only "Use this folder" and "Allow", once -- which also holds the
// 3DS games (Azahar/games/).  Then what was asked for goes ahead.
package org.citra.citra_emu.fold3ds

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.view.LayoutInflater
import android.widget.Toast
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.widget.doOnTextChanged
import androidx.documentfile.provider.DocumentFile
import androidx.preference.PreferenceManager
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import org.citra.citra_emu.NativeLibrary
import org.citra.citra_emu.R
import org.citra.citra_emu.activities.EmulationActivity
import org.citra.citra_emu.contracts.OpenFileResultContract
import org.citra.citra_emu.databinding.DialogSoftwareKeyboardBinding
import org.citra.citra_emu.features.settings.SettingKeys
import org.citra.citra_emu.features.settings.model.Settings
import org.citra.citra_emu.features.settings.ui.SettingsActivity
import org.citra.citra_emu.features.settings.utils.SettingsFile
import org.citra.citra_emu.model.Game
import org.citra.citra_emu.ui.main.MainActivity
import org.citra.citra_emu.utils.CiaInstallWorker
import org.citra.citra_emu.utils.CitraDirectoryHelper
import org.citra.citra_emu.utils.FileBrowserHelper
import org.citra.citra_emu.utils.GameHelper
import org.citra.citra_emu.utils.Log
import org.citra.citra_emu.utils.PermissionsHandler
import java.io.File

class Fold3dsLinkActivity : AppCompatActivity() {
    private val ciaPicker = registerForActivityResult(OpenFileResultContract()) { result ->
        if (result != null) installCia(result)
        done()
    }

    private val gamesFolderPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { result ->
            if (result != null) setGamesFolder(result)
            done()
        }

    // DriverManagerFragment's picker: any file, validated as a driver zip after
    private val driverPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocument()) { result ->
            if (result == null) {
                done()
                return@registerForActivityResult
            }
            Toast.makeText(applicationContext, R.string.installing_driver, Toast.LENGTH_SHORT).show()
            val app = applicationContext
            Thread {
                val problem = Fold3dsTools.addDriver(result)
                Fold3dsSettings.sync(app)   // drivers.tsv lists it
                runOnUiThread {
                    Toast.makeText(app, problem ?: "Driver added -- choose it in GPU Drivers", Toast.LENGTH_LONG)
                        .show()
                    done()
                }
            }.start()
        }

    // set up first, then this link
    private var pending: Uri? = null

    private val allFilesAccess =
        registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
            if (allFiles()) pickAzaharFolder() else done()
        }

    private val azaharFolderPicker =
        registerForActivityResult(ActivityResultContracts.OpenDocumentTree()) { tree ->
            if (tree != null) finishSetup(tree) else done()
        }

    override fun onSaveInstanceState(outState: Bundle) {
        super.onSaveInstanceState(outState)
        pending?.let { outState.putString(KEY_PENDING, it.toString()) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        savedInstanceState?.getString(KEY_PENDING)?.let { pending = Uri.parse(it) }
        val uri = intent?.data
        // LÖVE opens links with NO_HISTORY, which would drop a picker's
        // result: come back once without it
        if ((intent.flags and Intent.FLAG_ACTIVITY_NO_HISTORY) != 0) {
            startActivity(Intent(this, Fold3dsLinkActivity::class.java).setData(uri))
            finish()
            overridePendingTransition(0, 0)
            return
        }
        if (savedInstanceState != null) return // a picker is (still) open
        if (uri == null || uri.scheme != SCHEME) {
            done()
            return
        }
        try {
            handle(uri)
        } catch (e: Exception) {
            android.util.Log.e("fold3ds", "could not open $uri", e)
            done()
        }
    }

    private fun handle(uri: Uri) {
        val what = uri.host ?: ""
        if (what == "setup" && Fold3dsBridge.ready(applicationContext)) {
            done()
            return
        }
        if (what == "refresh") {
            Fold3dsBridge.refresh(applicationContext)
            done()
            return
        }
        // everything else needs Azahar's folder: set it up first
        if (!Fold3dsBridge.ready(applicationContext)) {
            startSetup(uri)
            return
        }
        when (what) {
            "play" -> play(uri.getQueryParameter("key"))
            "manual" -> openMain(Fold3dsMain.OPEN_LIBRARY, uri.getQueryParameter("key"))
            "settings" -> {
                val menu = uri.getQueryParameter("menu")
                SettingsActivity.launch(
                    this,
                    if (menu.isNullOrEmpty() || menu == "config") SettingsFile.FILE_NAME_CONFIG else menu,
                    ""
                )
            }
            "add_games" -> {
                addGames()
                return
            }
            "install" -> {
                ciaPicker.launch(true)
                return
            }
            "games_folder" -> {
                gamesFolderPicker.launch(null)
                return
            }
            "share_log" -> shareLog()
            "artic" -> {
                artic()
                return
            }
            "azahar" -> openMain(uri.getQueryParameter("open"), null)
            "gpu_driver_add" -> {
                driverPicker.launch(arrayOf("*/*"))
                return
            }
            "system_files" -> {
                systemFiles(uri.getQueryParameter("mode"), uri.getQueryParameter("addr"))
                return
            }
            "home_menu" -> homeMenu(uri.getQueryParameter("region")?.toIntOrNull())
        }
        done()
    }

    // ---------------------------------------------------------------- setup

    // Android 11+: the all-files switch; Android 10 has storage permission
    private fun allFiles(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.R || Environment.isExternalStorageManager()

    private fun startSetup(then: Uri) {
        pending = then
        if (!allFiles()) {
            Toast.makeText(
                this,
                "Allow access to all files -- for 3DS games and their saves",
                Toast.LENGTH_LONG
            ).show()
            allFilesAccess.launch(
                Intent(
                    android.provider.Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.parse("package:$packageName")
                )
            )
            return
        }
        pickAzaharFolder()
    }

    private fun pickAzaharFolder() {
        val dir = File(Environment.getExternalStorageDirectory(), "Azahar")
        File(dir, "games").mkdirs()
        Toast.makeText(
            this,
            "Tap \"Use this folder\", then \"Allow\" -- once, for Azahar's data",
            Toast.LENGTH_LONG
        ).show()
        azaharFolderPicker.launch(
            DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents",
                "primary:Azahar"
            )
        )
    }

    // as SetupFragment and CitraDirectoryHelper do, without their screens
    private fun finishSetup(tree: Uri) {
        if (NativeLibrary.getNativePath(tree) == "") {
            Toast.makeText(this, R.string.invalid_user_directory, Toast.LENGTH_LONG).show()
            done()
            return
        }
        contentResolver.takePersistableUriPermission(
            tree,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        )
        CitraDirectoryHelper.initializeCitraDirectory(tree)
        val prefs = PreferenceManager.getDefaultSharedPreferences(applicationContext)
        val edit = prefs.edit().putBoolean(Settings.PREF_FIRST_APP_LAUNCH, false)
        if (prefs.getString(GameHelper.KEY_GAME_PATH, "").isNullOrEmpty()) {
            edit.putString(GameHelper.KEY_GAME_PATH, tree.toString())
        }
        edit.apply()
        Fold3dsBridge.refresh(applicationContext)
        val next = pending
        pending = null
        if (next != null && next.host != "setup" && Fold3dsBridge.ready(applicationContext)) {
            handle(next)
        } else {
            done()
        }
    }

    private fun done() {
        finish()
        overridePendingTransition(0, 0)
    }

    private fun openMain(open: String?, gameKey: String?) {
        startActivity(
            Intent(this, MainActivity::class.java).apply {
                if (open != null) putExtra(Fold3dsMain.EXTRA_OPEN, open)
                if (gameKey != null) putExtra(Fold3dsMain.EXTRA_GAME, gameKey)
            }
        )
    }

    private fun play(key: String?) {
        val game = key?.let { Fold3dsBridge.find(applicationContext, it) }
        if (game == null) {
            Toast.makeText(this, R.string.no_game_present, Toast.LENGTH_SHORT).show()
            Fold3dsBridge.refresh(applicationContext)
            return
        }
        Fold3dsSettings.sync(applicationContext)   // changes made in the HOME menu reach config.ini before boot
        start(game)
    }

    private fun start(game: Game) {
        PreferenceManager.getDefaultSharedPreferences(applicationContext).edit()
            .putLong(game.keyLastPlayedTime, System.currentTimeMillis())
            .apply()
        startActivity(
            Intent(this, EmulationActivity::class.java).putExtra("game", game)
        )
    }

    // the HOME menu's Add 3DS Games tile: the two ways a game gets in
    private fun addGames() {
        val choices = arrayOf(
            "Install CIA files (games, updates, DLC)",
            "Choose your 3DS games folder (.3ds, .cci, .cxi)"
        )
        var picked = false
        MaterialAlertDialogBuilder(this)
            .setTitle("Add 3DS Games")
            .setItems(choices) { _, which ->
                picked = true
                if (which == 0) ciaPicker.launch(true) else gamesFolderPicker.launch(null)
            }
            .setNegativeButton(android.R.string.cancel, null)
            .setOnDismissListener { if (!picked) done() }
            .show()
    }

    // as MainActivity.ciaFileInstaller
    private fun installCia(result: Intent) {
        val selected =
            FileBrowserHelper.getSelectedFiles(result, applicationContext, listOf("cia", "zcia"))
        if (selected == null) {
            Toast.makeText(applicationContext, R.string.cia_file_not_found, Toast.LENGTH_LONG)
                .show()
            return
        }
        WorkManager.getInstance(applicationContext).enqueueUniqueWork(
            "installCiaWork",
            ExistingWorkPolicy.APPEND_OR_REPLACE,
            OneTimeWorkRequest.Builder(CiaInstallWorker::class.java)
                .setInputData(Data.Builder().putStringArray("CIA_FILES", selected).build())
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
        )
        Toast.makeText(applicationContext, "Installing -- it shows up on the HOME menu when done",
            Toast.LENGTH_LONG).show()
        // the installed games join the HOME menu once the install is done
        Fold3dsBridge.refreshAfterInstall(applicationContext)
    }

    // as HomeSettingsFragment.getGamesDirectory
    private fun setGamesFolder(result: Uri) {
        contentResolver.takePersistableUriPermission(result, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        PreferenceManager.getDefaultSharedPreferences(applicationContext).edit()
            .putString(GameHelper.KEY_GAME_PATH, result.toString())
            .apply()
        Toast.makeText(applicationContext, R.string.games_dir_selected, Toast.LENGTH_LONG).show()
        Fold3dsBridge.refresh(applicationContext)
    }

    // as HomeSettingsFragment.shareLog
    private fun shareLog() {
        val logDirectory =
            DocumentFile.fromTreeUri(this, PermissionsHandler.citraDirectory)?.findFile("log")
        val currentLog = logDirectory?.findFile("azahar_log.txt")
        val oldLog = logDirectory?.findFile("azahar_log.old.txt")
        val log = if (!Log.gameLaunched && oldLog?.exists() == true) {
            oldLog
        } else if (currentLog?.exists() == true) {
            currentLog
        } else {
            null
        }
        if (log == null) {
            Toast.makeText(this, R.string.share_log_not_found, Toast.LENGTH_SHORT).show()
            return
        }
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_STREAM, log.uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(Intent.createChooser(intent, getText(R.string.share_log)))
    }

    // as SystemFilesFragment's "Set Up System Files": the 3DS UI asked which console and the address
    private fun systemFiles(mode: String?, address: String?) {
        if ((mode != "o3ds" && mode != "n3ds") || address.isNullOrBlank()) {
            done()
            return
        }
        val old3ds = mode == "o3ds"
        PreferenceManager.getDefaultSharedPreferences(applicationContext).edit()
            .putString(SettingKeys.last_artic_base_addr(), address)
            .apply()
        Toast.makeText(this, R.string.setup_system_files_preparing, Toast.LENGTH_SHORT).show()
        Thread {
            NativeLibrary.uninstallSystemFiles(old3ds)
            runOnUiThread {
                Fold3dsSettings.sync(applicationContext)
                start(
                    Game(
                        title = getString(R.string.artic_base),
                        path = (if (old3ds) "articinio://" else "articinin://") + address,
                        filename = ""
                    )
                )
                done()
            }
        }.start()
    }

    // as SystemFilesFragment's "Start HOME Menu", for one region (0 Japan ... 6 Taiwan)
    private fun homeMenu(region: Int?) {
        val path = region?.let { NativeLibrary.getHomeMenuPath(it) }.orEmpty()
        if (path.isEmpty()) {
            Toast.makeText(this, "That region's HOME Menu isn't installed", Toast.LENGTH_LONG).show()
            return
        }
        Fold3dsSettings.sync(applicationContext)
        start(Game(title = getString(R.string.home_menu), path = path, filename = ""))
    }

    // as HomeSettingsFragment's Artic Base entry
    private fun artic() {
        val prefs = PreferenceManager.getDefaultSharedPreferences(applicationContext)
        val input = DialogSoftwareKeyboardBinding.inflate(LayoutInflater.from(this))
        var address = prefs.getString(SettingKeys.last_artic_base_addr(), "") ?: ""
        input.editTextInput.setText(address)
        input.editTextInput.doOnTextChanged { text, _, _, _ -> address = text.toString() }
        MaterialAlertDialogBuilder(this)
            .setView(input.root)
            .setTitle(R.string.artic_base_enter_address)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                if (address.isNotEmpty()) {
                    prefs.edit().putString(SettingKeys.last_artic_base_addr(), address).apply()
                    start(
                        Game(
                            title = getString(R.string.artic_base),
                            path = "articbase://$address",
                            filename = ""
                        )
                    )
                }
            }
            .setNegativeButton(android.R.string.cancel, null)
            .setOnDismissListener { done() }
            .show()
    }

    companion object {
        const val SCHEME = "fold3ds-azahar"
        private const val KEY_PENDING = "fold3ds_pending"
    }
}
